// ══════════════════════════════════════════════════════════
// 파일 역할: UI 화면용 고정 문구 모음
//
// 연관 파일:
//   - lib/features/menu/menu_screen.dart
//   - lib/data/seeds/restaurant_seeds.dart
// ══════════════════════════════════════════════════════════

/// 식당 상세 화면용 문구
class DetailTexts {
  DetailTexts._();

  static const String sectionMenu = '메뉴';
  static const String sectionInfo = '식당 정보';
  static const String sectionTags = '이런 점이 특징이에요';
  static const String sectionRecommend = '이런 분께 추천해요';
  static const String sectionAvoid = '이런 분은 참고하세요';

  static const String labelPrice = '가격대';
  static const String labelDistance = '거리';
  static const String labelSolo = '혼밥';
  static const String labelGroup = '단체';
  static const String labelPhone = '전화번호';
  static const String labelAddress = '주소';

  static const String closed = '현재 영업 종료';
  static const String open = '영업 중';
  static const String noMenu = '등록된 메뉴가 없습니다';
  static const String soldOut = '품절';
}

/// 비교 화면용 문구
class CompareTexts {
  CompareTexts._();

  static const String title = '식당 비교';
  static const String emptySlot = '식당을 선택하세요';
  static const String maxCompare = '최대 3곳까지 비교할 수 있어요';

  static const String headerName = '식당명';
  static const String headerCategory = '카테고리';
  static const String headerPrice = '가격대';
  static const String headerDistance = '거리';
  static const String headerSolo = '혼밥';
  static const String headerGroup = '단체';
  static const String headerTags = '태그';
  static const String headerSummary = '한 줄 요약';

  static const String betterPrice = '더 저렴해요';
  static const String closerDistance = '더 가까워요';
  static const String bothSoloOk = '둘 다 혼밥 가능';
  static const String bothGroupOk = '둘 다 단체 가능';
}

/// 추천 근거 상세용 짧은 문구
class RecommendTexts {
  RecommendTexts._();

  // ── 상황별 ────────────────────────────────────────────
  static const String quickMeal = '빠르게 먹기 좋아요';
  static const String budgetFriendly = '가성비가 좋아요';
  static const String healthyChoice = '건강한 선택이에요';
  static const String heartyMeal = '든든하게 먹을 수 있어요';
  static const String soloFriendly = '혼밥하기 편해요';
  static const String groupFriendly = '단체로 가기 좋아요';
  static const String quietMood = '조용히 식사하기 좋아요';

  // ── 태그 기반 ─────────────────────────────────────────
  static const String spicyLover = '매운 음식 좋아하는 분께';
  static const String mildPrefer = '자극적이지 않은 맛을 원하는 분께';
  static const String noodleFan = '면 요리를 좋아하는 분께';
  static const String riceFan = '밥 종류를 원하는 분께';
  static const String cafeTime = '식후 커피나 디저트가 필요할 때';

  // ── 제외/회피 ─────────────────────────��───────────────
  static const String tooFar = '거리가 좀 멀어요';
  static const String tooExpensive = '예산 초과일 수 있어요';
  static const String notForSolo = '혼밥하기 어려워요';
  static const String heavyMeal = '가볍게 먹기엔 양이 많아요';
  static const String limitedMenu = '메뉴 선택이 제한적이에요';

  // ── 2주차 보완: 카테고리 기반 ─────────────────────────
  static const String koreanComfort = '익숙한 한식이 생각날 때';
  static const String chineseGroup = '중식은 여럿이 나눠 먹기 좋아요';
  static const String japaneseQuiet = '일식으로 조용히 식사하기 좋아요';
  static const String westernSpecial = '특별한 날 양식 어떠세요';
  static const String snackQuick = '분식으로 간단히 때우기 좋아요';
  static const String meatLovers = '고기가 땡기는 날이에요';
  static const String curryFan = '카레를 좋아하는 분께';
  static const String chickenNight = '치킨과 함께하는 든든한 한 끼';

  // ── 2주차 보완: 알레르기/식이 관련 ────────────────────
  static const String allergenCaution = '알레르기 성분이 포함되어 있어요';
  static const String allergenSafe = '알레르기 안심 메뉴가 있어요';
  static const String glutenFreeOption = '글루텐프리 선택이 가능해요';
  static const String vegetableRich = '채소가 풍부한 메뉴예요';

  // ── 2주차 보완: 최근 방문 관련 ────────────────────────
  static const String recentlyVisited = '최근에 방문한 곳이에요';
  static const String longTimeNoVisit = '오랜만에 가보면 좋은 곳이에요';
}

/// 식당 상세 화면 — 추가 섹션 문구 (2주차 보완)
class DetailExtraTexts {
  DetailExtraTexts._();

  // ── 리뷰 요약 섹션 ───────────────────────────────────
  static const String sectionReview = '방문자 한마디';
  static const String noReview = '아직 등록된 리뷰가 없어요';

  // ── 대표 메뉴 섹션 ───────────────────────────────────
  static const String sectionSignature = '대표 메뉴';
  static const String noSignature = '대표 메뉴가 지정되지 않았어요';

  // ── 영업 정보 ─────────────────────────────────────────
  static const String businessHours = '영업 시간';
  static const String breakTime = '브레이크타임';
  static const String lastOrder = '라스트오더';

  // ── 알레르기 안내 ─────────────────────────────────────
  static const String allergenInfo = '알레르기 정보';
  static const String allergenDisclaimer = '정확한 알레르기 정보는 매장에 직접 확인해 주세요';
}

/// 비교 화면 — 추가 비교 항목 문구 (2주차 보완)
class CompareExtraTexts {
  CompareExtraTexts._();

  static const String headerSignature = '대표 메뉴';
  static const String headerBudgetFit = '예산 적합';
  static const String headerAllergen = '알레르기 주의';
  static const String headerRecentVisit = '최근 방문';
  static const String headerScore = '추천 점수';

  static const String withinBudget = '예산 내';
  static const String overBudget = '예산 초과';
  static const String noAllergen = '해당 없음';
  static const String hasAllergen = '주의 필요';
  static const String visitedRecently = '최근 방문';
  static const String notVisited = '미방문';
}
