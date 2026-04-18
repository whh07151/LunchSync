import {
  Injectable,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 투표 비즈니스 로직
//
// 흐름: 추천 결과 확인 → 투표 → 확정(CU-15)
// UNIQUE(user_id, session_id): 1인 1표
// ══════════════════════════════════════════════════════════

export interface CastVoteDto {
  restaurantId: string;
}

@Injectable()
export class VotesService {
  constructor(private readonly supabase: SupabaseService) {}

  // ── POST /votes ───────────────────────────────────────
  async castVote(userId: string, sessionId: string, dto: CastVoteDto) {
    const { data, error } = await this.supabase.client
      .from('votes')
      .insert({
        user_id: userId,
        session_id: sessionId,
        restaurant_id: dto.restaurantId,
      })
      .select('id, user_id, session_id, restaurant_id, created_at')
      .single();

    if (error) {
      if (error.code === '23505') {
        throw new ConflictException('이미 투표했습니다.');
      }
      throw new Error(`투표 실패: ${error.message}`);
    }

    return {
      id: data.id,
      userId: data.user_id,
      sessionId: data.session_id,
      restaurantId: data.restaurant_id,
      createdAt: data.created_at,
    };
  }

  // ── GET /sessions/:id/votes ───────────────────────────
  async getVotesBySession(sessionId: string) {
    const { data, error } = await this.supabase.client
      .from('votes')
      .select('id, user_id, restaurant_id, created_at, restaurants(name)')
      .eq('session_id', sessionId);

    if (error) {
      throw new Error(`투표 조회 실패: ${error.message}`);
    }

    return (data ?? []).map((v: any) => ({
      id: v.id,
      userId: v.user_id,
      restaurantId: v.restaurant_id,
      restaurantName: v.restaurants?.name,
      createdAt: v.created_at,
    }));
  }

  // ── 후보 관리 ──────────────────────────────────────────

  // 세션 후보 식당 목록 조회
  async getCandidates(sessionId: string) {
    const { data, error } = await this.supabase.client
      .from('session_candidates')
      .select('id, session_id, restaurant_id, added_by, source, created_at, restaurants(name, category, price_range, address)')
      .eq('session_id', sessionId)
      .order('created_at', { ascending: true });

    if (error) {
      throw new Error(`후보 조회 실패: ${error.message}`);
    }

    return (data ?? []).map((c: any) => ({
      id: c.id,
      sessionId: c.session_id,
      restaurantId: c.restaurant_id,
      addedBy: c.added_by,
      source: c.source,
      name: c.restaurants?.name,
      category: c.restaurants?.category,
      priceRange: c.restaurants?.price_range,
      address: c.restaurants?.address,
      createdAt: c.created_at,
    }));
  }

  // 후보 식당 1개 추가
  async addCandidate(userId: string, sessionId: string, restaurantId: string, source: string) {
    const { data, error } = await this.supabase.client
      .from('session_candidates')
      .insert({
        session_id: sessionId,
        restaurant_id: restaurantId,
        added_by: userId,
        source,
      })
      .select('id, session_id, restaurant_id, added_by, source, created_at')
      .single();

    if (error) {
      if (error.code === '23505') {
        throw new ConflictException('이미 후보에 추가된 식당입니다.');
      }
      throw new Error(`후보 추가 실패: ${error.message}`);
    }

    return {
      id: data.id,
      sessionId: data.session_id,
      restaurantId: data.restaurant_id,
      addedBy: data.added_by,
      source: data.source,
      createdAt: data.created_at,
    };
  }

  // 후보 식당 일괄 추가 (중복은 무시)
  async addCandidatesBatch(
    userId: string,
    sessionId: string,
    candidates: { restaurantId: string; source?: string }[],
  ) {
    const rows = candidates.map((c) => ({
      session_id: sessionId,
      restaurant_id: c.restaurantId,
      added_by: userId,
      source: c.source ?? 'AI',
    }));

    const { data, error } = await this.supabase.client
      .from('session_candidates')
      .upsert(rows, { onConflict: 'session_id,restaurant_id', ignoreDuplicates: true })
      .select('id, restaurant_id, source');

    if (error) {
      throw new Error(`후보 일괄 추가 실패: ${error.message}`);
    }

    return { added: data?.length ?? 0 };
  }

  // 후보 식당 삭제
  async removeCandidate(sessionId: string, restaurantId: string) {
    const { error } = await this.supabase.client
      .from('session_candidates')
      .delete()
      .eq('session_id', sessionId)
      .eq('restaurant_id', restaurantId);

    if (error) {
      throw new Error(`후보 삭제 실패: ${error.message}`);
    }
  }

  // ── CU-15: 투표 결과 집계 + 최다 득표 식당 확정 ────────
  async tallyAndDecide(sessionId: string) {
    const votes = await this.getVotesBySession(sessionId);
    if (votes.length === 0) {
      throw new NotFoundException('투표가 없습니다.');
    }

    // 식당별 득표수 집계
    const tally = new Map<string, { count: number; name: string }>();
    for (const v of votes) {
      const existing = tally.get(v.restaurantId);
      if (existing) {
        existing.count++;
      } else {
        tally.set(v.restaurantId, { count: 1, name: v.restaurantName ?? '' });
      }
    }

    // 최다 득표 식당
    let winnerId = '';
    let winnerName = '';
    let maxCount = 0;
    for (const [id, { count, name }] of tally) {
      if (count > maxCount) {
        maxCount = count;
        winnerId = id;
        winnerName = name;
      }
    }

    // sessions 테이블에 winner 업데이트 + 상태 ORDERED로 변경
    await this.supabase.client
      .from('sessions')
      .update({
        winner_restaurant_id: winnerId,
        status: 'ORDERED',
      })
      .eq('id', sessionId);

    return {
      winnerId,
      winnerName,
      voteCount: maxCount,
      totalVotes: votes.length,
      tally: Array.from(tally.entries()).map(([id, { count, name }]) => ({
        restaurantId: id,
        restaurantName: name,
        count,
      })),
    };
  }
}
