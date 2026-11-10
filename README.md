# 🍀 럭키슬랩 광장

캐릭터로 돌아다니면서 오리파 라이브를 같이 보고, 판 현황 확인하고, 당첨 자랑하는 커뮤니티 광장.
결제는 광장에서 안 함 — **상점 입구**를 통해 외부 쇼핑몰로 나감.

## 광장 구성
| 장소 | 기능 |
|---|---|
| 🎥 라이브 무대 | 유튜브 라이브를 광장 대형 스크린에 띄움 (크게 보기·소리 켜기) |
| 📋 판 현황판 | 진행 중인 판, 남은 수량, 등급별 상품 |
| 🏆 명예의 전당 | 당첨자 목록 |
| 🎰 무료 가챠 | 출석 코인으로 돌리는 꾸미기 아이템 가챠 (현금 가치 없음) |
| 🔄 교환소 | 교환 안내 + 오픈카톡 링크 |
| 🛒 상점 입구 | 외부 쇼핑몰로 이동 |
| 📖 방명록 | 한마디 남기기 (Supabase 테이블에 저장) |
| 💎 상품 진열장 | 판에 걸린 상품 실물 사진 진열 |
| ✨ 야생 몬스터 | 풀숲에 나타나는 오리지널 몬스터 9종 잡기 → 도감 → 데리고 다니기 |
| 🍀 오늘의 운세 | 동상에서 하루 한 번 바뀌는 럭키 넘버·럭키 몬스터 (재미용) |

## 상점 홈 (`shop/`)
판 목록·남은 수량·최근 당첨·이용 방법을 보여주는 랜딩 페이지. 구매 버튼은 `SHOP_URL`(카페24 등)로 나감. 결제 기능은 없음.

## 운영 방법
`data.js` 하나만 고치면 광장과 상점 홈이 같이 바뀜. (`ADMIN_KEY`만 `index.html`에 있음)
- `BIZ` 사업자 정보 — 상점 홈 맨 아래 표시
- `SHOP_URL` 상점 주소, `KAKAO_URL` 오픈카톡 주소
- `LIVE.youtube` 방송 링크, `LIVE.schedule` 방송 시간 문구
- `BOARDS` 판 목록 — 팔릴 때마다 `sold`, 상품별 남은 개수 수정
- `HALL` 명예의 전당 — 새 당첨자 맨 위에 추가
- `ADMIN_KEY` — `?admin=키` 로 들어오면 📣 당첨 알림 버튼 생김 (전원에게 폭죽+배너)

## 방명록 서버 저장 켜기 (한 번만)
Supabase 대시보드 → SQL Editor에 아래를 붙여넣고 Run. 안 하면 방명록이 접속 중인 사람한테만 보이고 각자 기기에만 저장됨.
```sql
create table guestbook (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) between 1 and 10),
  text text not null check (char_length(text) between 1 and 80),
  created_at timestamptz default now()
);
alter table guestbook enable row level security;
create policy "guestbook read" on guestbook for select using (true);
create policy "guestbook write" on guestbook for insert with check (true);
```
이상한 글은 대시보드 Table Editor에서 행 삭제.

## 진열장 사진 넣기
저장소에 `cards/` 폴더 만들어 사진 올리고 `BOARDS` 상품 4번째 칸에 주소 추가: `['리자몽 VMAX SSR (s4a) PSA10', 1, 1, 'cards/charizard.jpg']` (인증번호·바코드 가린 사진으로)

## 주소 옵션
- `?demo` 서버 없이 봇이랑 미리보기
- `?admin=키` 운영자 당첨 알림

## 기술
단일 `index.html` · 캔버스 아이소메트릭 · Supabase Realtime(presence/broadcast, 무료 한도 맞춰 전송량 제한) · GitHub Pages · PWA

## 쿠지 서버 (supabase/kuji.sql)
1. Supabase SQL Editor에 `supabase/kuji.sql` 전체를 붙여넣고, 맨 아래 `'여기에-비밀번호'`를 긴 비밀번호로 바꾼 뒤 Run
2. `kuji/admin.html` 에서 그 비밀번호로 로그인 → 판 열기 / 뽑기 코드 발급 / 라이브 뽑기 / 마감
3. SQL이 설치돼 있으면 쿠지 화면·광장이 자동으로 서버 모드로 바뀜 (없으면 데모 모드)

- 표는 판을 열 때 서버가 섞어서 고정, 지문(SHA-256) 공개 → 마감 후 salt 공개로 검증
- 테스트 판: 누구나 무료로 뽑기 / 실제 판: 뽑기 코드 필요 (나중에 카페24 결제와 자동 연동 예정)
- 당첨은 서버 기록(kuji_draws) 실시간 구독으로 광장 전체에 폭죽

## 카페24 결제 → 바로 뽑기 (A 방식)
흐름: 쿠지 판 "결제하고 바로 뽑기" → 카페24 상품 결제 → 주문완료 페이지가 자동으로 `kuji/?order=주문번호` 로 이동 → 서버가 카페24에 결제 확인 → 즉시 카드 공개
1. `supabase/kuji.sql` 다시 실행 (비밀번호 줄은 그대로 두면 기존 비밀번호 유지)
2. Supabase → Edge Functions → 새 함수 `kuji-order` 에 `supabase/functions/kuji-order/index.ts` 붙여넣고 배포, **Verify JWT 끄기**
3. Edge Functions → Secrets: `CAFE24_MALL_ID`, `CAFE24_CLIENT_ID`, `CAFE24_CLIENT_SECRET`
4. 카페24 개발자센터 앱: Redirect URI = `https://jxkicwyioopekmsajowh.supabase.co/functions/v1/kuji-order/callback`, 권한 = 주문(Order) 읽기
5. 관리자 페이지 → "카페24 연결하기" → 카페24 로그인·승인
6. 관리자 페이지 → 판마다 "카페24 상품 연결" (상품번호). 카페24 상품 재고 = 판 구수로 맞추기
7. 카페24 주문완료 페이지 맨 아래에 `supabase/cafe24-order-complete.html` 붙여넣기
