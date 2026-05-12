import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import {
  IsString,
  IsNotEmpty,
  IsArray,
  ValidateNested,
  IsInt,
  IsOptional,
  Min,
  Max,
  ArrayMinSize,
  ArrayMaxSize,
} from 'class-validator';
import { Type } from 'class-transformer';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { OrdersService } from './orders.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 주문/결제 관련 HTTP 엔드포인트
//
// 엔드포인트:
//   POST  /api/orders          — 주문 생성 + 결제 (CU-17/18/19)
//   GET   /api/orders/today    — 오늘 내 주문 목록
//   GET   /api/orders/:id      — 주문 상세
//   PATCH /api/orders/:id/status — 주문 상태 변경
// ══════════════════════════════════════════════════════════

// 2026-05-13 보안 패치: quantity 범위 제약 추가 (결제 금액 조작/오버플로우 방지)
class OrderItemDto {
  @IsString() menuItemId: string;
  @IsInt() @Min(1) @Max(999) quantity: number;
}

class CreateOrderDto {
  @IsString() @IsNotEmpty() sessionId: string;

  // 2026-05-13 보안 패치: 한 주문에 메뉴 1~100개로 제한 (DoS 방어)
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => OrderItemDto)
  items: OrderItemDto[];

  @IsOptional()
  @IsString()
  paymentMethod?: string; // CARD | TRANSFER | CASH | SIMULATE
}

class UpdateOrderStatusDto {
  @IsString() @IsNotEmpty() status: string;
}

@Controller('orders')
@UseGuards(JwtAuthGuard)
export class OrdersController {
  constructor(private readonly ordersService: OrdersService) {}

  @Post()
  async createOrder(
    @Req() req: { user: { userId: string } },
    @Body() dto: CreateOrderDto,
  ) {
    const result = await this.ordersService.createOrder(req.user.userId, {
      sessionId: dto.sessionId,
      items: dto.items,
      paymentMethod: dto.paymentMethod ?? 'SIMULATE',
    });
    return { success: true, data: result };
  }

  @Get('today')
  async getTodayOrders(@Req() req: { user: { userId: string } }) {
    const result = await this.ordersService.getTodayOrders(req.user.userId);
    return { success: true, data: result };
  }

  // 2026-05-13 보안 패치: 본인 주문 또는 같은 세션 멤버만 조회 가능
  @Get(':id')
  async getOrderById(
    @Req() req: { user: { userId: string } },
    @Param('id') id: string,
  ) {
    const result = await this.ordersService.getOrderById(id, req.user.userId);
    return { success: true, data: result };
  }

  @Patch(':id/status')
  async updateStatus(
    @Req() req: { user: { userId: string } },
    @Param('id') id: string,
    @Body() dto: UpdateOrderStatusDto,
  ) {
    const result = await this.ordersService.updateOrderStatus(
      id,
      req.user.userId,
      dto,
    );
    return { success: true, data: result };
  }
}
