import { Controller, Post, Body, UseGuards } from '@nestjs/common';
import { IsNumber, IsOptional } from 'class-validator';
import { CrawlService } from './crawl.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

// ══════════════════════════════════════════════════════════
// 파일 역할: 크롤링 API 컨트롤러
//
// 엔드포인트:
//   POST /api/crawl/restaurants — GPS 좌표 + 반경으로 식당 크롤링
//
// 인증: JWT 필수 (아무나 크롤링 트리거하면 안 되므로)
// ══════════════════════════════════════════════════════════

class CrawlRequestDto {
  @IsNumber()
  lat: number;

  @IsNumber()
  lng: number;

  @IsOptional()
  @IsNumber()
  radius?: number; // 미터 단위, 기본 1000m
}

@Controller('crawl')
@UseGuards(JwtAuthGuard)
export class CrawlController {
  constructor(private readonly crawlService: CrawlService) {}

  @Post('restaurants')
  async crawlRestaurants(@Body() dto: CrawlRequestDto) {
    const radius = dto.radius || 1000;
    const result = await this.crawlService.crawlAndSeed(
      dto.lat,
      dto.lng,
      radius,
    );

    return {
      success: true,
      data: result,
    };
  }
}
