// ══════════════════════════════════════════════════════════
// 파일 역할: 사용자 조건(상황)과 식당 태그 간 매핑
//
// 용도:
//   - 추천 엔진에서 사용자 조건을 태그로 변환하여 식당 필터링
//   - 홈 화면 추천 카드에서 상황별 식당 매칭
//
// 연관 파일:
//   - lib/data/seeds/restaurant_seeds.dart (식당 tags 필드)
//   - lib/models/tag.dart (TagGroup 정의)
//   - lib/core/utils/normalizer.dart (태그 정규화)
// ══════════════════════════════════════════════════════════

/// 상황/조건 → 태그 매핑
///
/// key: 상황 키 (코드에서 사용)
/// value: 해당 상황에 맞는 태그 id 목록 (restaurant_seeds.dart의 tags 필드와 매칭)
const Map<String, List<String>> conditionTagMap = {
  // ── 식사 인원 ────────────────────────────────────────────
  'solo': ['solo', 'fast', 'cheap'],
  'group': ['group', 'hearty', 'variety'],

  // ── 식사 속도 (users.speed 와 매핑) ─────────────────────
  'fast_meal': ['fast', 'cheap', 'solo'],
  'normal_meal': ['variety', 'korean', 'japanese'],
  'slow_meal': ['premium', 'quiet', 'group'],

  // ── 식사 목적 ────────────────────────────────────────────
  'light_meal': ['light', 'healthy', 'cafe', 'solo'],
  'hearty_meal': ['hearty', 'korean', 'meat', 'group'],
  'budget_meal': ['cheap', 'fast', 'snack'],
  'premium_meal': ['premium', 'quiet', 'steak', 'japanese'],
  'healthy_meal': ['healthy', 'vegetable', 'light', 'korean'],
  'cafe_time': ['cafe', 'dessert', 'cheap'],

  // ── 분위기/상황 ──────────────────────────────────────────
  'date': ['premium', 'quiet', 'japanese', 'western'],
  'team_dinner': ['group', 'hearty', 'meat', 'chicken', 'beer'],
  'quick_lunch': ['fast', 'cheap', 'solo', 'snack'],
  'rainy_day': ['noodle', 'korean', 'hearty'],
  'hot_weather': ['light', 'japanese', 'cafe'],
};

/// 사용자 speed 값 → 상황 키 변환
///
/// users.speed ('FAST'|'NORMAL'|'SLOW') 를 conditionTagMap 키로 변환
String speedToConditionKey(String speed) {
  switch (speed.toUpperCase()) {
    case 'FAST':
      return 'fast_meal';
    case 'SLOW':
      return 'slow_meal';
    default:
      return 'normal_meal';
  }
}

/// 예산 범위 → 상황 키 변환
///
/// users.budget (원 단위) 를 conditionTagMap 키로 변환
String budgetToConditionKey(int? budget) {
  if (budget == null) return 'normal_meal';
  if (budget <= 8000) return 'budget_meal';
  if (budget <= 15000) return 'normal_meal';
  return 'premium_meal';
}
