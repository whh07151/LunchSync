import { Body, Controller, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
// 2026-05-13 SkipThrottle: POS 단말이 주문 목록/통계를 폴링하면서 글로벌
//   throttler(분당 100) 한도를 빠르게 소모해 429 유발. 폴링성 GET 만 제외하고
//   상태 변경(PATCH)·취소(POST)는 보안 유지 위해 throttle 적용 그대로 둠.
import { SkipThrottle } from '@nestjs/throttler';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { assertPosAccessTo } from '../auth/pos-ownership.util';
import type { AuthedRequestUser } from '../auth/jwt.strategy';
import { PosService } from './pos.service';

// 2026-05-12 추가: req.user 타입 보강 — passport 가 주입한 사용자 객체.
type AuthedRequest = { user: AuthedRequestUser };

// ══════════════════════════════════════════════════════════
// 파일 역할: 점주앱/POS HTTP 엔드포인트
//
// 엔드포인트 (정식 + 별칭):
//   GET   /api/pos/restaurants/:id/orders   — 식당별 주문 목록 (OW-10) [정식]
//   GET   /api/pos/orders/:restaurantId     — 위와 동일 (LSPOS 명세 호환 별칭)
//   GET   /api/pos/restaurants/:id/stats    — 결제 상태 통계 (POS-08) [정식]
//   GET   /api/pos/orders/:restaurantId/stats — 위와 동일 (LSPOS 명세 호환 별칭)
//   PATCH /api/pos/orders/:id/status        — 주문 상태 변경
//   POST  /api/pos/orders/:id/cancel        — 취소/환불 (POS-09)
//
// 별칭 라우트 추가 배경 (2026-05-12):
//   LSPOS POS_BUILD_GUIDE 명세는 `/pos/orders/:restaurantId` 형식이지만
//   본 백엔드는 RESTful 한 `/pos/restaurants/:id/orders` 로 먼저 구현됨.
//   기존 사장 홈(우리 owner_home_screen) 과 LSPOS 둘 다 깨지지 않게 둘 다 동작하도록.
// ══════════════════════════════════════════════════════════

// 2026-05-13 보안 패치: status 는 정해진 ENUM 값만 허용, reason 길이 제한
class UpdatePosOrderStatusDto {
  @IsIn(['PREPARING', 'READY', 'COMPLETED'])
  status: string;
}

class CancelOrderDto {
  @IsOptional() @IsString() @MaxLength(500) reason?: string;
}

@Controller('pos')
@UseGuards(JwtAuthGuard)
export class PosController {
  constructor(private readonly posService: PosService) {}

  // ── OW-10: 식당별 주문 목록 (정식 경로) ───────────────
  // 권한: POS 토큰의 매장 ID 와 path 매장 ID 일치 필수 (2026-05-12 박검토A)
  // 폴링 엔드포인트 → throttler 제외 (2026-05-13)
  @SkipThrottle()
  @Get('restaurants/:id/orders')
  async getOrders(
    @Req() req: AuthedRequest,
    @Param('id') restaurantId: string,
    @Query('status') status?: string,
  ) {
    assertPosAccessTo(req.user, restaurantId);
    const result = await this.posService.getOrdersByRestaurant(
      restaurantId,
      status,
    );
    return { success: true, data: result };
  }

  // ── 별칭: LSPOS POS_BUILD_GUIDE 명세 호환 ─────────────
  // 폴링 엔드포인트 → throttler 제외 (2026-05-13)
  @SkipThrottle()
  @Get('orders/:restaurantId')
  async getOrdersAlias(
    @Req() req: AuthedRequest,
    @Param('restaurantId') restaurantId: string,
    @Query('status') status?: string,
  ) {
    return this.getOrders(req, restaurantId, status);
  }

  // ── POS-08: 결제 상태 통계 (정식 경로) ────────────────
  // 폴링 엔드포인트 → throttler 제외 (2026-05-13)
  @SkipThrottle()
  @Get('restaurants/:id/stats')
  async getStats(
    @Req() req: AuthedRequest,
    @Param('id') restaurantId: string,
  ) {
    assertPosAccessTo(req.user, restaurantId);
    const result = await this.posService.getPaymentStats(restaurantId);
    return { success: true, data: result };
  }

  // ── 별칭: LSPOS POS_BUILD_GUIDE 명세 호환 ─────────────
  // 폴링 엔드포인트 → throttler 제외 (2026-05-13)
  @SkipThrottle()
  @Get('orders/:restaurantId/stats')
  async getStatsAlias(
    @Req() req: AuthedRequest,
    @Param('restaurantId') restaurantId: string,
  ) {
    return this.getStats(req, restaurantId);
  }

  // ── 주문 상태 변경 (PREPARING → READY 등) ────────────
  // 권한: orderId → restaurant_id 사전 조회 후 토큰 일치 검증 (2026-05-13 보강)
  @Patch('orders/:id/status')
  async updateStatus(
    @Req() req: AuthedRequest,
    @Param('id') orderId: string,
    @Body() dto: UpdatePosOrderStatusDto,
  ) {
    const restaurantId = await this.posService.getRestaurantIdByOrderId(orderId);
    assertPosAccessTo(req.user, restaurantId);
    const result = await this.posService.updateOrderStatus(orderId, dto.status);
    return { success: true, data: result };
  }

  // ── POS-09: 취소/환불 ────────────────────────────────
  // 권한: orderId → restaurant_id 사전 조회 후 토큰 일치 검증 (2026-05-13 보강)
  @Post('orders/:id/cancel')
  async cancelOrder(
    @Req() req: AuthedRequest,
    @Param('id') orderId: string,
    @Body() dto: CancelOrderDto,
  ) {
    const restaurantId = await this.posService.getRestaurantIdByOrderId(orderId);
    assertPosAccessTo(req.user, restaurantId);
    const result = await this.posService.cancelOrder(orderId, dto.reason);
    return { success: true, data: result };
  }
}
