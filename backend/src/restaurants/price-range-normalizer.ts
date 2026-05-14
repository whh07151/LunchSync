// ══════════════════════════════════════════════════════════
// 파일 역할: restaurants.price_range 값 → "원(₩) 단위" 환산 헬퍼
//
// 배경 (2026-05-14):
//   `restaurants.price_range` 컬럼은 데이터 출처에 따라 단위가 다름.
//   단일 컬럼에 의미가 다른 값이 섞여 있어 추천 점수·필터·정렬에서
//   회귀(regression)가 반복 발생 → 마이그레이션 없이 휴리스틱으로 통일.
//
//   ① 시드 (backend/scripts/seed-restaurants.ts)
//      → 실제 평균 가격(원). 예: 5500, 8000, 15000, 25000
//   ② 카카오 크롤 (backend/src/crawl/crawl.service.ts:339)
//      → Math.round(avgPrice / 1000). 예: 평균 13,000원 → 13
//        메뉴 수집 실패 시 기본값 2 가 들어가기도 함.
//   ③ Gemini AI 가상 식당 (backend/src/gemini/gemini.service.ts)
//      → 1~5 척도 (1: 저렴 ~ 5: 고급). 항상 clamp(1, 5) 처리됨.
//
//   ※ 회귀 사례 (이 헬퍼 도입 전):
//     recommendations.service.ts 에서 `r.price_range * 10000` 곱셈으로
//     예산 비율을 계산했더니, 시드 5500 입력시 5,500 × 10,000 = 5천5백만원
//     으로 환산되어 항상 -30 페널티가 부과 → AI 점수 분산이 사라짐.
//
// ⚠️ 프론트 동기화:
//   본 헬퍼는 `lib/core/utils/normalizer.dart::formatRestaurantPriceRange`
//   와 1:1 동일한 휴리스틱을 사용. 한쪽 분기를 바꾸면 다른 쪽도 반드시
//   같이 갱신할 것. (라벨 변환은 프론트, 추천 점수 계산은 백엔드.)
//
// 휴리스틱 분기 표(입력값 → 환산 원 단위):
//   ─────────────────────────────────────────────────────────
//   입력 raw  | 추정 출처     | 환산 (원)     | 비고
//   ─────────────────────────────────────────────────────────
//        1   | Gemini 척도   |    5,000     | 분식·도시락
//        2   | Gemini 척도   |   10,000     | 한식·일식 일반
//        3   | Gemini 척도   |   15,000     | 일식·양식 일반
//        4   | Gemini 척도   |   25,000     | 양식·고급 한식
//        5   | Gemini 척도   |   35,000     | 고급
//        7   | 카카오 크롤   |    7,000     | 7 × 1000
//       13   | 카카오 크롤   |   13,000     | 13 × 1000
//     5500   | 시드          |    5,500     | 실제 원 단위 그대로
//     8000   | 시드          |    8,000     |
//    15000   | 시드          |   15,000     |
//     null   | 알 수 없음    |     null     | 호출측이 페널티/보너스 skip
//        0   | 알 수 없음    |     null     | (음수/0 도 동일 처리)
//   ─────────────────────────────────────────────────────────
//
// 사용처:
//   - backend/src/recommendations/recommendations.service.ts
//       → 예산 적합도 점수(가격 비율) 계산에 사용
//   - backend/src/restaurants/restaurants.service.ts
//       → 응답 단에 estimatedPriceWon 필드로 동봉 (프론트 옵션)
// ══════════════════════════════════════════════════════════

// Gemini 1~5 척도 → 대표 원 단위 매핑.
// 척도의 의미는 normalizer.dart 와 동일하므로 값 변경 시 양쪽 동기 필요.
const GEMINI_SCALE_TO_WON: Record<number, number> = {
  1: 5000, // 저렴: 분식·도시락 수준
  2: 10000, // 보통-아래: 한식·일식 일반
  3: 15000, // 보통: 일식·양식 일반
  4: 25000, // 보통-위: 양식·고급 한식
  5: 35000, // 고급
};

// 휴리스틱 출처 추정 경계 임계값.
//   - 5 이하: Gemini 척도로 간주 (1~5)
//   - 6 ~ 999: 카카오 크롤의 1000원 단위로 간주
//   - 1000 이상: 시드 데이터의 실제 원 단위로 간주
const GEMINI_SCALE_MAX = 5;
const CRAWL_UNIT_MAX = 999;

/**
 * price_range 값을 합리적인 원(₩) 단위 평균가로 환산.
 *
 * 호출측은 반환값이 `null` 이면 가격 정보가 없는 것으로 간주해
 * 페널티/보너스 계산을 모두 skip 하는 것이 안전 (페널티 폭주 방지).
 *
 * 프론트 `formatRestaurantPriceRange` 와 동일한 휴리스틱을 사용한다.
 *
 * @param raw restaurants.price_range 컬럼 raw 값 (출처에 따라 단위 다름)
 * @returns 추정 평균 가격 (원). 값이 없거나 0/음수면 null.
 *
 * @example
 *   normalizePriceRangeToWon(5500)  // 5500  (시드: 그대로)
 *   normalizePriceRangeToWon(13)    // 13000 (크롤: × 1000)
 *   normalizePriceRangeToWon(3)     // 15000 (Gemini 척도)
 *   normalizePriceRangeToWon(null)  // null  (호출측에서 skip)
 */
export function normalizePriceRangeToWon(
  raw: number | null | undefined,
): number | null {
  // null / undefined / 0 / 음수 → 정보 없음. 호출측에서 skip 하도록 null 반환.
  if (raw == null || raw <= 0) return null;

  // ① 1~5: Gemini AI 가상 식당의 1~5 척도로 간주.
  //   매핑 테이블에 없는 값(이론상 발생 안 함)은 안전하게 null 처리.
  if (raw <= GEMINI_SCALE_MAX) {
    return GEMINI_SCALE_TO_WON[raw] ?? null;
  }

  // ② 6~999: 카카오 크롤의 1000원 단위 (예: 13 → 13,000원).
  if (raw <= CRAWL_UNIT_MAX) {
    return raw * 1000;
  }

  // ③ 1000 이상: 시드 데이터의 실제 원 단위 (예: 5500, 8000, 15000).
  //   이미 원(₩) 단위이므로 그대로 반환.
  return raw;
}
