import { Module } from '@nestjs/common';
import { CrawlService } from './crawl.service';
import { CrawlController } from './crawl.controller';
import { GeminiModule } from '../gemini/gemini.module';

// ══════════════════════════════════════════════════════════
// 파일 역할: 크롤링 모듈 (카카오 + 네이버 + Gemini AI 폴백)
//
// 의존:
//   - GeminiModule: 네이버 메뉴 실패 시 AI 메뉴 생성 폴백
// ══════════════════════════════════════════════════════════

@Module({
  imports: [GeminiModule],
  controllers: [CrawlController],
  providers: [CrawlService],
})
export class CrawlModule {}
