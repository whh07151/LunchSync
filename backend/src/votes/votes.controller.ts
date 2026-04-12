import { Body, Controller, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import { IsString, IsNotEmpty } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
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

@Controller('sessions')
@UseGuards(JwtAuthGuard)
export class VotesController {
  constructor(private readonly votesService: VotesService) {}

  @Post(':id/votes')
  async castVote(
    @Req() req: { user: { userId: string } },
    @Param('id') sessionId: string,
    @Body() dto: CastVoteDto,
  ) {
    const result = await this.votesService.castVote(
      req.user.userId,
      sessionId,
      dto,
    );
    return { success: true, data: result };
  }

  @Get(':id/votes')
  async getVotes(@Param('id') sessionId: string) {
    const result = await this.votesService.getVotesBySession(sessionId);
    return { success: true, data: result };
  }

  // CU-15: 투표 결과 집계 → 식당 확정
  @Post(':id/decide')
  async decide(@Param('id') sessionId: string) {
    const result = await this.votesService.tallyAndDecide(sessionId);
    return { success: true, data: result };
  }
}
