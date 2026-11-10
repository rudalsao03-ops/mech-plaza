-- =====================================================================
--  럭키슬랩 쿠지 서버 (Supabase SQL Editor에 통째로 붙여넣고 Run)
--  · 판을 열 때 서버가 표 전체를 섞어서 순서를 고정하고, 그 순서의 지문(SHA-256)을 공개
--  · 뽑기는 서버 함수(kuji_draw)로만 가능 → 손님 브라우저에선 조작 불가
--  · 판이 끝나면 섞을 때 쓴 비밀값(salt)을 공개 → 누구나 지문 검증 가능
--  · 여러 번 실행해도 안전 (이미 있으면 건너뜀). 맨 아래 "관리자 비밀번호"만 꼭 바꿔서 실행
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- 테이블 ----------
create table if not exists kuji_admin (
  id int primary key default 1 check (id = 1),
  secret_hash text not null
);

create table if not exists kuji_boards (
  id bigint generated always as identity primary key,
  slug text unique not null check (slug ~ '^[a-z0-9-]{2,40}$'),
  title text not null check (char_length(title) between 1 and 60),
  price int not null check (price >= 0),
  total int not null check (total between 1 and 20000),
  mode text not null default 'auto' check (mode in ('auto', 'live')),
  test_mode boolean not null default true,
  status text not null default 'open' check (status in ('open', 'closed')),
  hash text not null,
  salt text,                       -- 판이 열려 있는 동안엔 비어 있음. 마감되면 공개
  sort int not null default 0,
  created_at timestamptz not null default now(),
  closed_at timestamptz
);

create table if not exists kuji_board_secrets (   -- 열린 판의 salt 보관 (외부 접근 불가)
  board_id bigint primary key references kuji_boards on delete cascade,
  salt text not null
);

create table if not exists kuji_prizes (
  board_id bigint not null references kuji_boards on delete cascade,
  idx int not null,
  grade text not null check (grade in ('S', 'A', 'B', 'C', 'D', 'LAST')),
  name text not null check (char_length(name) between 1 and 60),
  img text,
  qty int not null check (qty between 1 and 20000),
  primary key (board_id, idx)
);

create table if not exists kuji_tickets (          -- 섞인 표 (no = 뽑히는 순서). 외부에서 직접 못 봄
  board_id bigint not null references kuji_boards on delete cascade,
  no int not null,
  prize_idx int not null,
  grade text not null,
  name text not null,
  draw_id bigint,
  primary key (board_id, no)
);
create index if not exists kuji_tickets_next on kuji_tickets (board_id, no) where draw_id is null;

create table if not exists kuji_draws (            -- 추첨 기록 (공개)
  id bigint generated always as identity primary key,
  board_id bigint not null references kuji_boards on delete cascade,
  no int not null,
  prize_idx int not null,
  grade text not null,
  name text not null,
  who text not null,
  batch uuid not null,
  created_at timestamptz not null default now()
);
create index if not exists kuji_draws_board on kuji_draws (board_id, id desc);

create table if not exists kuji_codes (            -- 뽑기 코드 (결제 1건 = 코드 1개, 수량만큼 뽑기)
  code text primary key,
  board_id bigint not null references kuji_boards on delete cascade,
  qty int not null check (qty between 1 and 1000),
  used int not null default 0,
  memo text,
  created_at timestamptz not null default now()
);

-- 카페24 결제 연동
alter table kuji_boards add column if not exists cafe24_product_no int unique;   -- 이 판과 연결된 카페24 상품번호
alter table kuji_draws add column if not exists order_id text;
do $$ begin
  if to_regclass('public.kuji_orders') is not null then alter table kuji_orders add column if not exists short int not null default 0; end if;
end $$;
create index if not exists kuji_draws_order on kuji_draws (order_id) where order_id is not null;

create table if not exists kuji_orders (           -- 카페24 주문 1줄 = 이 판 n회 (결제 확인된 것만 들어옴)
  order_id text not null,
  board_id bigint not null references kuji_boards on delete cascade,
  qty int not null check (qty between 1 and 1000),
  drawn int not null default 0,
  short int not null default 0,                   -- 표가 모자라 못 뽑은 횟수 (환불 대상)
  buyer text,
  created_at timestamptz not null default now(),
  primary key (order_id, board_id)
);

