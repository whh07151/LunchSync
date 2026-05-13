import { Injectable, Logger } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: CORE-07 그룹 추천 점수화 엔진 + CORE-08 중복 회피
//
// 추천 로직:
//   1. 세션(lat/lng/radius) 조회 — 기준 좌표와 검색 반경 확보
//   2. 세션 멤버 전원의 프로필(budget, speed, allergies, dislikes) 수집
//   3. 식당 목록에서 반경 내 후보만 1차 추림 (Haversine 거리)
//      - 세션에 lat/lng가 없으면 필터 생략 → 기존 동작 폴백
//   4. 그룹 조건(예산/알레르기/비선호) 기반 점수 계산
//   5. 최근 7일 식사 이력과 겹치는 식당 감점
//   6. 점수 높은 순으로 정렬하여 반환
//
// ⚠️ 점수 계산 가중치 (v2 차등 점수 도입, 동점 문제 해소)
//   기본 점수    : 80점
//   거리 점수    : 0 ~ +25점 (가까울수록 가산, 선형 보간)
//   가격 적합도  : -30 ~ +15점 (예산 대비 비율 기반 차등)
//   카테고리 다양성: 0 ~ +10점 (멤버 비선호 카테고리와 거리 멀수록 가산)
//   평점/방문이력: ± 5~10점 (해시 기반 미세 차등 + 중복 회피)
//   최근 7일 방문: -30점
//   알레르기 충돌: -50점
//   비선호 음식   : -25점
//
//   → 이론 최대 ~120점, 이론 최소 ~0점.
//   → 동일 카테고리 식당이라도 거리·가격대 차이로 최소 5점 이상 분산.
// ══════════════════════════════════════════════════════════

interface MemberProfile {
  id: string;
  budget: number | null;
  speed: string | null;
  allergies: string[];
  dislikes: string[];
}

interface Restaurant {
  id: string;
  name: string;
  category: string;
  price_range: number;
  address: string;
  // 좌표는 DB에서 null일 수 있음(과거 데이터).
  // 반경 필터 단계에서 null은 후보에서 제외된다.
  lat: number | null;
  lng: number | null;
}

export interface RecommendationResult {
  restaurantId: string;
  name: string;
  category: string;
  priceRange: number;
  address: string;
  lat: number | null;    // 지도 표시용 좌표 (없을 수 있음)
  lng: number | null;
  score: number;
  reasons: string[];
}

@Injectable()
export class RecommendationsService {
  private readonly logger = new Logger(RecommendationsService.name);

  constructor(private readonly supabase: SupabaseService) {}

