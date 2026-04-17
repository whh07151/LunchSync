// ══════════════════════════════════════════════════════════
// 파일 역할: 메뉴 시드 데이터 (개발·테스트용)
//
// 연관 파일:
//   - lib/models/menu_item.dart
//   - lib/data/seeds/restaurant_seeds.dart
//
// UUID 규칙:
//   식당: bbbbbbbb-0000-4000-8000-000000000NNN
//   메뉴: cccccccc-0NNN-4000-8000-0000000000MM
//   (backend/scripts/seed-restaurants.ts 와 동일)
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
  // ── 한솥도시락 ────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0001-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000001',
    name: '치킨마요도시락',
    description: '바삭한 치킨에 고소한 마요네즈를 얹은 인기 도시락',
    price: 5500,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0001-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000001',
    name: '제육도시락',
    description: '매콤달콤 제육볶음이 듬뿍 들어간 도시락',
    price: 6000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0001-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000001',
    name: '참치김치도시락',
    description: '고소한 참치와 볶음김치의 조합',
    price: 5000,
    category: '밥류',
  ),

  // ── 김밥천국 ──────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0002-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000002',
    name: '참치김밥',
    description: '고소한 참치마요가 가득한 김밥',
    price: 4000,
    category: '분식',
  ),
  MenuSeed(
    id: 'cccccccc-0002-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000002',
    name: '떡볶이',
    description: '매콤한 고추장 소스의 국민 분식',
    price: 4500,
    category: '분식',
  ),
  MenuSeed(
    id: 'cccccccc-0002-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000002',
    name: '라볶이',
    description: '떡볶이에 라면 사리를 추가한 조합',
    price: 5500,
    category: '면류',
  ),

  // ── 스시로 ────────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0003-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000003',
    name: '연어초밥세트',
    description: '신선한 연어 8피스 초밥 세트',
    price: 15000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0003-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000003',
    name: '참치회덮밥',
    description: '참치회를 듬뿍 올린 덮밥',
    price: 13000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0003-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000003',
    name: '새우튀김우동',
    description: '바삭한 새우튀김과 진한 다시 육수 우동',
    price: 12000,
    category: '면류',
  ),

  // ── 맘스터치 ──────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0004-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000004',
    name: '싸이버거',
    description: '두툼한 닭다리살 패티의 시그니처 버거',
    price: 5200,
    category: '양식',
  ),
  MenuSeed(
    id: 'cccccccc-0004-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000004',
    name: '불싸이버거',
    description: '매콤한 소스를 더한 싸이버거',
    price: 5700,
    category: '양식',
  ),
  MenuSeed(
    id: 'cccccccc-0004-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000004',
    name: '케이준 감자',
    description: '바삭한 감자에 케이준 시즈닝을 뿌린 사이드',
    price: 2500,
    category: '양식',
  ),

  // ── 순남시래기 ────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0005-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000005',
    name: '시래기된장찌개',
    description: '구수한 된장에 시래기를 넣어 끓인 찌개',
    price: 9000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0005-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000005',
    name: '시래기불고기',
    description: '달콤한 불고기와 시래기의 건강한 조합',
    price: 10000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0005-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000005',
    name: '청국장찌개',
    description: '구수한 향이 진한 전통 청국장에 두부와 야채를 듬뿍',
    price: 9000,
    category: '밥류',
  ),

  // ── 홍콩반점 ──────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0006-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000006',
    name: '짬뽕',
    description: '얼큰한 해물 국물의 대표 짬뽕',
    price: 7000,
    category: '면류',
  ),
  MenuSeed(
    id: 'cccccccc-0006-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000006',
    name: '짜장면',
    description: '달달한 춘장 소스의 클래식 짜장면',
    price: 6000,
    category: '면류',
  ),
  MenuSeed(
    id: 'cccccccc-0006-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000006',
    name: '탕수육(소)',
    description: '바삭한 튀김옷에 새콤달콤 소스를 곁들인 탕수육',
    price: 13000,
    category: '밥류',
  ),

  // ── 서브웨이 ──────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0007-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000007',
    name: '이탈리안 BMT',
    description: '페퍼로니, 살라미, 햄이 들어간 클래식 서브',
    price: 7400,
    category: '양식',
  ),
  MenuSeed(
    id: 'cccccccc-0007-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000007',
    name: '에그마요',
    description: '고소한 에그마요네즈 샌드위치',
    price: 6500,
    category: '양식',
  ),
  MenuSeed(
    id: 'cccccccc-0007-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000007',
    name: '로티세리 치킨',
    description: '부드러운 통닭 가슴살이 들어간 담백한 샌드위치',
    price: 7900,
    category: '양식',
  ),

  // ── 이디야커피 ────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0008-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000008',
    name: '아메리카노',
    description: '깔끔한 에스프레소 기반 커피',
    price: 3300,
    category: '음료',
  ),
  MenuSeed(
    id: 'cccccccc-0008-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000008',
    name: '카페라떼',
    description: '부드러운 우유와 에스프레소의 조화',
    price: 4000,
    category: '음료',
  ),
  MenuSeed(
    id: 'cccccccc-0008-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000008',
    name: '크로플',
    description: '바삭한 크루아상 와플에 아이스크림을 곁들인 디저트',
    price: 4500,
    category: '디저트',
  ),

  // ── 봉추찜닭 ──────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0009-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000009',
    name: '오리지널찜닭',
    description: '간장 베이스 매콤달콤 찜닭 (2~3인분)',
    price: 22000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0009-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000009',
    name: '치즈찜닭',
    description: '모짜렐라 치즈를 듬뿍 올린 찜닭',
    price: 24000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0009-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000009',
    name: '간장찜닭',
    description: '안 매운 간장 베이스 찜닭 (2~3인분)',
    price: 22000,
    category: '밥류',
  ),

  // ── 역전우동 ──────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0010-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000010',
    name: '가케우동',
    description: '진한 가쓰오부시 육수의 따뜻한 우동',
    price: 6500,
    category: '면류',
  ),
  MenuSeed(
    id: 'cccccccc-0010-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000010',
    name: '냉우동',
    description: '시원한 냉육수에 쫄깃한 면발',
    price: 7000,
    category: '면류',
  ),
  MenuSeed(
    id: 'cccccccc-0010-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000010',
    name: '카레우동',
    description: '진한 일본식 카레 소스에 쫄깃한 우동 면',
    price: 7500,
    category: '면류',
  ),

  // ── 백소정 ────────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0011-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000011',
    name: '돈코츠라멘',
    description: '18시간 우려낸 진한 돼지뼈 육수 라멘',
    price: 10000,
    category: '면류',
  ),
  MenuSeed(
    id: 'cccccccc-0011-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000011',
    name: '매운라멘',
    description: '돈코츠 베이스에 매운 소스를 추가한 라멘',
    price: 11000,
    category: '면류',
  ),
  MenuSeed(
    id: 'cccccccc-0011-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000011',
    name: '차슈덮밥',
    description: '부드러운 차슈를 올린 일본식 덮밥',
    price: 9500,
    category: '밥류',
  ),

  // ── 본죽 ──────────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0012-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000012',
    name: '전복죽',
    description: '통전복이 들어간 영양 가득 죽',
    price: 10000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0012-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000012',
    name: '소고기야채죽',
    description: '소고기와 야채를 넣어 끓인 담백한 죽',
    price: 8000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0012-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000012',
    name: '참치야채죽',
    description: '고소한 참치와 야채의 부드러운 조합',
    price: 7500,
    category: '밥류',
  ),

  // ── 교촌치킨 ──────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0013-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000013',
    name: '교촌오리지널',
    description: '바삭한 튀김옷에 달콤한 간장 소스를 입힌 시그니처 치킨',
    price: 18000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0013-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000013',
    name: '레드콤보',
    description: '매콤한 레드 소스의 순살 치킨 + 감자 세트',
    price: 16000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0013-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000013',
    name: '허니콤보',
    description: '달콤한 허니 소스를 입힌 순살 치킨',
    price: 17000,
    category: '밥류',
  ),

  // ── 하남돼지집 ────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0014-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000014',
    name: '삼겹살 (1인분)',
    description: '두툼하게 썬 국내산 삼겹살을 숯불에 구워 먹는 메뉴',
    price: 14000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0014-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000014',
    name: '목살 (1인분)',
    description: '부드러운 결이 살아있는 목살구이',
    price: 13000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0014-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000014',
    name: '된장찌개',
    description: '고기와 함께 먹기 좋은 구수한 된장찌개',
    price: 3000,
    category: '밥류',
  ),

  // ── 쌈밥집 ────────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0015-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000015',
    name: '쌈밥정식',
    description: '신선한 쌈 채소 10종과 쌈장, 밥, 국이 함께 나오는 정식',
    price: 9000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0015-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000015',
    name: '제육쌈밥',
    description: '매콤한 제육볶음을 쌈에 싸서 먹는 보양 한 끼',
    price: 10000,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0015-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000015',
    name: '두부된장쌈밥',
    description: '두부와 된장을 곁들인 담백한 채소 쌈밥',
    price: 8500,
    category: '밥류',
  ),

  // ── 신전떡볶이 ────────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0016-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000016',
    name: '신전떡볶이',
    description: '즉석에서 볶아내는 매콤달콤 떡볶이',
    price: 4500,
    category: '분식',
  ),
  MenuSeed(
    id: 'cccccccc-0016-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000016',
    name: '순대',
    description: '당면이 가득 찬 쫄깃한 찹쌀순대',
    price: 4000,
    category: '분식',
  ),
  MenuSeed(
    id: 'cccccccc-0016-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000016',
    name: '모듬튀김',
    description: '고구마·김말이·오징어 등 바삭한 모듬튀김',
    price: 5000,
    category: '분식',
  ),

  // ── 아웃백 스테이크하우스 ──────────────────────────────
  MenuSeed(
    id: 'cccccccc-0017-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000017',
    name: '토마호크 스테이크',
    description: '육즙 가득한 대형 토마호크 스테이크 (2인 이상)',
    price: 49000,
    category: '양식',
  ),
  MenuSeed(
    id: 'cccccccc-0017-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000017',
    name: '투움바 파스타',
    description: '크리미한 투움바 소스에 새우와 베이컨을 올린 파스타',
    price: 18000,
    category: '면류',
  ),
  MenuSeed(
    id: 'cccccccc-0017-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000017',
    name: '런치 스테이크 세트',
    description: '부드러운 안심 스테이크에 수프·샐러드가 포함된 런치 세트',
    price: 22000,
    category: '양식',
  ),

  // ── CoCo 이찌방야 ────────────────────────────────────
  MenuSeed(
    id: 'cccccccc-0018-4000-8000-000000000001',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000018',
    name: '비프카레',
    description: '부드러운 소고기 덩어리가 들어간 진한 일본식 카레',
    price: 9500,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0018-4000-8000-000000000002',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000018',
    name: '치킨카츠카레',
    description: '바삭한 치킨카츠를 올린 카레라이스',
    price: 10500,
    category: '밥류',
  ),
  MenuSeed(
    id: 'cccccccc-0018-4000-8000-000000000003',
    restaurantId: 'bbbbbbbb-0000-4000-8000-000000000018',
    name: '야채카레',
    description: '감자·당근·브로콜리 등 야채가 듬뿍 들어간 순한 카레',
    price: 8500,
    category: '밥류',
  ),
];
