// ══════════════════════════════════════════════════════════
// 파일 역할: 메뉴 시드 데이터 (개발·테스트용)
//
// 연관 파일:
//   - lib/models/menu_item.dart
//   - lib/data/seeds/restaurant_seeds.dart
// ══════════════════════════════════════════════════════════

/// 메뉴 시드 데이터 항목
class MenuSeed {
  const MenuSeed({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    this.isSoldOut = false,
  });

  final String id;
  final String restaurantId;
  final String name;
  final String description;
  final int price;
  final String category; // 밥류, 면류, 분식, 음료 등
  final bool isSoldOut;
}

/// 메뉴 시드 데이터 목록
const List<MenuSeed> menuSeeds = [
  // ── rest_001: 한솥도시락 ──────────────────────────────
  MenuSeed(
    id: 'menu_001_01',
    restaurantId: 'rest_001',
    name: '치킨마요도시락',
    description: '바삭한 치킨에 고소한 마요네즈를 얹은 인기 도시락',
    price: 5500,
    category: '밥류',
  ),
  MenuSeed(
    id: 'menu_001_02',
    restaurantId: 'rest_001',
    name: '제육도시락',
    description: '매콤달콤 제육볶음이 듬뿍 들어간 도시락',
    price: 6000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'menu_001_03',
    restaurantId: 'rest_001',
    name: '참치김치도시락',
    description: '고소한 참치와 볶음김치의 조합',
    price: 5000,
    category: '밥류',
  ),

  // ── rest_002: 김밥천국 ────────────────────────────────
  MenuSeed(
    id: 'menu_002_01',
    restaurantId: 'rest_002',
    name: '참치김밥',
    description: '고소한 참치마요가 가득한 김밥',
    price: 4000,
    category: '분식',
  ),
  MenuSeed(
    id: 'menu_002_02',
    restaurantId: 'rest_002',
    name: '떡볶이',
    description: '매콤한 고추장 소스의 국민 분식',
    price: 4500,
    category: '분식',
  ),
  MenuSeed(
    id: 'menu_002_03',
    restaurantId: 'rest_002',
    name: '라볶이',
    description: '떡볶이에 라면 사리를 추가한 조합',
    price: 5500,
    category: '면류',
  ),

  // ── rest_003: 스시로 ──────────────────────────────────
  MenuSeed(
    id: 'menu_003_01',
    restaurantId: 'rest_003',
    name: '연어초밥세트',
    description: '신선한 연어 8피스 초밥 세트',
    price: 15000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'menu_003_02',
    restaurantId: 'rest_003',
    name: '참치회덮밥',
    description: '참치회를 듬뿍 올린 덮밥',
    price: 13000,
    category: '밥류',
  ),

  // ── rest_004: 맘스터치 ────────────────────────────────
  MenuSeed(
    id: 'menu_004_01',
    restaurantId: 'rest_004',
    name: '싸이버거',
    description: '두툼한 닭다리살 패티의 시그니처 버거',
    price: 5200,
    category: '양식',
  ),
  MenuSeed(
    id: 'menu_004_02',
    restaurantId: 'rest_004',
    name: '불싸이버거',
    description: '매콤한 소스를 더한 싸이버거',
    price: 5700,
    category: '양식',
  ),
  MenuSeed(
    id: 'menu_004_03',
    restaurantId: 'rest_004',
    name: '케이준 감자',
    description: '바삭한 감자에 케이준 시즈닝을 뿌린 사이드',
    price: 2500,
    category: '양식',
  ),

  // ── rest_005: 순남시래기 ──────────────────────────────
  MenuSeed(
    id: 'menu_005_01',
    restaurantId: 'rest_005',
    name: '시래기된장찌개',
    description: '구수한 된장에 시래기를 넣어 끓인 찌개',
    price: 9000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'menu_005_02',
    restaurantId: 'rest_005',
    name: '시래기불고기',
    description: '달콤한 불고기와 시래기의 건강한 조합',
    price: 10000,
    category: '밥류',
  ),

  // ── rest_006: 홍콩반점 ────────────────────────────────
  MenuSeed(
    id: 'menu_006_01',
    restaurantId: 'rest_006',
    name: '짬뽕',
    description: '얼큰한 해물 국물의 대표 짬뽕',
    price: 7000,
    category: '면류',
  ),
  MenuSeed(
    id: 'menu_006_02',
    restaurantId: 'rest_006',
    name: '짜장면',
    description: '달달한 춘장 소스의 클래식 짜장면',
    price: 6000,
    category: '면류',
  ),
  MenuSeed(
    id: 'menu_006_03',
    restaurantId: 'rest_006',
    name: '탕수육(소)',
    description: '바삭한 튀김옷에 새콤달콤 소스를 곁들인 탕수육',
    price: 13000,
    category: '밥류',
  ),

  // ── rest_007: 서브웨이 ────────────────────────────────
  MenuSeed(
    id: 'menu_007_01',
    restaurantId: 'rest_007',
    name: '이탈리안 BMT',
    description: '페퍼로니, 살라미, 햄이 들어간 클래식 서브',
    price: 7400,
    category: '양식',
  ),
  MenuSeed(
    id: 'menu_007_02',
    restaurantId: 'rest_007',
    name: '에그마요',
    description: '고소한 에그마요네즈 샌드위치',
    price: 6500,
    category: '양식',
  ),

  // ── rest_008: 이디야커피 ──────────────────────────────
  MenuSeed(
    id: 'menu_008_01',
    restaurantId: 'rest_008',
    name: '아메리카노',
    description: '깔끔한 에스프레소 기반 커피',
    price: 3300,
    category: '음료',
  ),
  MenuSeed(
    id: 'menu_008_02',
    restaurantId: 'rest_008',
    name: '카페라떼',
    description: '부드러운 우유와 에스프레소의 조화',
    price: 4000,
    category: '음료',
  ),
  MenuSeed(
    id: 'menu_008_03',
    restaurantId: 'rest_008',
    name: '크로플',
    description: '바삭한 크루아상 와플에 아이스크림을 곁들인 디저트',
    price: 4500,
    category: '디저트',
  ),

  // ── rest_009: 봉추찜닭 ────────────────────────────────
  MenuSeed(
    id: 'menu_009_01',
    restaurantId: 'rest_009',
    name: '오리지널찜닭',
    description: '간장 베이스 매콤달콤 찜닭 (2~3인분)',
    price: 22000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'menu_009_02',
    restaurantId: 'rest_009',
    name: '치즈찜닭',
    description: '모짜렐라 치즈를 듬뿍 올린 찜닭',
    price: 24000,
    category: '밥류',
  ),

  // ── rest_010: 역전우동 ────────────────────────────────
  MenuSeed(
    id: 'menu_010_01',
    restaurantId: 'rest_010',
    name: '가케우동',
    description: '진한 가쓰오부시 육수의 따뜻한 우동',
    price: 6500,
    category: '면류',
  ),
  MenuSeed(
    id: 'menu_010_02',
    restaurantId: 'rest_010',
    name: '냉우동',
    description: '시원한 냉육수에 쫄깃한 면발',
    price: 7000,
    category: '면류',
  ),

  // ── rest_011: 백소정 ──────────────────────────────────
  MenuSeed(
    id: 'menu_011_01',
    restaurantId: 'rest_011',
    name: '돈코츠라멘',
    description: '18시간 우려낸 진한 돼지뼈 육수 라멘',
    price: 10000,
    category: '면류',
  ),
  MenuSeed(
    id: 'menu_011_02',
    restaurantId: 'rest_011',
    name: '매운라멘',
    description: '돈코츠 베이스에 매운 소스를 추가한 라멘',
    price: 11000,
    category: '면류',
  ),
  MenuSeed(
    id: 'menu_011_03',
    restaurantId: 'rest_011',
    name: '차슈덮밥',
    description: '부드러운 차슈를 올린 일본식 덮밥',
    price: 9500,
    category: '밥류',
  ),

  // ── rest_012: 본죽 ────────────────────────────────────
  MenuSeed(
    id: 'menu_012_01',
    restaurantId: 'rest_012',
    name: '전복죽',
    description: '통전복이 들어간 영양 가득 죽',
    price: 10000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'menu_012_02',
    restaurantId: 'rest_012',
    name: '소고기야채죽',
    description: '소고기와 야채를 넣어 끓인 담백한 죽',
    price: 8000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'menu_012_03',
    restaurantId: 'rest_012',
    name: '참치야채죽',
    description: '고소한 참치와 야채의 부드러운 조합',
    price: 7500,
    category: '밥류',
  ),
];
