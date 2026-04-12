import { Controller, Get, Param, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RecommendationsService } from './recommendations.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: CORE-07/08 추천 엔진 HTTP 엔드포인트
//
// 엔드포인트:
//   GET /api/sessions/:id/recommendations — 세션 기반 그룹 추천
// ══════════════════════════════════════════════════════════

@Controller('sessions')
@UseGuards(JwtAuthGuard)
export class RecommendationsController {
  constructor(
    private readonly recommendationsService: RecommendationsService,
  ) {}

  @Get(':id/recommendations')
  async getRecommendations(@Param('id') sessionId: string) {
    const result =
      await this.recommendationsService.getRecommendations(sessionId);
    return { success: true, data: result };
  }
}