create table if not exists kuji_cafe24 (           -- 카페24 API 토큰 (서버 함수만 접근)
  id int primary key default 1 check (id = 1),
  access_token text,
  refresh_token text,
  expires_at timestamptz,
  refresh_expires_at timestamptz,
  oauth_state text,
  updated_at timestamptz default now()
);

-- ---------- 접근 권한 (RLS) ----------
alter table kuji_admin enable row level security;
alter table kuji_boards enable row level security;
alter table kuji_board_secrets enable row level security;
alter table kuji_prizes enable row level security;
alter table kuji_tickets enable row level security;
alter table kuji_draws enable row level security;
alter table kuji_codes enable row level security;
alter table kuji_orders enable row level security;
alter table kuji_cafe24 enable row level security;

drop policy if exists "kuji boards read" on kuji_boards;
create policy "kuji boards read" on kuji_boards for select using (true);
drop policy if exists "kuji prizes read" on kuji_prizes;
create policy "kuji prizes read" on kuji_prizes for select using (true);
drop policy if exists "kuji draws read" on kuji_draws;
create policy "kuji draws read" on kuji_draws for select using (true);
-- kuji_admin, kuji_board_secrets, kuji_tickets, kuji_codes, kuji_orders, kuji_cafe24 는 정책 없음 = 외부에서 읽기·쓰기 전부 불가
-- 모든 쓰기는 아래 함수(security definer)를 통해서만 가능

-- ---------- 내부 함수 ----------
create or replace function _kuji_is_admin(p_key text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  select secret_hash into h from kuji_admin where id = 1;
  if h is null or p_key is null or crypt(p_key, h) <> h then
    perform pg_sleep(0.5);           -- 비밀번호 무작위 대입 늦추기
    return false;
  end if;
  return true;
end $$;

create or replace function _kuji_clean(p text, n int) returns text
language sql immutable as $$
  select left(regexp_replace(btrim(coalesce(p, '')), '[<>[:cntrl:]]', '', 'g'), n)
$$;

-- 다음 표 n장을 꺼내서 기록 (판 행을 잠가서 동시에 뽑아도 같은 표가 두 번 안 나감)
create or replace function _kuji_take(p_board bigint, p_n int, p_who text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_batch uuid := gen_random_uuid();
  v_res jsonb;
  v_left int;
begin
  with picked as (
    select board_id, no, prize_idx, grade, name from kuji_tickets
    where board_id = p_board and draw_id is null
    order by no limit p_n
  ), ins as (
    insert into kuji_draws (board_id, no, prize_idx, grade, name, who, batch)
    select board_id, no, prize_idx, grade, name, p_who, v_batch from picked
    returning id, no, prize_idx, grade, name
  ), upd as (
    update kuji_tickets t set draw_id = ins.id from ins
    where t.board_id = p_board and t.no = ins.no
    returning t.no
  )
  select coalesce(jsonb_agg(jsonb_build_object('no', ins.no, 'grade', ins.grade, 'name', ins.name,
           'img', (select img from kuji_prizes p where p.board_id = p_board and p.idx = ins.prize_idx)) order by ins.no), '[]'::jsonb)
    into v_res from ins where exists (select 1 from upd where upd.no = ins.no);

  select count(*) into v_left from kuji_tickets where board_id = p_board and draw_id is null;
  if v_left = 0 then
    update kuji_boards b set status = 'closed', closed_at = now(),
      salt = (select salt from kuji_board_secrets s where s.board_id = p_board)
    where b.id = p_board;
  end if;
  return jsonb_build_object('results', v_res, 'left', v_left, 'closed', v_left = 0, 'batch', v_batch);
end $$;

-- ---------- 공개 함수 (누구나 호출) ----------

-- 판 목록 (열린 판 + 최근 마감 판)
create or replace function kuji_list() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(x order by (x->>'status') = 'closed', (x->>'sort')::int, (x->>'id')::bigint desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', b.id, 'slug', b.slug, 'title', b.title, 'price', b.price, 'total', b.total, 'mode', b.mode,
      'test', b.test_mode, 'status', b.status, 'sort', b.sort, 'product_no', b.cafe24_product_no,
      'left', (select count(*) from kuji_tickets t where t.board_id = b.id and t.draw_id is null),
      'hits_left', (select count(*) from kuji_tickets t where t.board_id = b.id and t.draw_id is null and t.grade in ('S','A','B','LAST')),
      's_left', (select count(*) from kuji_tickets t where t.board_id = b.id and t.draw_id is null and t.grade = 'S'),
      'imgs', (select coalesce(jsonb_agg(p.img order by p.idx), '[]'::jsonb) from (select img, idx from kuji_prizes p where p.board_id = b.id and p.img is not null order by idx limit 3) p)
    ) x
    from kuji_boards b
    where b.status = 'open' or b.closed_at > now() - interval '14 days'
  ) s
$$;

-- 판 상세 (상품별 남은 수량, 최근 결과, 지문)
create or replace function kuji_state(p_slug text) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select case when b.id is null then null else jsonb_build_object(
    'id', b.id, 'slug', b.slug, 'title', b.title, 'price', b.price, 'total', b.total, 'mode', b.mode,
    'test', b.test_mode, 'status', b.status, 'hash', b.hash, 'salt', b.salt, 'product_no', b.cafe24_product_no,
    'left', (select count(*) from kuji_tickets t where t.board_id = b.id and t.draw_id is null),
    'prizes', (select coalesce(jsonb_agg(jsonb_build_object('idx', p.idx, 'grade', p.grade, 'name', p.name, 'img', p.img, 'qty', p.qty,
                 'left', (select count(*) from kuji_tickets t where t.board_id = b.id and t.prize_idx = p.idx and t.draw_id is null)) order by p.idx), '[]'::jsonb)
               from kuji_prizes p where p.board_id = b.id),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('no', d.no, 'grade', d.grade, 'name', d.name, 'who', d.who, 'at', d.created_at) order by d.id desc), '[]'::jsonb)
               from (select * from kuji_draws d where d.board_id = b.id order by d.id desc limit 30) d)
  ) end
  from (select 1) one left join kuji_boards b on b.slug = p_slug
