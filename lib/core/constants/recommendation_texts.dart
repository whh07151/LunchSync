// ══════════════════════════════════════════════════════════
// 파일 역할: 추천 엔진 결과 표시용 문구 모음
//
// 용도:
//   - CU-11 추천 리스트 화면에서 추천 사유 표시
//   - CU-13 식당 상세/비교에서 추천 근거 상세 표시
//   - recommendations.service.ts의 reasons 배열과 매핑
//
// 연관 파일:
//   - lib/core/constants/ui_texts.dart (RecommendTexts — 짧은 문구)
//   - lib/core/constants/recommendation_reason_categories.dart (분류)
//   - backend/src/recommendations/recommendations.service.ts
// ══════════════════════════════════════════════════════════

/// 추천 사유 상세 문구 (긍정)
class RecommendReasonTexts {
  RecommendReasonTexts._();

  // ── 예산 ─────────────────────────────────────────────────
  static const String budgetFitAll = '모든 멤버의 예산 범위에 들어요';
  static const String budgetFitMost = '대부분의 멤버 예산에 맞아요';
  static const String budgetCheap = '가격이 저렴해서 부담 없어요';
  static const String budgetMidRange = '적당한 가격대의 식당이에요';

  // ── 거리 ─────────────────────────────────────────────────
  static const String distanceVeryClose = '아주 가까워요 (도보 3분 이내)';
  static const String distanceClose = '걸어갈 만한 거리예요 (도보 5분 이내)';
  static const String distanceModerate = '살짝 걸어야 하지만 갈 만해요';

  // ── 취향/태그 ────────────────────────────────────────────
  static const String tasteMatchHigh = '멤버들의 취향과 잘 맞아요';
  static const String tasteMatchPartial = '일부 멤버의 취향과 맞아요';
  static const String categoryPopular = '멤버들이 선호하는 카테고리예요';

  // ── 혼밥/단체 ────────────────────────────────────────────
  static const String soloOk = '혼자 가기에도 편한 곳이에요';
  static const String groupOk = '단체로 가기 좋은 곳이에요';
  static const String bothOk = '혼밥도 단체도 OK인 식당이에요';

  // ── 식사 속도 ────────────────────────────────────────────
  static const String fastService = '빠르게 식사할 수 있어요';
  static const String relaxedDining = '여유롭게 식사하기 좋아요';

  // ── 건강/특징 ────────────────────────────────────────────
  static const String healthyOption = '건강한 메뉴가 있어요';
  static const String heartyMeal = '든든하게 먹을 수 있어요';
  static const String varietyMenu = '메뉴가 다양해서 골라 먹기 좋아요';
  static const String quietMood = '조용히 식사하기 좋은 분위기예요';
}

/// 제외/회피 사유 상세 문구 (부정)
class AvoidReasonTexts {
  AvoidReasonTexts._();

  // ── 예산 초과 ────────────────────────────────────────────
  static const String budgetOverSlight = '예산을 약간 초과할 수 있어요';
  static const String budgetOverMuch = '예산 대비 가격이 높은 편이에요';

  // ── 거리 ─────────────────────────────────────────────────
  static const String tooFarWalking = '도보로 가기엔 조금 멀어요';
  static const String tooFarReturn = '복귀 시간 안에 돌아오기 빠듯해요';

  // ── 알레르기/식이 ────────────────────────────────────────
  static const String allergenWarning = '멤버 중 알레르기 해당 식재료가 있어요';
  static const String allergenSpecific = '({allergen}) 알레르기가 있는 멤버가 있어요';
  static const String dietaryConflict = '식이제한 조건에 맞지 않을 수 있어요';

  // ── 최근 방문 ────────────────────────────────────────────
  static const String recentVisit7d = '최근 7일 이내에 방문한 식당이에요';
  static const String recentVisit3d = '3일 전에 방문한 곳이에요';

  // ── 비선호 ───────────────────────────────────────────────
  static const String dislikeCategory = '멤버 중 비선호 카테고리로 설정한 분이 있어요';
  static const String dislikeSpicy = '매운 음식을 피하는 멤버가 있어요';

  // ── 혼밥/단체 제약 ───────────────────────────────────────
  static const String notSoloFriendly = '혼밥하기 어려운 식당이에요';
  static const String notGroupFriendly = '단체로 가기엔 좌석이 부족할 수 있어요';
  static const String portionTooLarge = '1인분 기준 양이 많을 수 있어요';
}

/// 추천 결과 요약 문구 (카드 하단 등)
class RecommendSummaryTexts {
  RecommendSummaryTexts._();

  static const String topPick = '오늘의 1순위 추천이에요';
  static const String goodOption = '괜찮은 선택지예요';
  static const String alternative = '다른 선택지도 고려해 보세요';
  static const String noGoodMatch = '조건에 완벽히 맞는 식당이 없어요';
  static const String allAvoided = '모든 후보가 제외 조건에 해당해요';

  /// 추천 점수 구간별 요약 문구
  static String summaryForScore(int score) {
    if (score >= 80) return topPick;
    if (score >= 50) return goodOption;
    if (score >= 30) return alternative;
    return noGoodMatch;
  }
}
