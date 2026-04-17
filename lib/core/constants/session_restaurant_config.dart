// ══════════════════════════════════════════════════════════
// 파일 역할: 세션에서 식당 후보를 연결할 때 필요한 최소 필드 및 기준
//
// 용도:
//   - CU-09 세션 생성 후 → AI 추천 → 투표 → 식당 확정 흐름에서
//     식당 후보를 선정·표시·비교할 때 필요한 기준 정의
//   - 세션의 조건(radius, budget, returnMinutes)과
//     식당 데이터를 연결하는 규칙
//
// 연관 파일:
//   - lib/models/session.dart (Session 모델 — radius, budget, returnMinutes)
//   - lib/data/seeds/restaurant_seeds.dart (식당 시드)
//   - backend/src/recommendations/recommendations.service.ts
//   - backend/src/sessions/sessions.service.ts
// ══════════════════════════════════════════════════════════

/// 세션-식당 연결 설정
class SessionRestaurantConfig {
  SessionRestaurantConfig._();

  /// 추천 후보로 선정하기 위한 식당 최소 필드
  ///
  /// 이 필드들이 null이면 추천 후보에서 제외
  static const List<String> requiredRestaurantFields = [
    'id',
    'name',
    'category',
    'priceRange',
  ];

  /// 투표 화면에서 필요한 식당 필드
  static const List<String> voteDisplayFields = [
    'id',
    'name',
    'category',
    'priceRange',
    'distanceLabel',
    'oneLineSummary',
  ];

  /// 확정 후 메뉴 화면 이동 시 필요한 필드
  static const List<String> menuTransitionFields = [
    'id',         // restaurantId → GET /restaurants/:id/menus
    'name',       // 앱바 제목으로 표시
  ];

  /// 세션 반경(m)에 따른 식당 필터링 기본값
  ///
  /// Session.radius가 null일 때 사용할 기본 반경
  static const int defaultRadiusMeters = 500;

  /// 세션 예산(원)에 따른 식당 필터링 기본값
  ///
  /// Session.budget이 null일 때 사용할 기본 예산
  static const int defaultBudgetWon = 15000;

  /// 세션 복귀시간(분)에 따른 거리 제한 기본값
  ///
  /// Session.returnMinutes가 null일 때 사용할 기본값
  static const int defaultReturnMinutes = 30;

  /// 복귀 시간으로 최대 도보 거리(m) 계산
  ///
  /// 왕복 기준이므로 식사시간(20분)을 빼고 편도 시간 × 보행속도(67m/분)
  static int maxWalkingDistance(int returnMinutes) {
    final walkingMinutesOneWay = (returnMinutes - 20) ~/ 2;
    if (walkingMinutesOneWay <= 0) return 200;
    return walkingMinutesOneWay * 67;
  }

  /// 추천 후보 최대 수
  static const int maxCandidates = 10;

  /// 투표 후보 최소 수 (이 이하면 조건 완화 필요 안내)
  static const int minCandidates = 2;

  /// 조건 완화 안내 문구
  static const String relaxConditionMessage =
      '조건에 맞는 식당이 부족해요. 반경이나 예산을 넓혀 보세요.';
}
