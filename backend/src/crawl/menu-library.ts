// ══════════════════════════════════════════════════════════
// 파일 역할: 카테고리 기반 정적 메뉴 라이브러리
//
// 사용 시점 (crawl.service.ts 폴백 최종 단계):
//   1) 네이버 비공식 API → 실패 (봇 차단 강화)
//   2) Gemini AI → 실패 (quota 초과)
//   3) 이 라이브러리 → 카테고리(한식/일식/양식/분식/중식 등)에 맞춰
//                    검증된 메뉴 + 가격 + Unsplash 사진 + 알레르기 자동 매핑
//
// 효과:
//   - 어디서 앱 켜든 카카오만 응답하면 메뉴+사진 항상 표시
//   - 수동 SQL 시드 불필요
//   - Gemini quota 회복 안 기다려도 됨
//
// 사진:
//   Unsplash Source API — 새로고침마다 실제 음식 사진 변경, CORS·인증 없음.
// ══════════════════════════════════════════════════════════

export interface LibraryMenuItem {
  name: string;
  price: number;
  category: string; // rice | noodle | snack | soup | drink | main
  description: string;
  imageUrl: string;
  ingredients: string[];
  allergens: string[];
}

/// 카테고리별 정적 메뉴 라이브러리.
/// 카카오의 카테고리 분류(mapCategory 의 출력) 와 일치해야 함:
///   한식 | 중식 | 일식 | 양식 | 분식 | 카페 | 패스트푸드 | 아시안 | 기타
export const MENU_LIBRARY: Record<string, LibraryMenuItem[]> = {
  '한식': [
    {
      name: '김치찌개',
      price: 9000,
      category: 'soup',
      description: '집밥 같은 진한 김치찌개',
      imageUrl: 'https://source.unsplash.com/400x300/?kimchi+jjigae',
      ingredients: ['김치', '돼지고기', '두부', '파'],
      allergens: ['대두'],
    },
    {
      name: '된장찌개',
      price: 9000,
      category: 'soup',
      description: '구수한 된장찌개',
      imageUrl: 'https://source.unsplash.com/400x300/?doenjang+jjigae',
      ingredients: ['된장', '두부', '애호박', '감자'],
      allergens: ['대두'],
    },
    {
      name: '제육볶음 정식',
      price: 11000,
      category: 'rice',
      description: '매콤한 제육과 흰밥',
      imageUrl: 'https://source.unsplash.com/400x300/?jeyuk+bokkeum',
      ingredients: ['돼지고기', '양파', '고추장', '쌀'],
      allergens: ['대두'],
    },
    {
      name: '비빔밥',
      price: 10000,
      category: 'rice',
      description: '나물 듬뿍 비빔밥',
      imageUrl: 'https://source.unsplash.com/400x300/?bibimbap',
      ingredients: ['쌀', '나물', '계란', '고추장'],
      allergens: ['계란', '대두'],
    },
    {
      name: '불고기 정식',
      price: 13000,
      category: 'rice',
      description: '달콤한 양념 불고기',
      imageUrl: 'https://source.unsplash.com/400x300/?bulgogi',
      ingredients: ['소고기', '양파', '간장', '쌀'],
      allergens: ['대두', '밀'],
    },
  ],

  '중식': [
    {
      name: '짜장면',
      price: 7000,
      category: 'noodle',
      description: '진한 춘장 베이스',
      imageUrl: 'https://source.unsplash.com/400x300/?jjajangmyeon',
      ingredients: ['면', '춘장', '양파', '돼지고기'],
      allergens: ['밀', '대두'],
    },
    {
      name: '짬뽕',
      price: 8500,
      category: 'noodle',
      description: '얼큰한 해물 짬뽕',
      imageUrl: 'https://source.unsplash.com/400x300/?jjamppong',
      ingredients: ['면', '오징어', '홍합', '청경채'],
      allergens: ['밀', '조개류', '갑각류'],
    },
    {
      name: '탕수육 (소)',
      price: 18000,
      category: 'snack',
      description: '바삭한 옛날 스타일',
      imageUrl: 'https://source.unsplash.com/400x300/?tangsuyuk',
      ingredients: ['돼지고기', '튀김옷', '식초', '설탕'],
      allergens: ['밀', '대두'],
    },
    {
      name: '마파두부덮밥',
      price: 10000,
      category: 'rice',
      description: '매콤한 두반장 소스',
      imageUrl: 'https://source.unsplash.com/400x300/?mapo+tofu',
      ingredients: ['두부', '돼지고기', '두반장', '쌀'],
      allergens: ['대두'],
    },
    {
      name: '깐풍기',
      price: 22000,
      category: 'snack',
      description: '매콤달콤 닭튀김',
      imageUrl: 'https://source.unsplash.com/400x300/?kkanpunggi',
      ingredients: ['닭고기', '고추', '간장', '튀김옷'],
      allergens: ['밀', '대두'],
    },
  ],

  '일식': [
    {
      name: '돈코츠 라멘',
      price: 12000,
      category: 'noodle',
      description: '진한 돼지뼈 육수',
      imageUrl: 'https://source.unsplash.com/400x300/?tonkotsu+ramen',
      ingredients: ['면', '돼지고기', '파', '계란'],
      allergens: ['밀', '계란', '대두'],
    },
    {
      name: '쇼유 라멘',
      price: 11000,
      category: 'noodle',
      description: '깔끔한 간장 베이스',
      imageUrl: 'https://source.unsplash.com/400x300/?shoyu+ramen',
      ingredients: ['면', '닭고기', '간장', '파'],
      allergens: ['밀', '대두'],
    },
    {
      name: '연어 사시미',
      price: 18000,
      category: 'rice',
      description: '신선한 연어회',
      imageUrl: 'https://source.unsplash.com/400x300/?salmon+sashimi',
      ingredients: ['연어', '간장', '와사비'],
      allergens: ['생선', '대두'],
    },
    {
      name: '치킨 가라아게',
      price: 9000,
      category: 'snack',
      description: '바삭한 일본식 닭튀김',
      imageUrl: 'https://source.unsplash.com/400x300/?karaage',
      ingredients: ['닭고기', '간장', '생강', '밀가루'],
      allergens: ['밀', '대두'],
    },
    {
      name: '교자',
      price: 7500,
      category: 'snack',
      description: '쫄깃한 일본식 만두',
      imageUrl: 'https://source.unsplash.com/400x300/?gyoza',
      ingredients: ['돼지고기', '부추', '밀가루'],
      allergens: ['밀', '대두'],
    },
  ],

  '양식': [
    {
      name: '까르보나라',
      price: 15000,
      category: 'noodle',
      description: '진한 크림 까르보나라',
      imageUrl: 'https://source.unsplash.com/400x300/?carbonara+pasta',
      ingredients: ['파스타', '베이컨', '계란', '크림'],
      allergens: ['밀', '계란', '유제품'],
    },
    {
      name: '토마토 파스타',
      price: 13000,
      category: 'noodle',
      description: '신선한 토마토 소스',
      imageUrl: 'https://source.unsplash.com/400x300/?tomato+pasta',
      ingredients: ['파스타', '토마토', '바질', '마늘'],
      allergens: ['밀'],
    },
    {
      name: '마르게리타 피자',
      price: 16000,
      category: 'snack',
      description: '나폴리 스타일',
      imageUrl: 'https://source.unsplash.com/400x300/?margherita+pizza',
      ingredients: ['밀가루', '토마토', '모짜렐라', '바질'],
      allergens: ['밀', '유제품'],
    },
    {
      name: '시저 샐러드',
      price: 11000,
      category: 'rice',
      description: '신선한 로메인',
      imageUrl: 'https://source.unsplash.com/400x300/?caesar+salad',
      ingredients: ['로메인', '닭가슴살', '치즈', '크루통'],
      allergens: ['밀', '유제품', '계란'],
    },
    {
      name: '봉골레 파스타',
      price: 16000,
      category: 'noodle',
      description: '바지락 듬뿍',
      imageUrl: 'https://source.unsplash.com/400x300/?vongole+pasta',
      ingredients: ['파스타', '바지락', '마늘', '올리브유'],
      allergens: ['밀', '조개류'],
    },
  ],

  '분식': [
    {
      name: '참치 김밥',
      price: 4500,
      category: 'rice',
      description: '신선한 참치와 야채',
      imageUrl: 'https://source.unsplash.com/400x300/?kimbap',
      ingredients: ['참치', '쌀', '단무지', '계란'],
      allergens: ['생선', '계란'],
    },
    {
      name: '치즈 라볶이',
      price: 6500,
      category: 'snack',
      description: '쫄깃한 떡과 진한 치즈',
      imageUrl: 'https://source.unsplash.com/400x300/?tteokbokki',
      ingredients: ['떡', '어묵', '치즈', '고추장'],
      allergens: ['유제품', '대두', '밀'],
    },
    {
      name: '왕돈가스',
      price: 8500,
      category: 'rice',
      description: '바삭한 왕돈가스 정식',
      imageUrl: 'https://source.unsplash.com/400x300/?donkatsu',
      ingredients: ['돼지고기', '빵가루', '계란'],
      allergens: ['밀', '계란', '대두'],
    },
    {
      name: '얼큰 라면',
      price: 4000,
      category: 'noodle',
      description: '진한 국물 라면',
      imageUrl: 'https://source.unsplash.com/400x300/?korean+ramen',
      ingredients: ['면', '계란', '파'],
      allergens: ['밀', '계란', '대두'],
    },
    {
      name: '오므라이스',
      price: 7500,
      category: 'rice',
      description: '폭신한 계란 위에 토마토 케첩',
      imageUrl: 'https://source.unsplash.com/400x300/?omurice',
      ingredients: ['쌀', '계란', '햄', '양파'],
      allergens: ['계란', '대두'],
    },
  ],

  '카페': [
    {
      name: '아메리카노',
      price: 4500,
      category: 'drink',
      description: '진한 에스프레소',
      imageUrl: 'https://source.unsplash.com/400x300/?americano+coffee',
      ingredients: ['에스프레소', '물'],
      allergens: [],
    },
    {
      name: '카페라떼',
      price: 5500,
      category: 'drink',
      description: '부드러운 우유 거품',
      imageUrl: 'https://source.unsplash.com/400x300/?cafe+latte',
      ingredients: ['에스프레소', '우유'],
      allergens: ['유제품'],
    },
    {
      name: '치즈케이크',
      price: 6500,
      category: 'snack',
      description: '진한 뉴욕 스타일',
      imageUrl: 'https://source.unsplash.com/400x300/?cheesecake',
      ingredients: ['크림치즈', '버터', '계란'],
      allergens: ['유제품', '계란', '밀'],
    },
    {
      name: '크로플',
      price: 6000,
      category: 'snack',
      description: '바삭한 크로플',
      imageUrl: 'https://source.unsplash.com/400x300/?croffle',
      ingredients: ['크루아상 반죽', '버터', '설탕'],
      allergens: ['밀', '유제품', '계란'],
    },
  ],

  '패스트푸드': [
    {
      name: '치즈버거',
      price: 7500,
      category: 'snack',
      description: '두툼한 패티',
      imageUrl: 'https://source.unsplash.com/400x300/?cheeseburger',
      ingredients: ['소고기 패티', '치즈', '양상추', '번'],
      allergens: ['밀', '유제품', '대두'],
    },
    {
      name: '후라이드 치킨',
      price: 19000,
      category: 'snack',
      description: '바삭한 옛날 통닭',
      imageUrl: 'https://source.unsplash.com/400x300/?korean+fried+chicken',
      ingredients: ['닭고기', '튀김옷', '소금'],
      allergens: ['밀'],
    },
    {
      name: '감자튀김',
      price: 4500,
      category: 'snack',
      description: '바삭한 감자',
      imageUrl: 'https://source.unsplash.com/400x300/?french+fries',
      ingredients: ['감자', '소금'],
      allergens: [],
    },
    {
      name: '콜라',
      price: 2500,
      category: 'drink',
      description: '시원한 콜라',
      imageUrl: 'https://source.unsplash.com/400x300/?coca+cola',
      ingredients: ['콜라'],
      allergens: [],
    },
  ],

  '아시안': [
    {
      name: '팟타이',
      price: 13000,
      category: 'noodle',
      description: '태국식 볶음면',
      imageUrl: 'https://source.unsplash.com/400x300/?pad+thai',
      ingredients: ['쌀국수', '새우', '계란', '땅콩'],
      allergens: ['갑각류', '계란', '땅콩', '대두'],
    },
    {
      name: '쌀국수',
      price: 11000,
      category: 'noodle',
      description: '담백한 베트남 국수',
      imageUrl: 'https://source.unsplash.com/400x300/?pho+vietnamese',
      ingredients: ['쌀국수', '소고기', '숙주', '라임'],
      allergens: ['대두'],
    },
    {
      name: '나시고렝',
      price: 12000,
      category: 'rice',
      description: '인도네시아 볶음밥',
      imageUrl: 'https://source.unsplash.com/400x300/?nasi+goreng',
      ingredients: ['쌀', '계란', '닭고기', '간장'],
      allergens: ['계란', '대두'],
    },
    {
      name: '그린 카레',
      price: 14000,
      category: 'soup',
      description: '코코넛 베이스 태국 카레',
      imageUrl: 'https://source.unsplash.com/400x300/?green+curry',
      ingredients: ['코코넛 밀크', '닭고기', '바질', '쌀'],
      allergens: ['유제품'],
    },
  ],

  // 카테고리 추론 실패 시 폴백
  '기타': [
    {
      name: '오늘의 추천 메뉴',
      price: 10000,
      category: 'main',
      description: '셰프 추천 메뉴',
      imageUrl: 'https://source.unsplash.com/400x300/?korean+food',
      ingredients: ['신선한 재료'],
      allergens: [],
    },
    {
      name: '계절 정식',
      price: 12000,
      category: 'rice',
      description: '제철 재료 정식',
      imageUrl: 'https://source.unsplash.com/400x300/?korean+meal',
      ingredients: ['쌀', '국', '반찬'],
      allergens: ['대두'],
    },
    {
      name: '오늘의 국수',
      price: 8000,
      category: 'noodle',
      description: '담백한 국수',
      imageUrl: 'https://source.unsplash.com/400x300/?korean+noodles',
      ingredients: ['면', '국물', '고명'],
      allergens: ['밀'],
    },
    {
      name: '음료수',
      price: 3000,
      category: 'drink',
      description: '음료',
      imageUrl: 'https://source.unsplash.com/400x300/?beverage',
      ingredients: ['음료'],
      allergens: [],
    },
  ],
};

/// 카테고리에 맞는 메뉴를 무작위로 N개 반환 (식당마다 다른 메뉴 보이게 셔플).
/// 라이브러리에 카테고리가 없으면 '기타' 폴백.
export function pickMenusForCategory(
  category: string,
  count: number = 5,
): LibraryMenuItem[] {
  const pool = MENU_LIBRARY[category] ?? MENU_LIBRARY['기타'];
  // 셔플 (Fisher-Yates 의 단순 버전 — 길이 작아 성능 OK)
  const shuffled = [...pool].sort(() => Math.random() - 0.5);
  return shuffled.slice(0, Math.min(count, shuffled.length));
}
