import {
  Controller,
  ForbiddenException,
  Get,
  Param,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { IsOptional, IsString, IsNumberString } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RestaurantsService } from './restaurants.service';
import { OrdersService } from '../orders/orders.service';
import type { AuthedRequestUser } from '../auth/jwt.strategy';

// ══════════════════════════════════════════════════════════
// 파일 역할: 식당/메뉴 관련 HTTP 엔드포인트
//
// 엔드포인트:
//   GET /api/restaurants                 — 식당 목록 (필터)
//   GET /api/restaurants/:id             — 식당 상세
//   GET /api/restaurants/:id/menus       — 식당 메뉴 목록
//   GET /api/restaurants/:id/reviews     — 매장별 별점/리뷰 (2026-05-15 배민 패턴)
//   GET /api/restaurants/:id/loyalty     — 단골 등급(NORMAL/REGULAR/VIP) + 방문 횟수
//                                          (2026-05-31 WOW#5 단골 랭킹)
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
  constructor(
    private readonly restaurantsService: RestaurantsService,
    // 2026-05-15 별점/리뷰는 orders 테이블의 review_* 컬럼을 사용하므로
    // OrdersService 를 재사용 (도메인 분리 — 리뷰는 주문에 종속).
    private readonly ordersService: OrdersService,
  ) {}

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

  // ── GET /api/restaurants/:id/reviews — 매장별 리뷰 (2026-05-15) ─
  // 사장 어플 / 손님 식당 상세 화면에서 평균 평점 + 리뷰 리스트 표시 용.
  // OrdersService.getReviewsByRestaurant 를 그대로 위임 — 별점 데이터는
  // orders 테이블의 review_score/review_text/review_at 컬럼에 저장되므로
  // 도메인 소유자(OrdersService) 가 단일 진입점.
  //
  // 응답 형태: { averageScore: number, count: number, reviews: [...] }
  @Get(':id/reviews')
  async getReviews(@Param('id') id: string) {
    const result = await this.ordersService.getReviewsByRestaurant(id);
    return { success: true, data: result };
  }

  // ── GET /api/restaurants/:id/loyalty — 단골 등급 (WOW#5) ────────
  //
  // 2026-05-31 추가 — "식당 단골 랭킹" WOW 포인트.
  //
  // 입력:
  //   :id         식당 UUID
  //   ?userId     단골 등급을 조회할 손님 user_id (필수 쿼리)
  //
  // 응답:
  //   { visitCount: number, rank: 'NORMAL'|'REGULAR'|'VIP', isFirstTime: boolean }
  //
  // 등급 규칙(고정 — 프론트 뱃지 색과 1:1 대응):
  //   1~2회 → NORMAL  (흰 배경 뱃지)
  //   3~4회 → REGULAR (주황 뱃지)
  //   5회~  → VIP     (금색 뱃지)
  //
  // 카운트 정의:
  //   orders.status = 'COMPLETED' AND user_id = :userId AND restaurant_id = :id
  //   (취소/조리중 주문은 카운트 X — "픽업 완료" 기준이라야 신뢰 가능)
  //
  // 보안:
  //   현재 손님 본인 외 타인의 단골 등급도 조회 가능하지만 등급 자체는
  //   민감정보가 아니라 차단하지 않음. 다만 userId 미지정 시는 400.
  @Get(':id/loyalty')
  async getLoyalty(
    @Req() req: { user: AuthedRequestUser },
    @Param('id') restaurantId: string,
  ) {
    if (req.user.type !== 'USER' || !req.user.userId) {
      throw new ForbiddenException('사용자 계정으로만 조회할 수 있습니다.');
    }
    const result = await this.restaurantsService.getLoyalty(
      restaurantId,
      req.user.userId,
    );
    return { success: true, data: result };
  }
}
