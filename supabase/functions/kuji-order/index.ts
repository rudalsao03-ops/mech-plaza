// =====================================================================
//  럭키슬랩 쿠지 · 카페24 주문 확인 함수 (Supabase Edge Function: kuji-order)
//
//  POST /kuji-order            {"order_id":"20261111-0000001"}          → 결제 확인 후 즉시 뽑기, 결과 반환
//  POST /kuji-order            {"order_id":"...", "check":true}          → 쿠지 상품 주문인지만 확인 (주문완료 페이지용)
//  GET  /kuji-order/connect                                              → 카페24 연결 시작 (운영자가 한 번만)
//  GET  /kuji-order/callback?code=..&state=..                             → 카페24가 돌려보내는 주소
//
//  필요한 비밀값 (Supabase → Edge Functions → Secrets):
//    CAFE24_MALL_ID        예) luckyslap
//    CAFE24_CLIENT_ID      카페24 개발자센터 앱의 Client ID
//    CAFE24_CLIENT_SECRET  카페24 개발자센터 앱의 Client Secret
//  (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY 는 Supabase가 자동으로 넣어줌)
//  ※ 이 함수는 "Verify JWT" 를 꺼야 함 (카페24 페이지·리다이렉트에서 호출되므로)
// =====================================================================
import { createClient } from 'npm:@supabase/supabase-js@2';

const env = (k: string) => Deno.env.get(k) ?? '';
const MALL = env('CAFE24_MALL_ID');
const CLIENT_ID = env('CAFE24_CLIENT_ID');
const CLIENT_SECRET = env('CAFE24_CLIENT_SECRET');
const SB_URL = env('SUPABASE_URL');
const API = `https://${MALL}.cafe24api.com/api/v2`;
const REDIRECT = `${SB_URL}/functions/v1/kuji-order/callback`;
const SCOPES = 'mall.read_order';