$$;

-- 뽑기 (테스트 판은 코드 없이 1회 최대 10장, 실제 판은 결제로 받은 코드 필요)
create or replace function kuji_draw(p_slug text, p_count int, p_who text, p_code text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  b kuji_boards%rowtype;
  c kuji_codes%rowtype;
  v_left int;
  v_n int;
  v_res jsonb;
  v_who text := coalesce(nullif(_kuji_clean(p_who, 10), ''), '익명');
begin
  select * into b from kuji_boards where slug = p_slug for update;   -- 이 판 뽑기는 한 번에 하나씩
  if b.id is null then raise exception '판을 찾을 수 없어요'; end if;
  if b.status <> 'open' then raise exception '이미 마감된 판이에요'; end if;
  if b.mode <> 'auto' then raise exception '라이브 판은 방송에서만 뽑을 수 있어요'; end if;
  select count(*) into v_left from kuji_tickets where board_id = b.id and draw_id is null;
  v_n := least(greatest(coalesce(p_count, 1), 1), 10, v_left);

  if not b.test_mode then
    select * into c from kuji_codes where code = upper(_kuji_clean(p_code, 20)) and board_id = b.id for update;
    if c.code is null then perform pg_sleep(0.3); raise exception '뽑기 코드가 맞지 않아요'; end if;
    if c.used >= c.qty then raise exception '이미 다 사용한 코드예요'; end if;
    v_n := least(v_n, c.qty - c.used);
  end if;

  v_res := _kuji_take(b.id, v_n, v_who);
  if not b.test_mode then
    update kuji_codes set used = used + jsonb_array_length(v_res->'results') where code = c.code;
    v_res := v_res || jsonb_build_object('code_left', c.qty - c.used - jsonb_array_length(v_res->'results'));
  end if;
  return v_res;
end $$;

-- 코드 확인 (주문 완료 화면에서 넘어왔을 때 남은 횟수 표시용)
create or replace function kuji_code_info(p_code text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare r record;
begin
  select k.qty, k.used, b.slug, b.title into r from kuji_codes k join kuji_boards b on b.id = k.board_id
  where k.code = upper(_kuji_clean(p_code, 20));
  if r is null then perform pg_sleep(0.3); return null; end if;
  return jsonb_build_object('slug', r.slug, 'title', r.title, 'qty', r.qty, 'left', r.qty - r.used);
end $$;

-- 마감된 판의 원래 순서 공개 (지문 검증용)
create or replace function kuji_reveal(p_slug text) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select case when b.status = 'closed' then jsonb_build_object('salt', b.salt, 'hash', b.hash,
    'order', (select string_agg(t.no || ':' || t.grade || ':' || t.name, '|' order by t.no) from kuji_tickets t where t.board_id = b.id))
  end from kuji_boards b where b.slug = p_slug
$$;

-- ---------- 관리자 함수 (관리자 비밀번호 필요) ----------
create or replace function kuji_admin_check(p_key text) returns boolean
language sql security definer set search_path = public, extensions as $$ select _kuji_is_admin(p_key) $$;

-- 판 열기: p_prizes = [{"grade":"S","name":"리자몽 VMAX","img":"cards/x.jpg","qty":1}, ...]
create or replace function kuji_open(p_key text, p_slug text, p_title text, p_price int, p_prizes jsonb,
  p_mode text default 'auto', p_test boolean default true, p_sort int default 0) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id bigint;
  v_total int;
  v_salt text := encode(gen_random_bytes(16), 'hex');
  v_order text;
  v_hash text;
begin
  if not _kuji_is_admin(p_key) then raise exception '관리자 비밀번호가 틀렸어요'; end if;
  if jsonb_typeof(p_prizes) <> 'array' or jsonb_array_length(p_prizes) = 0 then raise exception '상품 구성이 비어 있어요'; end if;
  select sum((e->>'qty')::int) into v_total from jsonb_array_elements(p_prizes) e;
  if v_total is null or v_total < 1 or v_total > 20000 then raise exception '전체 구수는 1~20000 사이여야 해요'; end if;

  insert into kuji_boards (slug, title, price, total, mode, test_mode, sort, hash)
  values (lower(p_slug), _kuji_clean(p_title, 60), p_price, v_total, p_mode, p_test, p_sort, 'pending')
  returning id into v_id;

  insert into kuji_prizes (board_id, idx, grade, name, img, qty)
  select v_id, (o - 1)::int, e->>'grade', _kuji_clean(e->>'name', 60), nullif(_kuji_clean(e->>'img', 200), ''), (e->>'qty')::int
  from jsonb_array_elements(p_prizes) with ordinality as a(e, o);

  -- 표를 전부 만들고 암호학적 난수로 섞어서 순서(no)를 고정
  insert into kuji_tickets (board_id, no, prize_idx, grade, name)
  select v_id, row_number() over (order by gen_random_uuid())::int, p.idx, p.grade, p.name
  from kuji_prizes p cross join lateral generate_series(1, p.qty)
  where p.board_id = v_id;

  select string_agg(no || ':' || grade || ':' || name, '|' order by no) into v_order from kuji_tickets where board_id = v_id;
  v_hash := encode(digest(v_salt || '|' || v_order, 'sha256'), 'hex');
  update kuji_boards set hash = v_hash where id = v_id;
  insert into kuji_board_secrets (board_id, salt) values (v_id, v_salt);
  return jsonb_build_object('slug', lower(p_slug), 'total', v_total, 'hash', v_hash);
end $$;

-- 뽑기 코드 발급 (지금은 직접 발급, 나중엔 카페24 결제와 자동 연동)
create or replace function kuji_issue_code(p_key text, p_slug text, p_qty int, p_memo text default null) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare v_b bigint; v_code text;
begin
  if not _kuji_is_admin(p_key) then raise exception '관리자 비밀번호가 틀렸어요'; end if;
  select id into v_b from kuji_boards where slug = p_slug and status = 'open';
  if v_b is null then raise exception '열린 판이 아니에요'; end if;
  v_code := upper(encode(gen_random_bytes(6), 'hex'));
  v_code := substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4) || '-' || substr(v_code, 9, 4);
  insert into kuji_codes (code, board_id, qty, memo) values (v_code, v_b, p_qty, _kuji_clean(p_memo, 100));
  return v_code;
end $$;

-- 라이브 판 뽑기 (방송 중 운영자가 대신 뽑음) — 테스트·자동 판에도 사용 가능
create or replace function kuji_live_draw(p_key text, p_slug text, p_count int, p_who text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare b kuji_boards%rowtype;
begin
  if not _kuji_is_admin(p_key) then raise exception '관리자 비밀번호가 틀렸어요'; end if;
  select * into b from kuji_boards where slug = p_slug for update;
  if b.id is null or b.status <> 'open' then raise exception '열린 판이 아니에요'; end if;
  return _kuji_take(b.id, least(greatest(coalesce(p_count, 1), 1), 100), coalesce(nullif(_kuji_clean(p_who, 10), ''), '익명'));
end $$;

-- 판 설정 바꾸기 (테스트 ↔ 실제, 자동 ↔ 라이브, 정렬)
create or replace function kuji_update(p_key text, p_slug text, p_test boolean, p_mode text, p_sort int default null) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not _kuji_is_admin(p_key) then raise exception '관리자 비밀번호가 틀렸어요'; end if;
  update kuji_boards set test_mode = coalesce(p_test, test_mode), mode = coalesce(p_mode, mode), sort = coalesce(p_sort, sort) where slug = p_slug;
end $$;

-- 판 마감 (남은 표가 있어도 마감하고 순서 공개)
create or replace function kuji_close(p_key text, p_slug text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not _kuji_is_admin(p_key) then raise exception '관리자 비밀번호가 틀렸어요'; end if;
  update kuji_boards b set status = 'closed', closed_at = now(), salt = (select salt from kuji_board_secrets s where s.board_id = b.id)
  where slug = p_slug and status = 'open';
end $$;

-- 판 삭제 (테스트 판만)
create or replace function kuji_delete(p_key text, p_slug text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not _kuji_is_admin(p_key) then raise exception '관리자 비밀번호가 틀렸어요'; end if;
  if exists (select 1 from kuji_boards where slug = p_slug and not test_mode) then raise exception '실제 판은 삭제할 수 없어요. 마감만 가능'; end if;
  delete from kuji_boards where slug = p_slug;
end $$;

-- 관리자용: 코드 목록
create or replace function kuji_codes_list(p_key text, p_slug text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not _kuji_is_admin(p_key) then raise exception '관리자 비밀번호가 틀렸어요'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('code', k.code, 'qty', k.qty, 'used', k.used, 'memo', k.memo, 'at', k.created_at) order by k.created_at desc), '[]'::jsonb)
          from kuji_codes k join kuji_boards b on b.id = k.board_id where b.slug = p_slug);
end $$;

-- ---------- 카페24 주문 연동 ----------
-- (서버 전용) 결제 확인된 주문 1줄을 받아서 남은 횟수만큼 즉시 뽑기. 같은 주문이 여러 번 와도 한 번만 뽑힘
create or replace function kuji_order_draw(p_order text, p_product int, p_qty int, p_buyer text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  b kuji_boards%rowtype;
  o kuji_orders%rowtype;
  v_n int; v_left int; v_res jsonb; v_short int := 0;
begin
  select * into b from kuji_boards where cafe24_product_no = p_product for update;
  if b.id is null then return null; end if;                       -- 쿠지 상품이 아님
  insert into kuji_orders (order_id, board_id, qty, buyer) values (p_order, b.id, p_qty, _kuji_clean(p_buyer, 10))
  on conflict (order_id, board_id) do nothing;
  select * into o from kuji_orders where order_id = p_order and board_id = b.id for update;
  v_n := o.qty - o.drawn - o.short;
  if v_n > 0 and b.mode = 'auto' then
    v_left := 0;
    if b.status = 'open' then select count(*) into v_left from kuji_tickets where board_id = b.id and draw_id is null; end if;
    if v_left < v_n then v_short := v_n - v_left; v_n := v_left; end if;
    if v_n > 0 then
      v_res := _kuji_take(b.id, v_n, coalesce(nullif(o.buyer, ''), '손님'));
      update kuji_draws set order_id = p_order where batch = (v_res->>'batch')::uuid;
    end if;
    update kuji_orders set drawn = drawn + v_n, short = short + v_short where order_id = p_order and board_id = b.id;
  end if;
  return jsonb_build_object('slug', b.slug, 'title', b.title, 'mode', b.mode, 'qty', o.qty,
    'shortage', (select short from kuji_orders where order_id = p_order and board_id = b.id),
    'pending', b.mode = 'live',
    'results', (select coalesce(jsonb_agg(jsonb_build_object('no', d.no, 'grade', d.grade, 'name', d.name,
        'img', (select img from kuji_prizes p where p.board_id = b.id and p.idx = d.prize_idx)) order by d.no), '[]'::jsonb)
      from kuji_draws d where d.order_id = p_order and d.board_id = b.id));
end $$;

-- 주문 결과 다시 보기 (주문번호로)
create or replace function kuji_order_results(p_order text) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(jsonb_build_object('slug', b.slug, 'title', b.title, 'qty', o.qty, 'pending', b.mode = 'live',
    'results', (select coalesce(jsonb_agg(jsonb_build_object('no', d.no, 'grade', d.grade, 'name', d.name,
        'img', (select img from kuji_prizes p where p.board_id = b.id and p.idx = d.prize_idx)) order by d.no), '[]'::jsonb)
      from kuji_draws d where d.order_id = o.order_id and d.board_id = b.id))), '[]'::jsonb)
  from kuji_orders o join kuji_boards b on b.id = o.board_id where o.order_id = p_order
$$;

-- (서버 전용) 카페24 토큰 저장소 접근 — 주문 확인 함수(Edge Function)만 사용
create or replace function kuji_svc_token_get() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select to_jsonb(c) - 'id' from kuji_cafe24 c where id = 1
$$;
create or replace function kuji_svc_token_save(p_access text, p_refresh text, p_expires timestamptz, p_refresh_expires timestamptz) returns void
language sql security definer set search_path = public, extensions as $$
  insert into kuji_cafe24 (id, access_token, refresh_token, expires_at, refresh_expires_at, oauth_state, updated_at)
  values (1, p_access, p_refresh, p_expires, p_refresh_expires, null, now())
  on conflict (id) do update set access_token = excluded.access_token, refresh_token = excluded.refresh_token,
    expires_at = excluded.expires_at, refresh_expires_at = excluded.refresh_expires_at, oauth_state = null, updated_at = now()
$$;
create or replace function kuji_svc_state_set(p_state text) returns void
language sql security definer set search_path = public, extensions as $$
  insert into kuji_cafe24 (id, oauth_state) values (1, p_state) on conflict (id) do update set oauth_state = excluded.oauth_state
$$;
create or replace function kuji_svc_products() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(cafe24_product_no), '[]'::jsonb) from kuji_boards where cafe24_product_no is not null
$$;

-- 판 ↔ 카페24 상품번호 연결 (관리자)
create or replace function kuji_link_product(p_key text, p_slug text, p_product int) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not _kuji_is_admin(p_key) then raise exception '관리자 비밀번호가 틀렸어요'; end if;
  update kuji_boards set cafe24_product_no = null where cafe24_product_no = p_product and slug <> p_slug;
  update kuji_boards set cafe24_product_no = p_product where slug = p_slug;
end $$;

-- 주문 목록 (관리자) — 표 부족으로 못 뽑은 주문(short > 0)은 환불 대상
create or replace function kuji_orders_list(p_key text, p_slug text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not _kuji_is_admin(p_key) then raise exception '관리자 비밀번호가 틀렸어요'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('order_id', o.order_id, 'qty', o.qty, 'drawn', o.drawn, 'short', o.short, 'buyer', o.buyer, 'at', o.created_at,
            'hits', (select coalesce(jsonb_agg(d.grade || ' ' || d.name), '[]'::jsonb) from kuji_draws d where d.order_id = o.order_id and d.board_id = b.id and d.grade in ('S','A','B','LAST'))) order by o.created_at desc), '[]'::jsonb)
          from kuji_orders o join kuji_boards b on b.id = o.board_id where b.slug = p_slug);
