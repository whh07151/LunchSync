import { Body, Controller, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { IsOptional, IsString } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { PosService } from './pos.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 점주앱/POS HTTP 엔드포인트
//
// 엔드포인트:
//   GET  /api/pos/restaurants/:id/orders — 식당별 주문 목록 (OW-10)
//   GET  /api/pos/restaurants/:id/stats  — 결제 상태 통계 (POS-08)
//   PATCH /api/pos/orders/:id/status     — 주문 상태 변경
//   POST /api/pos/orders/:id/cancel      — 취소/환불 (POS-09)
// ══════════════════════════════════════════════════════════

class UpdatePosOrderStatusDto {
  @IsString() status: string;
}

class CancelOrderDto {
  @IsOptional() @IsString() reason?: string;
}

@Controller('pos')
@UseGuards(JwtAuthGuard)
export class PosController {
  constructor(private readonly posService: PosService) {}

  // ── OW-10: 식당별 주문 목록 ───────────────────────────
  @Get('restaurants/:id/orders')
  async getOrders(
    @Param('id') restaurantId: string,
    @Query('status') status?: string,
  ) {
    const result = await this.posService.getOrdersByRestaurant(
      restaurantId,
      status,
    );
    return { success: true, data: result };
  }

  // ── POS-08: 결제 상태 통계 ────────────────────────────
  @Get('restaurants/:id/stats')
  async getStats(@Param('id') restaurantId: string) {
    const result = await this.posService.getPaymentStats(restaurantId);
    return { success: true, data: result };
  }

  // ── 주문 상태 변경 (PREPARING → READY 등) ────────────
  @Patch('orders/:id/status')
  async updateStatus(
    @Param('id') orderId: string,
    @Body() dto: UpdatePosOrderStatusDto,
  ) {
    const result = await this.posService.updateOrderStatus(orderId, dto.status);
    return { success: true, data: result };
  }

  // ── POS-09: 취소/환불 ────────────────────────────────
  @Post('orders/:id/cancel')
  async cancelOrder(
    @Param('id') orderId: string,
    @Body() dto: CancelOrderDto,
  ) {
    const result = await this.posService.cancelOrder(orderId, dto.reason);
    return { success: true, data: result };
  }
}
