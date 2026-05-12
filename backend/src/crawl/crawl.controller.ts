import { Controller, Post, Body, UseGuards } from '@nestjs/common';
import { IsLatitude, IsLongitude, IsNumber, IsOptional, Max, Min } from 'class-validator';
import { CrawlService } from './crawl.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

// ══════════════════════════════════════════════════════════
// 파일 역할: 크롤링 API 컨트롤러
//
// 엔드포인트:
//   POST /api/crawl/restaurants — GPS 좌표 + 반경으로 식당 크롤링
//
// 인증: JWT 필수 (아무나 크롤링 트리거하면 안 되므로)
//
// 입력 검증 (2026-05-12 박검토A):
//   @IsLatitude/@IsLongitude — 위경도 범위 강제 (Infinity / NaN 차단)
//   radius Min/Max — 음수·과도한 반경 차단 (Gemini 폴백 무한 INSERT 방어)
// ══════════════════════════════════════════════════════════

class CrawlRequestDto {
  // 위도 (-90 ~ 90) — Infinity/NaN/문자열 차단
  @IsLatitude({ message: 'lat 은 -90 ~ 90 범위의 유효한 위도여야 합니다.' })
  lat: number;

  // 경도 (-180 ~ 180)
  @IsLongitude({ message: 'lng 은 -180 ~ 180 범위의 유효한 경도여야 합니다.' })
  lng: number;

  // 반경 (m). 50m ~ 5km. 미설정 시 controller 에서 1000m 기본값.
  @IsOptional()
  @IsNumber()
  @Min(50, { message: 'radius 는 최소 50m 이상이어야 합니다.' })
  @Max(5000, { message: 'radius 는 최대 5000m(5km) 까지 허용됩니다.' })
  radius?: number;
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