end $$;

-- 카페24 연결 상태 (관리자)
create or replace function kuji_cafe24_status(p_key text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not _kuji_is_admin(p_key) then raise exception '관리자 비밀번호가 틀렸어요'; end if;
  return (select jsonb_build_object('connected', refresh_token is not null and refresh_expires_at > now(), 'refresh_expires_at', refresh_expires_at, 'updated_at', updated_at)
          from kuji_cafe24 where id = 1);
end $$;

-- ---------- 함수 실행 권한 ----------
revoke all on function _kuji_is_admin(text), _kuji_take(bigint, int, text), kuji_order_draw(text, int, int, text), kuji_svc_token_get(), kuji_svc_token_save(text, text, timestamptz, timestamptz), kuji_svc_state_set(text), kuji_svc_products() from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function _kuji_is_admin(text), _kuji_take(bigint, int, text), kuji_order_draw(text, int, int, text), kuji_svc_token_get(), kuji_svc_token_save(text, text, timestamptz, timestamptz), kuji_svc_state_set(text), kuji_svc_products() from anon, authenticated;
    grant execute on function kuji_list(), kuji_state(text), kuji_draw(text, int, text, text), kuji_code_info(text), kuji_reveal(text),
      kuji_admin_check(text), kuji_open(text, text, text, int, jsonb, text, boolean, int), kuji_issue_code(text, text, int, text),
      kuji_live_draw(text, text, int, text), kuji_update(text, text, boolean, text, int), kuji_close(text, text),
      kuji_delete(text, text), kuji_codes_list(text, text), kuji_order_results(text), kuji_link_product(text, text, int),
      kuji_cafe24_status(text), kuji_orders_list(text, text) to anon, authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function kuji_order_draw(text, int, int, text), kuji_svc_token_get(), kuji_svc_token_save(text, text, timestamptz, timestamptz), kuji_svc_state_set(text), kuji_svc_products() to service_role;
  end if;
end $$;

-- ---------- 실시간 (뽑기 결과가 광장에 바로 뜨게) ----------
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'kuji_draws') then
    alter publication supabase_realtime add table kuji_draws;
  end if;
end $$;

-- ---------- 관리자 비밀번호 설정 ----------
-- ⚠️ 아래 '여기에-비밀번호' 를 남들이 못 맞힐 긴 비밀번호로 바꾸고 실행하세요 (12자 이상 추천)
-- · 처음 설치할 때 안 바꾸면 에러가 나면서 설치가 멈춰요 (기본값으로 열리는 사고 방지)
-- · 이미 설치한 뒤 다시 실행할 땐 그대로 두면 기존 비밀번호 유지, 새로 적으면 그 비밀번호로 바뀜
do $$
declare v text := '여기에-비밀번호';
begin
  if md5(v) = '326feacbc0a6c323f67d341273a1d97f' then        -- 기본값 그대로인지 확인
    if not exists (select 1 from kuji_admin where id = 1) then
      raise exception '맨 아래 관리자 비밀번호를 바꾼 다음 다시 실행해주세요';
    end if;
  elsif char_length(v) < 8 then
    raise exception '관리자 비밀번호는 8자 이상으로 해주세요';
  else
    insert into kuji_admin (id, secret_hash) values (1, extensions.crypt(v, extensions.gen_salt('bf')))
    on conflict (id) do update set secret_hash = excluded.secret_hash;
  end if;
end $$;
