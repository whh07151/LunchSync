import {
  Injectable,
  ConflictException,
  ForbiddenException,
  NotFoundException,
  BadRequestException,
  InternalServerErrorException,
  Logger,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 투표 비즈니스 로직
//
// 보안 패치 (2026-05-12):
//   - VOTING 상태에서만 투표 가능 (다른 상태에서 castVote 거부)
//   - tallyAndDecide 는 호스트만 가능
//   - 에러 메시지 노출 차단
//
// 흐름: 추천 결과 확인 → 투표 → 확정(CU-15)
// UNIQUE(user_id, session_id): 1인 1표
// ══════════════════════════════════════════════════════════

export interface CastVoteDto {
  restaurantId: string;
}

@Injectable()
export class VotesService {
  private readonly logger = new Logger(VotesService.name);

  constructor(private readonly supabase: SupabaseService) {}

  // ── POST /sessions/:id/votes ──────────────────────────
  // 세션이 VOTING 상태일 때만 투표 가능
  async castVote(userId: string, sessionId: string, dto: CastVoteDto) {
    // 1단계: 세션 상태 검증 (VOTING 만 허용)
    const { data: session, error: sessionError } = await this.supabase.client
      .from('sessions')
      .select('id, status')
      .eq('id', sessionId)
      .single();

    if (sessionError || !session) {
      throw new NotFoundException('세션을 찾을 수 없어요.');
    }
    if (session.status !== 'VOTING') {
      throw new BadRequestException(
        `${session.status} 상태에서는 투표할 수 없어요. 투표는 VOTING 상태에서만 가능해요.`,
      );
    }

    // 2단계: 식당 존재 확인 (잘못된 restaurantId 거부)
    const { data: restaurant } = await this.supabase.client
      .from('restaurants')
      .select('id')
      .eq('id', dto.restaurantId)
      .single();
    if (!restaurant) {
      throw new NotFoundException('유효하지 않은 식당이에요.');
    }

    // 3단계: 투표 INSERT
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
        throw new ConflictException('이미 투표했어요.');
      }
      this.logger.error(
        `투표 INSERT DB 오류 session=${sessionId} user=${userId}: ${error.message}`,
      );
      throw new InternalServerErrorException('투표를 등록하지 못했어요.');
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
      this.logger.error(`투표 조회 DB 오류 session=${sessionId}: ${error.message}`);
      throw new InternalServerErrorException('투표 현황을 불러오지 못했어요.');
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
  // 보안 패치: 호스트만 가능 + VOTING 상태에서만
  async tallyAndDecide(sessionId: string, requesterId: string) {
    // 호스트 + 상태 검증
    const { data: session, error: sessionError } = await this.supabase.client
      .from('sessions')
      .select('created_by, status')
      .eq('id', sessionId)
      .single();
    if (sessionError || !session) {
      throw new NotFoundException('세션을 찾을 수 없어요.');
    }
    if (session.created_by !== requesterId) {
      throw new ForbiddenException('세션 호스트만 결과를 확정할 수 있어요.');
    }
    if (session.status !== 'VOTING') {
      throw new BadRequestException(
        'VOTING 상태의 세션만 결과 확정할 수 있어요.',
      );
    }

    const votes = await this.getVotesBySession(sessionId);
    if (votes.length === 0) {
      throw new NotFoundException('아직 투표가 없어요.');
    }

    // 식당별 득표수 집계
    const tally = new Map<string, { count: number; name: string }>();
    for (const v of votes) {
      const existing = tally.get(v.restaurantId);
      if (existing) {
        existing.count++;
      } else {
        tally.set(v.restaurantId, {
          count: 1,
          name: v.restaurantName ?? '',
        });
      }
    }

    // 최다 득표 식당 (동률 시 먼저 발견된 식당)
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
    const { error: updateError } = await this.supabase.client
      .from('sessions')
      .update({
        winner_restaurant_id: winnerId,
        status: 'ORDERED',
      })
      .eq('id', sessionId);
    if (updateError) {
      this.logger.error(
        `세션 winner 업데이트 DB 오류 session=${sessionId}: ${updateError.message}`,
      );
      throw new InternalServerErrorException('결과를 확정하지 못했어요.');
    }

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
