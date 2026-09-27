// ══════════════════════════════════════════════════════════
// 파일 역할: 토너먼트 결과 적재 및 트렌딩 집계 서비스
//
// 흐름:
//   1) createResult — Flutter 우승 화면에서 POST /api/tournaments 호출 시
//      tournament_results 테이블에 1행 INSERT. 실패해도 UX 막지 않도록
//      컨트롤러는 백그라운드 호출이지만, 본 서비스는 명시적 예외 throw.
//
//   2) getTrending — 최근 N일 동안의 우승 데이터를 가져와 식당별 카운트.
//      Supabase 는 GROUP BY 집계를 PostgREST 단에서 지원하지 않아
//      recommendations.service 와 동일하게 JS 측에서 집계.
//      이후 restaurants 테이블에 한 번에 in() 으로 조인해 카드 정보 채움.
//
// 보안:
//   - JwtAuthGuard 는 controller 단계에서 적용 → 본 서비스는 userId 신뢰.
//   - getTrending 은 식당 카드 정보만 노출 → 개인정보 누출 위험 없음.
//
// 성능:
//   - tournament_results 는 한 주에 수십~수백 건 정도로 예상 (시연 규모).
//     N일 row 전체를 메모리에 올려도 부담 없음. 인덱스 idx_..._created
//     로 created_at 필터가 빠르게 동작.
//   - restaurants 조회는 distinct restaurant_id (최대 limit*3 정도)만 in() 으로 1쿼리.
// ══════════════════════════════════════════════════════════

