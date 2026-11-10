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
    { title: 'PSA10 피카츄·리자몽 10종', price: 2500, total: 1334, sold: 0, status: '오픈 예정', url: '',
      lastOne: null,
      tiers: [
        { g: 'S', items: [['리자몽 VMAX SSR (s4a) PSA10', 1, 1, 'cards/charizard_vmax.jpg'], ['피카츄 ex UR (sv8) PSA10', 1, 1, 'cards/pikachu_ex_ur.jpg']] },
        { g: 'A', items: [['히로시마의 피카츄 PSA10', 1, 1, 'cards/hiroshima_pikachu.jpg'], ['라이츄 포켓큥 1st PSA10', 1, 1, 'cards/raichu_pokekyun.jpg'], ['토호쿠의 피카츄 PSA10', 1, 1, 'cards/tohoku_pikachu.jpg'], ['님피아 ex SAR PSA10', 1, 1, 'cards/nymphia_sar.jpg']] },
        { g: 'B', items: [['팬텀 VMAX (SCG) PSA10', 1, 1, 'cards/gengar_vmax.jpg'], ['피카츄&제크로무 GX PSA10', 1, 1, 'cards/pika_zekrom_gx.jpg'], ['메가리자몽X ex MA PSA10', 1, 1, 'cards/mega_charizard_x.jpg'], ['심향의 블레이범 AR PSA10', 1, 1, 'cards/typhlosion_ar.jpg']] },
        { g: 'C', items: [['골드·실버·브론즈 포인트', 1324, 1324]] },
      ] },
  ],
  HALL: [
    // { name: '닉네임', card: '리자몽 VMAX PSA10', grade: 'S', date: '11/12' },
  ],
  BIZ: { name: '럭키슬랩', ceo: '박경민', bizno: '695-27-02176', mailorder: '', addr: '', tel: '', email: '' },
};
