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

## 운영 방법
`index.html` 맨 위 `CONFIG`만 고치면 됨.
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