const sb = createClient(SB_URL, env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false } });

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type, authorization, apikey, x-client-info',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json; charset=utf-8' } });
const page = (title: string, msg: string, status = 200) =>
  new Response(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>
<body style="font-family:sans-serif;background:#0e111a;color:#f3edda;display:flex;align-items:center;justify-content:center;min-height:90vh;text-align:center">
<div><h2>${title}</h2><p>${msg}</p></div></body>`, { status, headers: { 'Content-Type': 'text/html; charset=utf-8' } });

async function rpc<T = unknown>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await sb.rpc(fn, args);
  if (error) throw new Error(`${fn}: ${error.message}`);
  return data as T;
}

// 카페24 시간 표기(시간대 없으면 한국시간)를 Date로
const kst = (s?: string | null) => (!s ? null : new Date(/[zZ]|[+-]\d\d:?\d\d$/.test(s) ? s : s + '+09:00'));
const basic = () => 'Basic ' + btoa(`${CLIENT_ID}:${CLIENT_SECRET}`);

async function saveTokens(t: Record<string, string>) {
  await rpc('kuji_svc_token_save', {
    p_access: t.access_token, p_refresh: t.refresh_token,
    p_expires: kst(t.expires_at)?.toISOString() ?? new Date(Date.now() + 7000e3).toISOString(),
    p_refresh_expires: kst(t.refresh_token_expires_at)?.toISOString() ?? new Date(Date.now() + 13 * 864e5).toISOString(),
  });
}
async function tokenRequest(body: Record<string, string>) {
  const r = await fetch(`${API}/oauth/token`, {
    method: 'POST',
    headers: { Authorization: basic(), 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(body).toString(),
  });
  const t = await r.json().catch(() => ({}));
  if (!r.ok || !t.access_token) throw new Error('카페24 토큰 발급 실패: ' + JSON.stringify(t).slice(0, 300));
  return t;
}
// 유효한 액세스 토큰 (만료 5분 전이면 갱신)
async function accessToken(): Promise<string> {
  const t = await rpc<Record<string, string> | null>('kuji_svc_token_get');
  if (!t || !t.refresh_token) throw new Error('카페24 연결이 아직 안 됐어요 (운영자: /kuji-order/connect)');
  const exp = t.expires_at ? new Date(t.expires_at).getTime() : 0;
  if (t.access_token && exp - Date.now() > 5 * 60e3) return t.access_token;
  const nt = await tokenRequest({ grant_type: 'refresh_token', refresh_token: t.refresh_token });
  await saveTokens(nt);
  return nt.access_token;
}

type Item = { product_no?: number | string; quantity?: number | string; status_code?: string; claim_code?: string | null };
type Order = { order_id: string; paid?: string; canceled?: string; billing_name?: string; buyer?: { name?: string }; items?: Item[] };

async function getOrder(orderId: string): Promise<Order | null> {
  const tok = await accessToken();
  const r = await fetch(`${API}/admin/orders/${encodeURIComponent(orderId)}?embed=items,buyer`, {
    headers: { Authorization: `Bearer ${tok}`, 'Content-Type': 'application/json' },
  });
  if (r.status === 404) return null;
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error('카페24 주문 조회 실패: ' + JSON.stringify(j).slice(0, 300));
  return j.order ?? null;
}

const mask = (n?: string) => { const s = (n || '').trim(); return s ? s[0] + '*'.repeat(Math.min(Math.max(s.length - 1, 1), 2)) : '손님'; };
// 취소·반품·교환 접수된 상품줄은 제외 (status_code: C=취소, R=반품, E=교환)
const activeItem = (it: Item) => !(it.status_code && /^[CRE]/i.test(it.status_code));

async function handleOrder(orderId: string, check: boolean) {
  if (!/^\d{8}-\d{7}$/.test(orderId)) return json({ status: 'bad_order', message: '주문번호 형식이 아니에요' }, 400);
  const products = new Set((await rpc<(number | string)[]>('kuji_svc_products')).map(Number));
  const order = await getOrder(orderId);
  if (!order) return json({ status: 'not_found', message: '주문을 찾을 수 없어요' }, 404);
  const qty = new Map<number, number>();
  for (const it of order.items ?? []) {
    const no = Number(it.product_no), q = Number(it.quantity) || 0;
    if (products.has(no) && q > 0 && activeItem(it)) qty.set(no, (qty.get(no) ?? 0) + q);
  }
  if (!qty.size) return json({ status: 'none', kuji: false });
  if (order.canceled === 'T') return json({ status: 'canceled', kuji: true, message: '취소된 주문이에요' });
  if (order.paid !== 'T') return json({ status: 'unpaid', kuji: true, message: '아직 결제(입금)가 확인되지 않았어요. 입금 확인 후 다시 열어주세요' });
  if (check) return json({ status: 'ok', kuji: true });
  const buyer = mask(order.billing_name || order.buyer?.name);
  const boards = [];
  for (const [no, q] of qty) {
    const r = await rpc('kuji_order_draw', { p_order: orderId, p_product: no, p_qty: Math.min(q, 1000), p_buyer: buyer });
    if (r) boards.push(r);
  }
  return json({ status: 'ok', kuji: true, order_id: orderId, who: buyer, boards });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  const url = new URL(req.url);
  try {
    if (!MALL || !CLIENT_ID || !CLIENT_SECRET) return json({ status: 'not_configured', message: 'CAFE24_* 비밀값이 아직 설정 안 됐어요' }, 500);

    if (req.method === 'GET' && url.pathname.endsWith('/connect')) {
      const state = crypto.randomUUID();
      await rpc('kuji_svc_state_set', { p_state: state });
      const auth = `${API}/oauth/authorize?` + new URLSearchParams({ response_type: 'code', client_id: CLIENT_ID, state, redirect_uri: REDIRECT, scope: SCOPES });
      return Response.redirect(auth, 302);
    }

    if (req.method === 'GET' && url.pathname.endsWith('/callback')) {
      const code = url.searchParams.get('code'), state = url.searchParams.get('state');
      const t = await rpc<Record<string, string> | null>('kuji_svc_token_get');
      if (!code || !state || !t || t.oauth_state !== state) return page('연결 실패', '요청이 맞지 않아요. 관리자 페이지에서 다시 시도해주세요.', 400);
      await saveTokens(await tokenRequest({ grant_type: 'authorization_code', code, redirect_uri: REDIRECT }));
      return page('✅ 카페24 연결 완료', '이제 결제하면 바로 뽑기가 돼요. 이 창은 닫아도 돼요.');
    }

    if (req.method === 'POST') {
      const body = await req.json().catch(() => ({}));
      return await handleOrder(String(body.order_id ?? '').trim(), !!body.check);
    }
    return json({ status: 'bad_request' }, 400);
  } catch (e) {
    console.error(e);
    return json({ status: 'error', message: e instanceof Error ? e.message : String(e) }, 500);
  }
});
