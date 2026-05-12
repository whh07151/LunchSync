import { Controller, Get, Param, Query, UseGuards } from '@nestjs/common';
import { IsOptional, IsString, IsNumberString } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RestaurantsService } from './restaurants.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 식당/메뉴 관련 HTTP 엔드포인트
//
// 엔드포인트:
//   GET /api/restaurants            — 식당 목록 (필터)
//   GET /api/restaurants/:id        — 식당 상세
//   GET /api/restaurants/:id/menus  — 식당 메뉴 목록
// ══════════════════════════════════════════════════════════

class GetRestaurantsQueryDto {
  @IsOptional() @IsString() category?: string;
  @IsOptional() @IsNumberString() maxPrice?: string;
  @IsOptional() @IsNumberString() limit?: string;
  @IsOptional() @IsNumberString() offset?: string;
  // 위치 기반 필터링 (2026-05-12 추가) — 길동 GPS 에서 강남 식당 노출 차단
  // 위/경도 와 반경(m) 모두 있으면 Haversine 으로 반경 내 식당만 반환.
  @IsOptional() @IsNumberString() lat?: string;
  @IsOptional() @IsNumberString() lng?: string;
  @IsOptional() @IsNumberString() radius?: string; // m 단위, 기본 1000m
}

@Controller('restaurants')
@UseGuards(JwtAuthGuard)
export class RestaurantsController {
  constructor(private readonly restaurantsService: RestaurantsService) {}

  // ── GET /api/restaurants ──────────────────────────────
  @Get()
  async getRestaurants(@Query() query: GetRestaurantsQueryDto) {
    const result = await this.restaurantsService.getRestaurants({
      category: query.category,
      maxPrice: query.maxPrice ? Number(query.maxPrice) : undefined,
      limit: query.limit ? Number(query.limit) : undefined,
      offset: query.offset ? Number(query.offset) : undefined,
      lat: query.lat ? Number(query.lat) : undefined,
      lng: query.lng ? Number(query.lng) : undefined,
      radius: query.radius ? Number(query.radius) : undefined,
    });
    return { success: true, data: result };
  }

  // ── GET /api/restaurants/:id ──────────────────────────
  @Get(':id')
  async getRestaurantById(@Param('id') id: string) {
    const result = await this.restaurantsService.getRestaurantById(id);
    return { success: true, data: result };
  }

  // ── GET /api/restaurants/:id/menus ────────────────────
  @Get(':id/menus')
  async getMenus(@Param('id') id: string) {
    const result = await this.restaurantsService.getMenusByRestaurant(id);
    return { success: true, data: result };
  }
}
