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
  IsNumber,
  IsOptional,
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

class OrderItemDto {
  @IsString() menuItemId: string;
  @IsNumber() quantity: number;
}

class CreateOrderDto {
  @IsString() @IsNotEmpty() sessionId: string;

  @IsArray()
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

  @Get(':id')
  async getOrderById(@Param('id') id: string) {
    const result = await this.ordersService.getOrderById(id);
    return { success: true, data: result };
  }

  @Patch(':id/status')
  async updateStatus(
    @Param('id') id: string,
    @Body() dto: UpdateOrderStatusDto,
  ) {
    const result = await this.ordersService.updateOrderStatus(id, dto);
    return { success: true, data: result };
  }
}
