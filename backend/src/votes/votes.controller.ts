import { Body, Controller, Delete, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import { IsString, IsNotEmpty, IsArray, IsOptional } from 'class-validator';
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

class AddCandidateDto {
  @IsString()
  @IsNotEmpty()
  restaurantId: string;

  @IsString()
  @IsOptional()
  source?: string; // 'AI' | 'MANUAL' (기본값 'MANUAL')
}

class AddCandidatesBatchDto {
  @IsArray()
  candidates: { restaurantId: string; source?: string }[];
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

  // ── 투표 후보 관리 ─────────────────────────────────────

  // 후보 식당 목록 조회
  @Get(':id/candidates')
  async getCandidates(@Param('id') sessionId: string) {
    const result = await this.votesService.getCandidates(sessionId);
    return { success: true, data: result };
  }

  // 후보 식당 1개 추가
  @Post(':id/candidates')
  async addCandidate(
    @Req() req: { user: { userId: string } },
    @Param('id') sessionId: string,
    @Body() dto: AddCandidateDto,
  ) {
    const result = await this.votesService.addCandidate(
      req.user.userId,
      sessionId,
      dto.restaurantId,
      dto.source ?? 'MANUAL',
    );
    return { success: true, data: result };
  }

  // 후보 식당 일괄 추가 (AI 추천 결과를 한번에 등록)
  @Post(':id/candidates/batch')
  async addCandidatesBatch(
    @Req() req: { user: { userId: string } },
    @Param('id') sessionId: string,
    @Body() dto: AddCandidatesBatchDto,
  ) {
    const result = await this.votesService.addCandidatesBatch(
      req.user.userId,
      sessionId,
      dto.candidates,
    );
    return { success: true, data: result };
  }

  // 후보 식당 삭제
  @Delete(':id/candidates/:restaurantId')
  async removeCandidate(
    @Param('id') sessionId: string,
    @Param('restaurantId') restaurantId: string,
  ) {
    await this.votesService.removeCandidate(sessionId, restaurantId);
    return { success: true };
  }
}
