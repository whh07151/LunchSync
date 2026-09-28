import { Body, Controller, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import { IsString, IsNotEmpty, IsOptional } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SessionAccessService } from '../auth/session-access.service';
import { VotesService } from './votes.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 투표 관련 HTTP 엔드포인트
//
// 엔드포인트:
//   POST /api/sessions/:id/votes     — 투표하기
//   GET  /api/sessions/:id/votes     — 투표 현황 조회
//   POST /api/sessions/:id/decide    — CU-15 결과 확정
// ══════════════════════════════════════════════════════════

class CastVoteDto {
  @IsString()
  @IsNotEmpty()
  restaurantId: string;
}

// 2026-05-15 회귀 fix — restaurantId 있으면 즉석 결정(룰렛/사다리),
// 없으면 기존 투표 집계(tallyAndDecide). 하위호환 유지.
class DecideDto {
  @IsOptional()
  @IsString()
  restaurantId?: string;
}

@Controller('sessions')
@UseGuards(JwtAuthGuard)
export class VotesController {
  constructor(
    private readonly votesService: VotesService,
    private readonly sessionAccess: SessionAccessService,
  ) {}

  @Post(':id/votes')
  async castVote(
    @Req() req: { user: { userId: string } },
    @Param('id') sessionId: string,
    @Body() dto: CastVoteDto,
  ) {
    await this.sessionAccess.assertMember(sessionId, req.user.userId);
    const result = await this.votesService.castVote(
      req.user.userId,
      sessionId,
      dto,
    );
    return { success: true, data: result };
  }

  @Get(':id/votes')
  async getVotes(
    @Req() req: { user: { userId: string } },
    @Param('id') sessionId: string,
  ) {
    await this.sessionAccess.assertMember(sessionId, req.user.userId);
    const result = await this.votesService.getVotesBySession(sessionId);
    return { success: true, data: result };
  }

  // CU-15: 결과 확정 (호스트만)
  //   - body.restaurantId 있음 → 즉석 결정 (룰렛/사다리, WAITING 도 허용)
  //   - body 없음 → 기존 투표 집계 (VOTING + 최소 1표)
  @Post(':id/decide')
  async decide(
    @Req() req: { user: { userId: string } },
    @Param('id') sessionId: string,
    @Body() dto: DecideDto,
  ) {
    const result = dto?.restaurantId
      ? await this.votesService.decideManually(
          sessionId,
          req.user.userId,
          dto.restaurantId,
        )
      : await this.votesService.tallyAndDecide(sessionId, req.user.userId);
    return { success: true, data: result };
  }
}
