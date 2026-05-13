// ══════════════════════════════════════════════════════════
// 파일 역할: 데이터 정규화 유틸리티 함수
//
// 연관 파일:
//   - lib/data/seeds/restaurant_seeds.dart
//   - lib/models/tag.dart
// ══════════════════════════════════════════════════════════

/// 카테고리 문자열 정규화
///
/// 다양한 입력 형태를 통일된 카테고리명으로 변환합니다.
/// 예: '한국식', '코리안', 'korean' → '한식'
String normalizeCategory(String raw) {
  final input = raw.trim().toLowerCase();
  const mapping = {
    '한식': '한식', '한국식': '한식', '코리안': '한식', 'korean': '한식',
    '중식': '중식', '중국식': '중식', '차이니즈': '중식', 'chinese': '중식',
    '일식': '일식', '일본식': '일식', '재패니즈': '일식', 'japanese': '일식',
    '양식': '양식', '서양식': '양식', '웨스턴': '양식', 'western': '양식',
    '분식': '분식', 'snack': '분식',
    '카페': '카페', '커피': '카페', '디저트': '카페', 'cafe': '카페',
  };
  return mapping[input] ?? '기타';
}

/// 가격대 문자열 정규화
///
/// 숫자 범위를 "~만원대" 형태의 가격대 레이블로 변환합니다.
String normalizePriceRange(int minPrice, int maxPrice) {
  if (maxPrice <= 5000) return '5천원 이하';
  if (maxPrice <= 8000) return '5천~8천원';
  if (maxPrice <= 12000) return '8천~1.2만원';
  if (maxPrice <= 20000) return '1.2만~2만원';
  return '2만원 이상';
}

/// 가격 문자열에서 숫자 추출
///
/// "6,500원" → 6500
int? parsePriceString(String priceStr) {
  final digits = priceStr.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isNotEmpty ? int.tryParse(digits) : null;
}

/// 태그 id 정규화
///
/// 공백·대소문자·특수문자를 통일된 형태로 변환합니다.
/// 예: 'Spicy High' → 'spicy_high'
String normalizeTagId(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^a-z0-9_가-힣]'), '');
}

/// 혼밥 여부 표현 정규화
///
/// 다양한 입력을 bool 값으로 변환합니다.
/// 예: '가능', 'O', 'yes', 'true', '1' → true
bool normalizeSoloFriendly(String raw) {
  final input = raw.trim().toLowerCase();
  const trueValues = {
    '가능', '혼밥가능', '혼밥ok', '혼밥 가능', 'o', 'yes', 'true', '1', 'y',
  };
  return trueValues.contains(input);
}

/// 혼밥 여부를 표시 문자열로 변환
String soloFriendlyLabel(bool value) => value ? '혼밥 가능' : '혼밥 어려움';

/// 단체 가능 여부를 표시 문자열로 변환
String groupFriendlyLabel(bool value) => value ? '단체 가능' : '단체 어려움';

// ══════════════════════════════════════════════════════════
// 2주차 보완: 알레르기·식이제한·거리·맵기 정규화
// ══════════════════════════════════════════════════════════

/// 알레르기 원재료 정규화
///
/// 다양한 입력 형태를 표준 알레르기 코드로 변환합니다.
/// 예: '우유', 'milk', '유제품' → 'dairy'
String normalizeAllergen(String raw) {
  final input = raw.trim().toLowerCase();
  const mapping = {
    // 유제품
    '우유': 'dairy', '유제품': 'dairy', '유당': 'dairy',
    '치즈': 'dairy', 'milk': 'dairy', 'dairy': 'dairy',
    // 계란
    '계란': 'egg', '달걀': 'egg', '난류': 'egg', 'egg': 'egg',
    // 밀
    '밀': 'wheat', '글루텐': 'wheat', '소맥': 'wheat',
    'wheat': 'wheat', 'gluten': 'wheat',
    // 대두
    '대두': 'soy', '콩': 'soy', '두부': 'soy', 'soy': 'soy',
    // 땅콩
    '땅콩': 'peanut', 'peanut': 'peanut',
    // 견과류
    '견과류': 'treenut', '호두': 'treenut', '아몬드': 'treenut',
    'treenut': 'treenut',
    // 갑각류
    '갑각류': 'shellfish', '새우': 'shellfish', '게': 'shellfish',
    '랍스터': 'shellfish', 'shellfish': 'shellfish',
    // 생선
    '생선': 'fish', '어류': 'fish', 'fish': 'fish',
    // 돼지고기
    '돼지고기': 'pork', '돈육': 'pork', 'pork': 'pork',
    // 소고기
    '소고기': 'beef', '우육': 'beef', 'beef': 'beef',
  };
  return mapping[input] ?? input;
}

