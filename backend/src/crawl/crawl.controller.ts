import { BadRequestException, Controller, HttpCode, Post, Body, UseGuards, Logger } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
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
  // 2026-05-14 사장님 버그 신고 ('식당 안 찾아짐'/500 응답) 대응으로 도입.
  // service 내부에서 잡지 못한 예외가 끝까지 올라와도 500 대신 200 + 빈 결과로
  // 응답하기 위해 controller 에 외곽 안전망을 두고 그 안에서 로그를 남긴다.
  private readonly logger = new Logger(CrawlController.name);

  constructor(private readonly crawlService: CrawlService) {}

  @Post('nearby')
  @HttpCode(200)
  @Throttle({ default: { limit: 6, ttl: 60_000 } })
  async discoverNearby(@Body() query: CrawlRequestDto) {
    const lat = query.lat;
    const lng = query.lng;
    const radius = query.radius ?? 1000;
    if (!Number.isFinite(lat) || Math.abs(lat) > 90 ||
        !Number.isFinite(lng) || Math.abs(lng) > 180 ||
        !Number.isInteger(radius) || radius < 50 || radius > 5000) {
      throw new BadRequestException('유효한 위치와 50~5000m 반경을 입력해 주세요.');
    }
    const data = await this.crawlService.discoverNearby(lat, lng, radius);
    return { success: true, data };
  }

  // ── POST /api/crawl/restaurants ─────────────────────────
  // 클라이언트(session_create_screen.dart)는 이 호출을 fire-and-forget 으로
  // 사용하므로 500 응답이 사용자 화면을 직접 막진 않지만, 그래도 200 으로
  // 통일해두면:
  //   - 클라이언트 로그가 '응답 실패: 500' 으로 도배되지 않음 → 진단 용이
  //   - 향후 추천 동기 흐름이 이 API 결과를 카운트해도 0으로 안전 폴백
  @Post('restaurants')
  @Throttle({ default: { limit: 6, ttl: 60_000 } })
  async crawlRestaurants(@Body() dto: CrawlRequestDto) {
    const radius = dto.radius || 1000;
    try {
      // 예전 클라이언트 호환용. 장소를 조회만 하며 DB·메뉴는 수정하지 않는다.
      const nearby = await this.crawlService.discoverNearby(
        dto.lat,
        dto.lng,
        radius,
      );

      return {
        success: true,
        data: {
          totalSearched: nearby.length,
          totalSaved: 0,
          totalMenus: 0,
          restaurants: [],
        },
      };
    } catch (_) {
      // 예: Supabase 일시적 장애, 카카오/네이버/Gemini 호출 전부 실패 등.
      // 사용자에겐 친근하게, 운영 로그엔 원인 추적 정보 남김.
      this.logger.error('CRAWL_REQUEST_FAILED');
      return {
        success: false,
        message:
          '주변 식당을 가져오지 못했어요. 잠시 후 다시 시도하거나 기존 추천을 확인해주세요.',
        data: {
          totalSearched: 0,
          totalSaved: 0,
          totalMenus: 0,
          restaurants: [],
        },
      };
    }
  }
}
