// ══════════════════════════════════════════════════════════
// 파일 역할: 추천 근거를 카테고리별로 분류하는 기준 정의
//
// 용도:
//   - AI 추천 결과의 reasons 배열을 분류하여 UI에서
//     "왜 이 식당을 추천하는지" 카테고리별로 보여줄 때 사용
//   - CU-11 추천 리스트, CU-13 식당 상세/비교에서 활용
//
// 연관 파일:
//   - backend/src/recommendations/recommendations.service.ts
//   - lib/core/constants/recommendation_texts.dart (문구)
//   - lib/data/seeds/restaurant_seeds.dart (식당 시드)
// ══════════════════════════════════════════════════════════

/// 추천 근거 카테고리 정의
class ReasonCategory {
  const ReasonCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.priority,
  });

  final String id;       // 카테고리 식별자
  final String label;    // 표시용 한글 레이블
  final String icon;     // 카테고리 앞에 붙일 아이콘/이모지
  final int priority;    // 표시 우선순위 (낮을수록 먼저 표시)
}

/// 추천 근거 카테고리 목록
///
/// priority 순서대로 정렬하여 UI에 표시
class RecommendationReasonCategories {
  RecommendationReasonCategories._();

  static const List<ReasonCategory> all = [
    // ── 긍정적 근거 (추천 이유) ───────────────────────────
    ReasonCategory(
      id: 'budget_fit',
      label: '예산',
      icon: '💰',
      priority: 1,
    ),
    ReasonCategory(
      id: 'distance_fit',
      label: '거리',
      icon: '📍',
      priority: 2,
    ),
    ReasonCategory(
      id: 'taste_match',
      label: '취향',
      icon: '😋',
      priority: 3,
    ),
    ReasonCategory(
      id: 'tag_match',
      label: '태그 일치',
      icon: '🏷️',
      priority: 4,
    ),
    ReasonCategory(
      id: 'solo_friendly',
      label: '혼밥',
      icon: '🧑',
      priority: 5,
    ),
    ReasonCategory(
      id: 'group_friendly',
      label: '단체',
      icon: '👥',
      priority: 6,
    ),

    // ── 부정적 근거 (주의 사항) ───────────────────────────
    ReasonCategory(
      id: 'allergen_warning',
      label: '알레르기 주의',
      icon: '⚠️',
      priority: 10,
    ),
    ReasonCategory(
      id: 'budget_over',
      label: '예산 초과',
      icon: '💸',
      priority: 11,
    ),
    ReasonCategory(
      id: 'too_far',
      label: '거리 멀음',
      icon: '🚶',
      priority: 12,
    ),
    ReasonCategory(
      id: 'recent_visit',
      label: '최근 방문',
      icon: '🔄',
      priority: 13,
    ),
    ReasonCategory(
      id: 'dislike_match',
      label: '비선호',
      icon: '👎',
      priority: 14,
    ),
  ];

  /// id로 카테고리 조회
  static ReasonCategory? findById(String id) {
    for (final cat in all) {
      if (cat.id == id) return cat;
    }
    return null;
  }

  /// 긍정적 근거만 필터
  static List<ReasonCategory> get positiveReasons =>
      all.where((c) => c.priority < 10).toList();

  /// 부정적 근거(주의사항)만 필터
  static List<ReasonCategory> get negativeReasons =>
      all.where((c) => c.priority >= 10).toList();
}

/// 추천 점수 계산에 사용하는 가중치
///
/// backend의 recommendations.service.ts 점수 로직과 대응
class RecommendationWeights {
  RecommendationWeights._();

  /// 기본 점수
  static const int baseScore = 100;

  /// 예산 적합 시 가점
  static const int budgetFitBonus = 20;

  /// 예산 초과 시 감점 배율 (초과 비율 × 이 값)
  static const int budgetOverPenaltyRate = 40;

  /// 알레르기 충돌 시 감점
  static const int allergenConflictPenalty = 50;

  /// 비선호 카테고리 충돌 시 감점
  static const int dislikeConflictPenalty = 25;

  /// 최근 7일 내 방문 식당 감점
  static const int recentVisitPenalty = 30;
}