/// 알레르기 코드를 한글 표시 라벨로 변환
String allergenLabel(String code) {
  const labels = {
    'dairy': '유제품',
    'egg': '계란',
    'wheat': '밀(글루텐)',
    'soy': '대두',
    'peanut': '땅콩',
    'treenut': '견과류',
    'shellfish': '갑각류',
    'fish': '생선',
    'pork': '돼지고기',
    'beef': '소고기',
  };
  return labels[code] ?? code;
}

/// 맵기 레벨 정규화
///
/// 0~3 단계로 통일합니다.
/// 0: 순한맛, 1: 약간 매움, 2: 매움, 3: 아주 매움
int normalizeSpiceLevel(String raw) {
  final input = raw.trim().toLowerCase();
  const mapping = {
    '순한맛': 0, '안매움': 0, '순함': 0, 'mild': 0, '0': 0,
    '약간매움': 1, '보통': 1, 'medium': 1, '1': 1,
    '매움': 2, '매운맛': 2, 'hot': 2, 'spicy': 2, '2': 2,
    '아주매움': 3, '극강': 3, 'very_hot': 3, '3': 3,
  };
  return mapping[input] ?? 0;
}

/// 맵기 레벨을 표시 문자열로 변환
String spiceLevelLabel(int level) {
  const labels = ['순한맛', '약간 매움', '매움', '아주 매움'];
  if (level < 0 || level >= labels.length) return labels[0];
  return labels[level];
}

/// 거리(m)를 도보 시간 레이블로 변환
///
/// 성인 평균 보행 속도 약 67m/분 기준
String distanceToWalkingLabel(int meters) {
  final minutes = (meters / 67).ceil();
  if (minutes <= 1) return '도보 1분';
  return '도보 $minutes분';
}

/// 거리(m)를 가까움 레벨로 변환
///
/// 0: 매우 가까움 (~200m), 1: 가까움 (~500m),
/// 2: 보통 (~1km), 3: 멀리 (1km 초과)
int distanceLevel(int meters) {
  if (meters <= 200) return 0;
  if (meters <= 500) return 1;
  if (meters <= 1000) return 2;
  return 3;
}

/// 식이제한 유형 정규화
///
/// 예: '비건', 'vegan' → 'vegan'
String normalizeDietaryType(String raw) {
  final input = raw.trim().toLowerCase();
  const mapping = {
    '비건': 'vegan', '채식': 'vegan', 'vegan': 'vegan',
    '락토': 'lacto', '유제품허용채식': 'lacto', 'lacto': 'lacto',
    '페스코': 'pesco', '해산물채식': 'pesco', 'pesco': 'pesco',
    '할랄': 'halal', 'halal': 'halal',
    '글루텐프리': 'gluten_free', 'gluten_free': 'gluten_free',
    '저염': 'low_salt', 'low_salt': 'low_salt',
    '저칼로리': 'low_cal', 'low_cal': 'low_cal',
  };
  return mapping[input] ?? input;
}

/// 식이제한 코드를 한글 표시 라벨로 변환
String dietaryTypeLabel(String code) {
  const labels = {
    'vegan': '비건(채식)',
    'lacto': '락토 채식',
    'pesco': '페스코 채식',
    'halal': '할랄',
    'gluten_free': '글루텐프리',
    'low_salt': '저염식',
    'low_cal': '저칼로리',
  };
  return labels[code] ?? code;
}

