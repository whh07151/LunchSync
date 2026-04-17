// ══════════════════════════════════════════════════════════
// 파일 역할: 홈 화면 추천 카드 표시 기준 및 설정
//
// 용도:
//   - 홈 대시보드(CU-06)에서 AI 추천 식당 카드를 표시할 때
//     필요한 최소 필드 기준, 카드 수, 정렬 기준 등을 정의
//
// 연관 파일:
//   - lib/features/home/home_screen.dart (추천 카드 UI)
//   - lib/data/seeds/restaurant_seeds.dart (식당 데이터)
//   - backend/src/recommendations/ (추천 점수 계산)
// ══════════════════════════════════════════════════════════

/// 홈 화면 추천 카드 표시 설정
class HomeRecommendationConfig {
  HomeRecommendationConfig._();

  /// 홈 화면에 표시할 최대 추천 식당 수
  static const int maxCards = 5;

  /// 추천 카드에 표시할 최소 점수 (이 점수 미만이면 표시 안 함)
  static const int minScoreThreshold = 30;

  /// 추천 카드에 반드시 포함해야 할 필드 목록
  ///
  /// 이 필드들이 null이면 카드를 표시하지 않음
  static const List<String> requiredFields = [
    'name',
    'category',
    'priceRange',
  ];

  /// 카드에 표시할 선택 필드 (있으면 표시, 없으면 생략)
  static const List<String> optionalFields = [
    'distanceLabel',
    'rating',
    'oneLineSummary',
    'tags',
  ];

  /// 추천 카드 상황별 제목 문구
  static const Map<String, String> situationTitles = {
    'default': '오늘의 추천',
    'budget': '가성비 좋은 곳',
    'quick': '빠르게 먹기 좋은 곳',
    'healthy': '건강한 한 끼',
    'group': '단체로 가기 좋은 곳',
    'solo': '혼밥하기 좋은 곳',
    'nearby': '가까운 곳',
    'revisit': '다시 가보면 좋은 곳',
  };

  /// 추천 카드 하단 보조 문구 (score 범위별)
  static const Map<String, String> scoreLabels = {
    'high': '강력 추천',       // 80점 이상
    'medium': '추천',          // 50~79점
    'low': '참고해 보세요',    // 30~49점
  };

  /// score → label 변환
  static String scoreLabelFor(int score) {
    if (score >= 80) return scoreLabels['high']!;
    if (score >= 50) return scoreLabels['medium']!;
    return scoreLabels['low']!;
  }
}
