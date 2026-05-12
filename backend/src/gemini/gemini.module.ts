import { Module } from '@nestjs/common';
import { GeminiService } from './gemini.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: Gemini AI 모듈
//
// 노출: GeminiService — 식당명+카테고리 기반 메뉴 자동 생성
// 의존: ConfigService (전역, ConfigModule.isGlobal)
//
// 사용처:
//   - CrawlModule (네이버 메뉴 실패 시 폴백)
//   - 추후 RecommendationsModule, OrdersModule 등에서도 재사용 가능
// ══════════════════════════════════════════════════════════

@Module({
  providers: [GeminiService],
  exports: [GeminiService],
})
export class GeminiModule {}