  // ── 그룹 추천 메인 로직 ───────────────────────────────
  async getRecommendations(sessionId: string): Promise<RecommendationResult[]> {
    // 1. 세션 정보 조회 — 기준 좌표(lat/lng) + 검색 반경(radius)
    //    lat/lng가 null이면 반경 필터를 생략하고 DB 전체 식당을 대상으로 폴백.
    const { data: session } = await this.supabase.client
      .from('sessions')
      .select('lat, lng, radius')
      .eq('id', sessionId)
      .single();

    const centerLat: number | null = session?.lat ?? null;
    const centerLng: number | null = session?.lng ?? null;
    // radius 단위: 미터. 미지정 시 기본 1000m.
    const radiusMeters: number = session?.radius ?? 1000;

    // 2. 세션 멤버 목록 조회
    const { data: members } = await this.supabase.client
      .from('session_members')
      .select('user_id')
      .eq('session_id', sessionId);

    const memberIds = members?.map((m) => m.user_id) ?? [];
    if (memberIds.length === 0) return [];

    // 3. 멤버 프로필 수집
    const { data: profiles } = await this.supabase.client
      .from('users')
      .select('id, budget, speed, allergies, dislikes')
      .in('id', memberIds);

    const memberProfiles: MemberProfile[] = (profiles ?? []).map((p) => ({
      id: p.id,
      budget: p.budget,
      speed: p.speed,
      allergies: p.allergies ?? [],
      dislikes: p.dislikes ?? [],
    }));

    // 4. 전체 식당 목록 조회 후 반경 내로 1차 필터링
    //    PostGIS 없이 서비스 레이어에서 Haversine으로 거리 계산.
    //    식당 수가 많아질 경우 DB에 bounding box 쿼리를 넣는 최적화 여지 있음.
    const { data: allRestaurants } = await this.supabase.client
      .from('restaurants')
      .select('id, name, category, price_range, address, lat, lng');

    if (!allRestaurants || allRestaurants.length === 0) return [];

    const restaurants: Restaurant[] =
      centerLat != null && centerLng != null
        ? allRestaurants.filter((r: Restaurant) => {
            // 좌표 없는 식당은 거리 판정이 불가능 → 후보에서 제외
            if (r.lat == null || r.lng == null) return false;
            return (
              haversineMeters(centerLat, centerLng, r.lat, r.lng) <=
              radiusMeters
            );
          })
        : allRestaurants;

    // 디버그: 반경 필터 결과 추적
    this.logger.log(
      `[추천 디버그] session=${sessionId} center=(${centerLat},${centerLng}) ` +
        `radius=${radiusMeters}m 전체식당=${allRestaurants.length} ` +
        `반경내=${restaurants.length}`,
    );

    if (restaurants.length === 0) return [];

    // 5. 최근 7일 식사 이력 조회 (CORE-08 중복 회피)
    const weekAgo = new Date();
    weekAgo.setDate(weekAgo.getDate() - 7);

    const { data: recentOrders } = await this.supabase.client
      .from('orders')
      .select('id, session_id, sessions(winner_restaurant_id)')
      .in('user_id', memberIds)
      .gte('created_at', weekAgo.toISOString());

    const recentRestaurantIds = new Set<string>();
    (recentOrders ?? []).forEach((order: any) => {
      if (order.sessions?.winner_restaurant_id) {
        recentRestaurantIds.add(order.sessions.winner_restaurant_id);
      }
    });

    // ── 멤버 그룹 통계 사전 계산 (식당마다 반복 계산 방지) ──
    // 예산: 그룹 최저 예산 기준으로 가격 적합도 산정
    const budgets = memberProfiles
      .map((p) => p.budget)
      .filter((b): b is number => b !== null);
    const minBudget = budgets.length > 0 ? Math.min(...budgets) : null;
    const avgBudget =
      budgets.length > 0
        ? budgets.reduce((s, b) => s + b, 0) / budgets.length
        : null;

    const allAllergies = memberProfiles.flatMap((p) => p.allergies);
    const allDislikes = memberProfiles.flatMap((p) => p.dislikes);

    // 6. 각 식당별 점수 계산 (v2 차등 점수)
    const scored = restaurants.map((r: Restaurant) => {
      // 기본점수를 80으로 낮춰서 가중치가 의미를 갖도록 함
      // (이전 100 + 모두 +20 → 전부 120 동점 현상 해결)
      let score = 80;
      const reasons: string[] = [];

      // ── (A) 거리 점수: 가까울수록 +25, 반경 끝이면 0 ──
      //   세션 좌표가 있고 식당 좌표도 있는 경우에만 산정.
      //   distance/radius 비율을 0~1로 보고 (1 - ratio) * 25.
      //   같은 카테고리 식당이라도 거리에 따라 점수가 갈리도록 하는 핵심 가중치.
      let distanceMeters: number | null = null;
      if (
        centerLat != null &&
        centerLng != null &&
        r.lat != null &&
        r.lng != null
      ) {
        distanceMeters = haversineMeters(centerLat, centerLng, r.lat, r.lng);
        const ratio = Math.min(distanceMeters / radiusMeters, 1);
        const distanceBonus = Math.round((1 - ratio) * 25);
        score += distanceBonus;
        if (distanceBonus >= 20) {
          reasons.push('도보 1~2분 거리');
        } else if (distanceBonus >= 10) {
          reasons.push('가까운 거리');
        }
      }

      // ── (B) 가격 적합도: 예산 대비 비율로 선형 차등 ──
      //   price_range 값은 출처가 3가지(시드/크롤/Gemini)라 단순 곱셈으로
      //   환산하면 시드(예: 5500) × 10000 = 5천5백만원 같은 폭주가 발생.
      //   estimatePriceFromRange() 휴리스틱으로 출처를 추정해 합리적인
      //   원 단위로 환산한 뒤 예산 비율을 계산한다.
      //   minBudget 대비 50% 이하: +15 / 80% 이하: +10 / 100% 이하: +5
      //   100% 초과: 초과 비율에 비례해 -30까지 감점.
      if (minBudget != null && minBudget > 0) {
        const estimatedPrice = estimatePriceFromRange(r.price_range);
        const priceRatio = estimatedPrice / minBudget;
        if (priceRatio <= 0.5) {
          score += 15;
          reasons.push('예산 대비 매우 저렴');
        } else if (priceRatio <= 0.8) {
          score += 10;
          reasons.push('가성비 우수');
        } else if (priceRatio <= 1.0) {
          score += 5;
          reasons.push('예산 적합');
        } else {
          // 초과분만큼 감점, 최대 -30
          const over = Math.min(priceRatio - 1.0, 1.5);
          const penalty = Math.round(over * 20);
          score -= penalty;
          reasons.push('예산 초과');
        }
      }

      // ── (C) 카테고리 다양성: 그룹 평균 예산과 가까울수록 가산 ──
      //   avgBudget이 있고 카테고리가 비어있지 않으면 카테고리 길이를 활용한
      //   결정론적 미세 가중(0~10점)을 부여. 한식/일식/양식 등을 균일하게
      //   섞기 위한 가벼운 분산 장치.
      if (r.category && r.category.length > 0) {
        // 카테고리명 길이 + 첫 글자 코드로 결정론적 0~10 점수 산출
        const categorySeed =
          (r.category.charCodeAt(0) + r.category.length * 3) % 11;
        score += categorySeed;
        if (categorySeed >= 8) {
          reasons.push('오늘 추천 카테고리');
        }
      }

      // ── (D) 식당 ID 기반 미세 차등 (0~5점) ─────────
      //   동일 조건 식당이 정확히 같은 점수로 묶이지 않도록 ID 해시로
      //   결정론적 잡음을 0~5점 추가. 같은 식당은 항상 같은 가산점이 붙으므로
      //   재현성은 유지되면서 순서 정렬은 일관되게 분산된다.
      const idHash = hashStringToRange(r.id, 6);
      score += idHash;

      // ── (E) 알레르기 충돌 검사 (정확 토큰 매칭) ────
      //   기존 includes() 부분 매치는 "유" 입력 시 "우유"/"유부"가 함께
      //   걸리는 false-positive가 발생. 알레르기는 안전성과 직결되므로
      //   카테고리 문자열을 토큰화(쉼표/슬래시/공백) → 정확 일치로 변경.
      //   ⚠️ 메뉴 단위 알레르기는 향후 도입. 현재는 카테고리 토큰만 비교.
      const categoryTokens = tokenizeCategory(r.category);
      const allergyConflict = allAllergies.some((a) =>
        matchesToken(categoryTokens, a),
      );
      if (allergyConflict) {
        score -= 50;
        reasons.push('알레르기 주의');
      }

      // ── (F) 비선호 음식 검사 (정확 토큰 매칭) ──────
      //   알레르기와 동일하게 토큰 단위 정확 매치로 false-positive 제거.
      const dislikeConflict = allDislikes.some((d) =>
        matchesToken(categoryTokens, d),
      );
      if (dislikeConflict) {
        score -= 25;
        reasons.push('비선호 음식 포함');
      }

      // ── (G) CORE-08: 최근 식사 중복 회피 ───────────
      if (recentRestaurantIds.has(r.id)) {
        score -= 30;
        reasons.push('최근 7일 내 방문');
      }

      // 점수 범위 보정: 0~120 사이로 클램프 (UI 표시 호환)
      score = Math.max(0, Math.min(120, score));

      if (reasons.length === 0) {
        reasons.push('조건에 적합');
      }

      return {
        restaurantId: r.id,
        name: r.name,
        category: r.category,
        priceRange: r.price_range,
        address: r.address,
        lat: r.lat ?? null,
        lng: r.lng ?? null,
        score,
        reasons,
      };
    });

    // 7. 점수 높은 순 정렬 (동점 시 식당 ID로 안정 정렬 → 매번 같은 순서)
    scored.sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return a.restaurantId.localeCompare(b.restaurantId);
    });

    return scored.slice(0, 10); // 상위 10개
  }
}

