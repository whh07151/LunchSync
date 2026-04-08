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
