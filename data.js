/* ======================================================================
   럭키슬랩 운영 데이터 — 광장(index.html)과 상점 홈(shop/)이 같이 씀. 여기만 고치면 둘 다 바뀜
   · SHOP_URL  : 카페24 등 결제하는 쇼핑몰 주소 (비워두면 "오픈 준비 중")
   · KAKAO_URL : 오픈카톡 주소
   · LIVE      : 유튜브 라이브 링크, 방송 시간 문구
   · BOARDS    : 판 목록. 팔릴 때마다 sold / 상품별 남은 개수 수정
                 items 형식 = [상품명, 남은 개수, 전체 개수, (선택) 사진 주소]
                 url 을 넣으면 그 판의 구매 버튼이 그 주소로 감 (없으면 SHOP_URL)
   · HALL      : 당첨자. 새 당첨자는 맨 위에 추가
   · BIZ       : 사업자 정보 (상점 홈 맨 아래 표시 — 통신판매업 필수 표시사항)
   ====================================================================== */
window.LUCKY = {
  SUPABASE_URL: 'https://jxkicwyioopekmsajowh.supabase.co',   // 광장·쿠지 서버 (공개 키라 노출돼도 괜찮음)
  SUPABASE_ANON_KEY: 'sb_publishable_HkZjK14uHrUpVgybOEhdkA_liVHEb71',
  SHOP_URL: 'https://luckyslab.shop/',
  KAKAO_URL: '',
  LIVE: { youtube: '', schedule: '매일 저녁 8시 LIVE' },
  NOTICES: [
    '럭키슬랩 광장 오픈! 친구 불러와요',
    '라이브 무대 앞에 모여서 같이 개봉 보기',
    '판 현황판에서 남은 상품 바로 확인',
    '무료 가챠는 출석 코인으로 돌려요',
    '풀숲에 야생 몬스터가 나타나요. 잡아서 도감 채우기!',
    '방명록에 한마디 남기고 가요',
    '서로 존중하는 대화 부탁해요. 불편한 사람은 눌러서 차단',
  ],
  BOARDS: [
    // 카페24 상품 'PSA 10 레전드 쿠지 1회차'(product_no=57)와 같은 구성. 숫자 바꿀 땐 카페24 상세 설명도 같이 고칠 것
    { title: 'PSA 10 레전드 쿠지 1회차', price: 20000, total: 250, sold: 0, status: '오픈 예정',
      url: 'https://luckyslab.shop/product/detail.html?product_no=57',
      lastOne: '리자몽 VMAX SSR (샤이니스타 V) PSA10',
      tiers: [
        { g: 'S', items: [['피카츄 ex UR (SV8) PSA10', 1, 1, 'cards/pikachu_ex_ur.jpg'], ['토호쿠의 피카츄 PSA10', 1, 1, 'cards/tohoku_pikachu.jpg'], ['히로시마의 피카츄 PSA10', 1, 1, 'cards/hiroshima_pikachu.jpg']] },
        { g: 'A', items: [['뮤 VMAX UR (VMAX 클라이맥스) PSA10', 1, 1], ['라이츄 포켓큥 1st PSA10', 1, 1, 'cards/raichu_pokekyun.jpg'], ['님피아 ex SAR (SV8a) PSA10', 1, 1, 'cards/nymphia_sar.jpg']] },
        { g: 'B', items: [['메가리자몽X ex MA (M2a) PSA10', 1, 1, 'cards/mega_charizard_x.jpg'], ['골드의 블레이범 AR (SV9a) PSA10', 1, 1, 'cards/typhlosion_ar.jpg'], ['데덴네 AR (M3) PSA10', 1, 1]] },
        { g: 'C', items: [['인페르노X 박스 (한글판 미개봉 30팩)', 11, 11]] },
        { g: 'D', items: [['인페르노X 확장팩 (한글판 1팩)', 230, 230]] },
      ] },
  ],
  HALL: [
    // { name: '닉네임', card: '리자몽 VMAX PSA10', grade: 'S', date: '11/12' },
  ],
  BIZ: { name: '럭키슬랩', ceo: '박경민', bizno: '695-27-02176', mailorder: '', addr: '경기도 안산시 단원구 예술대학로1길 7 (고잔동)', tel: '010-2908-4969', email: '1029z@naver.com' },
};