// ══════════════════════════════════════════════════════════
// 식당 가격대(price_range) 표시 헬퍼
//
// 백엔드 restaurants.price_range 컬럼 값은 데이터 출처에 따라
// 의미가 다르게 저장되어 있어, 단순히 "${n}원대" 로 출력하면
// "2원대" / "13원대" 같은 이상한 문구가 나옴.
//
// 데이터 출처별 의미:
//   ① 시드 데이터 (backend/scripts/seed-restaurants.ts)
//      → 실제 평균 가격(원). 예: 5500, 15000, 25000
//   ② 카카오 크롤 (backend/src/crawl/crawl.service.ts:339)
//      → Math.round(avgPrice / 1000). 예: 평균 13000원 → 13
//        또는 메뉴가 없으면 기본값 2
//   ③ Gemini AI 가상 식당 (backend/src/gemini/gemini.service.ts)
//      → 1~5 척도 (1: 저렴, 5: 고급, clamp 처리됨)
//
// 해결 전략(휴리스틱 정규화):
//   값의 크기로 의미를 추정해 하나의 한국식 가격대 레이블로 변환.
//     - n <= 5      → 1~5 척도(Gemini)
//     - n < 1000    → 1000원 단위(크롤) → n*1000원으로 환산
//     - n >= 1000   → 실제 원 단위(시드)
//   환산된 "원" 값을 5천/1만/2만/3만 원 구간 라벨로 매핑.
//
// 사용처:
//   - lib/features/home/home_screen.dart (홈 추천 카드)
//   - lib/features/session/recommendation_list_screen.dart (AI 추천 리스트)
//   - lib/features/restaurant/restaurant_detail_screen.dart (식당 상세)
//   - lib/features/restaurant/restaurant_comparison_screen.dart (식당 비교)
//
// ⚠️ 디자인 토큰/위젯 구조 변경 금지 — 텍스트 포맷만 통일.
// ══════════════════════════════════════════════════════════

/// 식당 price_range 값(int) → 한국식 가격대 레이블
///
/// 매핑 표(환산된 평균가 기준):
///   - ~5,000원       → "5천원 이하"
///   - 5,001~10,000원 → "1만원대"
///   - 10,001~20,000원→ "2만원대"
///   - 20,001~30,000원→ "3만원대"
///   - 30,001원 이상  → "3만원 이상"
///
/// 예시:
///   formatRestaurantPriceRange(2)     → "1만원대"     (1~5 척도 또는 1000원 단위 모두 OK)
///   formatRestaurantPriceRange(5)     → "2만원대"
///   formatRestaurantPriceRange(13)    → "1만원대"     (크롤: 13000원)
///   formatRestaurantPriceRange(5500)  → "1만원대"     (시드: 실제 가격)
///   formatRestaurantPriceRange(15000) → "2만원대"
///   formatRestaurantPriceRange(null)  → "가격 미정"
String formatRestaurantPriceRange(int? raw) {
  // null 또는 0 이하 → 정보 없음으로 통일
  if (raw == null || raw <= 0) return '가격 미정';

  // 값의 크기로 의미 추정 후 원(₩) 단위로 환산
  //  - 1~5: Gemini 1~5 척도 (1=저렴, 5=고급)
  //    → 척도별 대표값으로 환산 (1=5천원, 2=1만원, 3=1.5만원, 4=2.5만원, 5=3.5만원)
  //  - 6~999: 카카오 크롤의 1000원 단위 (예: 13 → 13,000원)
  //  - 1000 이상: 시드 데이터의 실제 원 단위 (예: 5500, 15000)
  int wonEquivalent;
  if (raw <= 5) {
    // Gemini 1~5 척도 → 대표 원 단위로 환산
    const scaleMap = {
      1: 5000,   // 저렴: 분식·도시락 수준
      2: 10000,  // 보통-아래: 한식·일식 일반
      3: 15000,  // 보통: 일식·양식 일반
      4: 25000,  // 보통-위: 양식·고급 한식
      5: 35000,  // 고급
    };
    wonEquivalent = scaleMap[raw] ?? 10000;
  } else if (raw < 1000) {
    // 카카오 크롤: 1000원 단위
    wonEquivalent = raw * 1000;
  } else {
    // 시드 데이터: 실제 원 단위
    wonEquivalent = raw;
  }

  // 환산된 원 단위 → 한국식 가격대 라벨
  if (wonEquivalent <= 5000) return '5천원 이하';
  if (wonEquivalent <= 10000) return '1만원대';
  if (wonEquivalent <= 20000) return '2만원대';
  if (wonEquivalent <= 30000) return '3만원대';
  return '3만원 이상';
}
