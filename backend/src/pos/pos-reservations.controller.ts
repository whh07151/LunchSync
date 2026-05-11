import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { IsIn, IsNumber, IsOptional, IsString, IsNotEmpty } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { PosReservationsService } from './pos-reservations.service';
import type { ReservationStatus } from './pos-reservations.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: LSPOS 예약/웨이팅 모듈 HTTP 엔드포인트
//
// 엔드포인트:
//   GET    /api/pos/reservations/:restaurantId         — 목록
//   POST   /api/pos/reservations/:restaurantId         — 추가
//   PATCH  /api/pos/reservations/item/:id/status       — 상태 변경
//   DELETE /api/pos/reservations/item/:id              — 삭제
//
// 인증: JWT
// ══════════════════════════════════════════════════════════

class CreateReservationBody {
  @IsIn(['WAITING', 'RESERVATION'])
  kind: 'WAITING' | 'RESERVATION';

  @IsString() @IsNotEmpty()
  customerName: string;

  @IsNumber()
  partySize: number;

  @IsOptional() @IsString()
  scheduledAt?: string;

  @IsOptional() @IsString()
  note?: string;
}

class UpdateStatusBody {
  @IsIn(['OPEN', 'SEATED', 'CANCELLED'])
  status: ReservationStatus;
}

@Controller('pos/reservations')
@UseGuards(JwtAuthGuard)
export class PosReservationsController {
  constructor(private readonly service: PosReservationsService) {}

  @Get(':restaurantId')
  async list(@Param('restaurantId') restaurantId: string) {
    const data = await this.service.list(restaurantId);
    return { success: true, data };
  }

  @Post(':restaurantId')
  async create(
    @Param('restaurantId') restaurantId: string,
    @Body() dto: CreateReservationBody,
  ) {
    const data = await this.service.add(restaurantId, dto);
    return { success: true, data };
  }

  @Patch('item/:id/status')
  async updateStatus(
    @Param('id') id: string,
    @Body() dto: UpdateStatusBody,
  ) {
    const data = await this.service.updateStatus(id, dto.status);
    return { success: true, data };
  }

  @Delete('item/:id')
  async remove(@Param('id') id: string) {
    const data = await this.service.remove(id);
    return { success: true, data };
  }
}
