import { Controller, Get, Param, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RecommendationsService } from './recommendations.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: CORE-07/08 추천 엔진 HTTP 엔드포인트
//
// 엔드포인트:
//   GET /api/sessions/:id/recommendations — 세션 기반 그룹 추천
//
// 응답 포맷 (2026-05-31 CU-21 metadata 도입):
//   {
//     success: true,
//     data: RecommendationResult[],          // 기존 호환 (프론트 코드 무수정 작동)
//     metadata: { recentPenalty: {id:-N} }   // CU-21 페널티 디버그/칩 표시 보조
//   }
// ══════════════════════════════════════════════════════════

@Controller('sessions')
@UseGuards(JwtAuthGuard)
export class RecommendationsController {
  constructor(
    private readonly recommendationsService: RecommendationsService,
  ) {}

  @Get(':id/recommendations')
  async getRecommendations(@Param('id') sessionId: string) {
    // 서비스는 봉투 형태(items + metadata)를 돌려준다.
    // 컨트롤러에서 기존 응답 키마 호환을 위해 data + metadata 두 레벨로 펼친다.
    const result =
      await this.recommendationsService.getRecommendations(sessionId);
    return {
      success: true,
      data: result.items,
      metadata: result.metadata,
    };
  }
}
