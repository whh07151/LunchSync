import { Injectable } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: CORE-07 그룹 추천 점수화 엔진 + CORE-08 중복 회피
//
// 추천 로직:
//   1. 세션 멤버 전원의 프로필(budget, speed, allergies, dislikes) 수집
//   2. 식당 목록에서 그룹 조건 기반 점수 계산
//   3. 최근 7일 식사 이력과 겹치는 식당 감점
//   4. 점수 높은 순으로 정렬하여 반환
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
  lat: number;
  lng: number;
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
  constructor(private readonly supabase: SupabaseService) {}

  // ── 그룹 추천 메인 로직 ───────────────────────────────
  async getRecommendations(sessionId: string): Promise<RecommendationResult[]> {
    // 1. 세션 멤버 목록 조회
    const { data: members } = await this.supabase.client
      .from('session_members')
      .select('user_id')
      .eq('session_id', sessionId);

    const memberIds = members?.map((m) => m.user_id) ?? [];
    if (memberIds.length === 0) return [];

    // 2. 멤버 프로필 수집
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

    // 3. 전체 식당 목록 조회
    const { data: restaurants } = await this.supabase.client
      .from('restaurants')
      .select('id, name, category, price_range, address, lat, lng');

    if (!restaurants || restaurants.length === 0) return [];

    // 4. 최근 7일 식사 이력 조회 (CORE-08 중복 회피)
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

    // 5. 각 식당별 점수 계산
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

    // 6. 점수 높은 순 정렬
    scored.sort((a, b) => b.score - a.score);

    return scored.slice(0, 10); // 상위 10개
  }
}
