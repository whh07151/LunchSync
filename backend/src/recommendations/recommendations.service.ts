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

    // 6. 각 식당별 점수 계산
    const scored = restaurants.map((r: Restaurant) => {
      let score = 100;
      const reasons: string[] = [];

      // ── 예산 적합도 ────────────────────────────────
      const budgets = memberProfiles
        .map((p) => p.budget)
        .filter((b): b is number => b !== null);

      if (budgets.length > 0) {
        const minBudget = Math.min(...budgets);
        if (r.price_range <= minBudget) {
          score += 20;
          reasons.push('전원 예산 범위 내');
        } else {
          // 예산 초과 정도에 따라 감점
          const overRatio = (r.price_range - minBudget) / minBudget;
          score -= Math.round(overRatio * 40);
          reasons.push('일부 멤버 예산 초과');
        }
      }

      // ── 알레르기 충돌 검사 ─────────────────────────
      const allAllergies = memberProfiles.flatMap((p) => p.allergies);
      const categoryLower = (r.category ?? '').toLowerCase();
      const allergyConflict = allAllergies.some((a) =>
        categoryLower.includes(a.toLowerCase()),
      );
      if (allergyConflict) {
        score -= 50;
        reasons.push('알레르기 주의');
      }

      // ── 비선호 음식 검사 ──────────────────────────
      const allDislikes = memberProfiles.flatMap((p) => p.dislikes);
      const dislikeConflict = allDislikes.some((d) =>
        categoryLower.includes(d.toLowerCase()),
      );
      if (dislikeConflict) {
        score -= 25;
        reasons.push('비선호 음식 포함');
      }

      // ── CORE-08: 최근 식사 중복 회피 ───────────────
      if (recentRestaurantIds.has(r.id)) {
        score -= 30;
        reasons.push('최근 7일 내 방문');
      }

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

    // 7. 점수 높은 순 정렬
    scored.sort((a, b) => b.score - a.score);

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
