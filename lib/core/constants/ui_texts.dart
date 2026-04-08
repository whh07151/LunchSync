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

  // ── 제외/회피 ─────────────────────────────────────────
  static const String tooFar = '거리가 좀 멀어요';
  static const String tooExpensive = '예산 초과일 수 있어요';
  static const String notForSolo = '혼밥하기 어려워요';
  static const String heavyMeal = '가볍게 먹기엔 양이 많아요';
  static const String limitedMenu = '메뉴 선택이 제한적이에요';
}
