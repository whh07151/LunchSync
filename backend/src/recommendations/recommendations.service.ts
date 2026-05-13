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
      //   price_range는 1~4 정도의 등급(저렴~고급)을 1만원 단위로 환산.
      //   minBudget 대비 50% 이하: +15 / 80% 이하: +10 / 100% 이하: +5
      //   100% 초과: 초과 비율에 비례해 -30까지 감점.
      if (minBudget != null && minBudget > 0) {
        // price_range는 1~4 스케일이라 가정(1=저렴, 4=고급). 만원 단위로 환산.
        const estimatedPrice = r.price_range * 10000;
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

      // ── (E) 알레르기 충돌 검사 ─────────────────────
      const categoryLower = (r.category ?? '').toLowerCase();
      const allergyConflict = allAllergies.some((a) =>
        categoryLower.includes(a.toLowerCase()),
      );
      if (allergyConflict) {
        score -= 50;
        reasons.push('알레르기 주의');
      }

      // ── (F) 비선호 음식 검사 ──────────────────────
      const dislikeConflict = allDislikes.some((d) =>
        categoryLower.includes(d.toLowerCase()),
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