import {
  Injectable,
  InternalServerErrorException,
  Logger,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ── 입력 타입 ─────────────────────────────────────────────
// controller 에서 DTO 변환 후 본 서비스로 전달되는 정규화된 payload.
export interface CreateTournamentResultInput {
  userId: string;
  mode: 'restaurant' | 'menu';
  winnerRestaurantId: string | null;
  winnerMenuId: string | null;
  candidateCount: number | null;
  durationMs: number | null;
}

// ── 출력 타입: 트렌딩 카드 ─────────────────────────────────
// Flutter 홈 화면 _buildTrendingList 가 그대로 받아 카드로 그릴 수 있는 형태.
// imageUrl 은 null 가능 — FoodImage 위젯이 카테고리 이모지로 폴백.
export interface TrendingRestaurantDto {
  restaurantId: string;
  name: string;
  category: string | null;
  imageUrl: string | null;
  winCount: number;
}

// ── 옵션 타입 ─────────────────────────────────────────────
export interface GetTrendingOptions {
  /** 최대 식당 개수 (홈 가로 스크롤 권장 5개) */
  limit: number;
  /** 최근 며칠 (기본 7일) */
  days: number;
}

@Injectable()
export class TournamentsService {
  private readonly logger = new Logger(TournamentsService.name);

  constructor(private readonly supabase: SupabaseService) {}

  // ── 1) 우승 결과 INSERT ────────────────────────────────
  // Supabase 의 insert().select().single() 패턴으로 새 id 를 즉시 반환.
  // 실패는 5xx 로 throw 하여 호출 측(앱)에서 디버깅 가능하게 함.
  async createResult(
    input: CreateTournamentResultInput,
  ): Promise<{ id: string }> {
    // 컬럼명은 SQL 컨벤션(snake_case) 로 변환.
    // 트렌딩 집계에 winner_restaurant_id 가 핵심 — 메뉴 모드도 컨트롤러에서
    // 가능한 한 채워 보내는 것이 좋지만, 누락되면 그대로 NULL 저장(분석 노이즈).
    const row = {
      user_id: input.userId,
      mode: input.mode,
      winner_restaurant_id: input.winnerRestaurantId,
      winner_menu_id: input.winnerMenuId,
      candidate_count: input.candidateCount,
      duration_ms: input.durationMs,
      // created_at 은 DB DEFAULT NOW() 가 채움.
    };

    const { data, error } = await this.supabase.client
      .from('tournament_results')
      .insert(row)
      .select('id')
      .single();

    if (error || !data) {
      this.logger.error('TOURNAMENT_RESULT_CREATE_PERSIST_FAILED');
      throw new InternalServerErrorException(
        '토너먼트 결과를 저장하지 못했어요.',
      );
    }

    return { id: data.id as string };
  }

  // ── 2) 트렌딩 식당 조회 (최근 N일) ─────────────────────
  // 단계:
  //   ① tournament_results 에서 created_at >= now()-N days &
  //     winner_restaurant_id NOT NULL 행만 select.
  //   ② JS 측 Map<restaurantId, count> 으로 집계.
  //   ③ count desc 정렬 + 상위 limit 개 추출.
  //   ④ restaurants 테이블에서 카드 정보(name/category/image_url) 일괄 조회.
  //   ⑤ Map 으로 lookup 하여 winCount 와 함께 최종 응답 구성.
  //
  // 빈 결과:
  //   - 우승 데이터 0개 → [] 반환.
  //   - 식당이 모두 삭제 → 매칭 0개라도 [] 반환.
  async getTrending(
    options: GetTrendingOptions,
  ): Promise<TrendingRestaurantDto[]> {
    const since = new Date();
    since.setDate(since.getDate() - options.days);

    // ── ① 최근 N일 우승 행 가져오기 ────────────────────
    // winner_restaurant_id 가 NULL 인 행(메뉴 모드 + 식당 누락)은 제외.
    const { data: rows, error } = await this.supabase.client
      .from('tournament_results')
      .select('winner_restaurant_id')
      .gte('created_at', since.toISOString())
      .not('winner_restaurant_id', 'is', null);

    if (error) {
      this.logger.error('TOURNAMENT_RESULT_LIST_PERSIST_FAILED');
      throw new InternalServerErrorException(
        '트렌딩 데이터를 불러오지 못했어요.',
      );
    }

    if (!rows || rows.length === 0) {
      this.logger.log(
        `[트렌딩] days=${options.days} 우승 데이터 0건 → 빈 배열 반환`,
      );
      return [];
    }

    // ── ② JS 측 집계 ───────────────────────────────────
    const countByRestaurant = new Map<string, number>();
    for (const r of rows) {
      const rid = (r as { winner_restaurant_id: string | null })
        .winner_restaurant_id;
      if (!rid) continue;
      countByRestaurant.set(rid, (countByRestaurant.get(rid) ?? 0) + 1);
    }

    // ── ③ count desc 정렬 + 상위 limit 개 ───────────────
    const sorted = Array.from(countByRestaurant.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, options.limit);

    if (sorted.length === 0) return [];

    // ── ④ restaurants 카드 정보 일괄 조회 ───────────────
    const ids = sorted.map(([rid]) => rid);
    const { data: restaurants, error: rError } = await this.supabase.client
      .from('restaurants')
      .select('id, name, category, image_url')
      .in('id', ids);

    if (rError) {
      this.logger.error('TOURNAMENT_RESTAURANT_LOOKUP_FAILED');
      throw new InternalServerErrorException(
        '트렌딩 식당 정보를 불러오지 못했어요.',
      );
    }

    // ── ⑤ 정렬 순서 유지하며 응답 구성 ────────────────
    // restaurants 결과를 Map 으로 만들고 sorted 순서대로 매핑 → 순위 보존.
    type RestaurantRow = {
      id: string;
      name: string;
      category: string | null;
      image_url: string | null;
    };
    const restaurantMap = new Map<string, RestaurantRow>();
    for (const r of (restaurants ?? []) as RestaurantRow[]) {
      restaurantMap.set(r.id, r);
    }

    const result: TrendingRestaurantDto[] = [];
    for (const [rid, count] of sorted) {
      const r = restaurantMap.get(rid);
      if (!r) {
        // 식당이 삭제된 경우 — 순위에서 제외 (메뉴에 노출되면 식당 상세 진입 시 404).
        continue;
      }
      result.push({
        restaurantId: r.id,
        name: r.name,
        category: r.category,
        imageUrl: r.image_url,
        winCount: count,
      });
    }

    this.logger.log(
      `[트렌딩] days=${options.days} limit=${options.limit} 결과=${result.length}건`,
    );
    return result;
  }
}
