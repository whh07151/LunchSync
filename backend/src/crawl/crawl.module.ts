import { Module } from '@nestjs/common';
import { CrawlService } from './crawl.service';
import { CrawlController } from './crawl.controller';

// ══════════════════════════════════════════════════════════
// 파일 역할: Kakao Local 일회성 주변 장소 조회
// ══════════════════════════════════════════════════════════

@Module({
  controllers: [CrawlController],
  providers: [CrawlService],
})
export class CrawlModule {}