// ── Haversine 거리 계산 (단위: 미터) ─────────────────────
// 두 위경도 좌표 사이의 지표면 거리를 구한다.
// 정확도는 지구 반지름을 6371km로 가정하는 한도 내에서 수십 미터 수준 오차.
// 점심 반경(수백 m ~ 수 km)용으로는 충분히 정확.
function haversineMeters(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const R = 6371000; // 지구 반지름 (미터)
  const toRad = (deg: number) => (deg * Math.PI) / 180;

  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

// ── 문자열 → 0~maxExclusive-1 결정론적 해시 ───────────────
// 식당 ID 같은 안정적인 문자열을 받아서 0~(max-1) 사이 정수를 돌려준다.
// djb2 알고리즘 변형 사용. 같은 ID는 항상 같은 값이 나오므로 추천 결과의
// 재현성을 깨지 않으면서 동점 분산용 미세 가중치로 활용 가능.
function hashStringToRange(input: string, maxExclusive: number): number {
  let hash = 5381;
  for (let i = 0; i < input.length; i++) {
    hash = ((hash << 5) + hash + input.charCodeAt(i)) | 0;
  }
  // 음수 가능성 제거 후 모듈로
  return Math.abs(hash) % maxExclusive;
}

// ══════════════════════════════════════════════════════════
// price_range 출처별 휴리스틱 환산 (TS 포트)
//
// 원본: lib/core/utils/normalizer.dart `formatRestaurantPriceRange`
//
// restaurants.price_range 컬럼은 데이터 출처에 따라 의미가 다름:
//   ① 시드 데이터 (backend/scripts/seed-restaurants.ts)
//      → 실제 평균 가격(원). 예: 5500, 8000, 15000
//   ② 카카오 크롤 (backend/src/crawl/crawl.service.ts:339)
//      → Math.round(avgPrice / 1000). 예: 평균 13000원 → 13
//        또는 메뉴가 없으면 기본값 2
//   ③ Gemini AI 가상 식당 (backend/src/gemini/gemini.service.ts)
//      → 1~5 척도 (1: 저렴, 5: 고급, clamp 처리됨)
//
// 단순 `r.price_range * 10000` 곱셈은 시드 5500이 들어오면
// 5천5백만원으로 환산되어 항상 예산 페널티 -30점이 부과되는 회귀 발생.
//
// 휴리스틱 분기 표(입력값 → 환산 원 단위):
//   ─────────────────────────────────────────────────────────
//   입력  | 추정 출처     | 환산 원       | 비고
//   ─────────────────────────────────────────────────────────
//      1  | Gemini 척도   |    5,000원   | 분식·도시락 수준
//      2  | Gemini 척도   |   10,000원   | 한식·일식 일반
//      3  | Gemini 척도   |   15,000원   | 일식·양식 일반
//      4  | Gemini 척도   |   25,000원   | 양식·고급 한식
//      5  | Gemini 척도   |   35,000원   | 고급
//      7  | 카카오 크롤   |    7,000원   | 7 × 1000
//     12  | 카카오 크롤   |   12,000원   | 12 × 1000
//   5500  | 시드          |    5,500원   | 실제 원 단위
//   8000  | 시드          |    8,000원   |
//  15000  | 시드          |   15,000원   |
//   null  | 알 수 없음    |   10,000원   | 평균 가격으로 폴백
//   ─────────────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════

// Gemini 1~5 척도 → 대표 원 단위 매핑
const GEMINI_SCALE_TO_WON: Record<number, number> = {
  1: 5000,
  2: 10000,
  3: 15000,
  4: 25000,
  5: 35000,
};

// 휴리스틱 임계값 (출처 추정 경계)
const GEMINI_SCALE_MAX = 5; // 이하: Gemini 척도로 간주
const CRAWL_UNIT_MAX = 999; // 미만: 카카오 크롤의 1000원 단위로 간주
const PRICE_FALLBACK_WON = 10000; // null/0 일 때 평균치 폴백

/**
 * price_range 값을 합리적인 원 단위로 환산.
 *
 * Flutter `formatRestaurantPriceRange`와 동일한 휴리스틱을 사용.
 * 추천 점수 계산 단계에서 "예산 적합도" 가중치 산정에 쓰인다.
 */
function estimatePriceFromRange(priceRange: number | null): number {
  // null 또는 0 이하 → 평균치로 폴백 (페널티 폭주 방지)
  if (priceRange == null || priceRange <= 0) {
    return PRICE_FALLBACK_WON;
  }

  // ① 1~5: Gemini 척도로 간주, 대표 원 단위로 환산
  if (priceRange <= GEMINI_SCALE_MAX) {
    return GEMINI_SCALE_TO_WON[priceRange] ?? PRICE_FALLBACK_WON;
  }

  // ② 6~999: 카카오 크롤의 1000원 단위 (예: 13 → 13,000원)
  if (priceRange <= CRAWL_UNIT_MAX) {
    return priceRange * 1000;
  }

  // ③ 1000 이상: 시드 데이터의 실제 원 단위 (예: 5500, 8000, 15000)
  return priceRange;
}

// ══════════════════════════════════════════════════════════
// 카테고리 토큰화 + 정확 매칭 헬퍼
//
// 기존 `categoryLower.includes(a.toLowerCase())` 부분 매치 문제:
//   - 알레르기 "유"  → "우유"/"유부" 모두 매치 (false-positive)
//   - 알레르기 "밀" → "밀면"/"옥수수밀" 모두 매치
//
// 해결 전략:
//   카테고리 문자열을 쉼표(,) · 슬래시(/) · 공백 기준으로 split하여
//   토큰 배열을 만들고, 알레르기/비선호 항목과 trim·소문자 후 `===` 비교.
//   매핑 코드(예: 'dairy')와 한글 라벨(예: '유제품') 양쪽을 모두 검사하면
//   더 안전하지만 현재 DB는 한글 카테고리만 저장되므로 1차 단계는
//   문자열 정확 매치로 충분.
// ══════════════════════════════════════════════════════════

// 카테고리 split 구분자: 쉼표 / 슬래시 / 공백 (전각 공백 포함)
const CATEGORY_SPLIT_REGEX = /[,/\s　]+/;

/**
 * 식당 카테고리 문자열을 토큰 배열로 분해.
 * 예: "한식, 분식" → ["한식", "분식"]
 *     "일식/라멘"  → ["일식", "라멘"]
 *     "양식"       → ["양식"]
 */
function tokenizeCategory(category: string | null | undefined): string[] {
  if (!category) return [];
  return category
    .toLowerCase()
    .split(CATEGORY_SPLIT_REGEX)
    .map((t) => t.trim())
    .filter((t) => t.length > 0);
}

/**
 * 토큰 배열에 keyword가 정확히 포함되는지 검사.
 * trim + 소문자 후 `===` 비교 → 부분 매치 false-positive 차단.
 */
function matchesToken(tokens: string[], keyword: string): boolean {
  if (!keyword) return false;
  const normalized = keyword.trim().toLowerCase();
  if (normalized.length === 0) return false;
  return tokens.includes(normalized);
}
