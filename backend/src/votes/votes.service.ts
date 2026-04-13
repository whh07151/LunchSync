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
