import { Body, Controller, Delete, Get, Param, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { IsIn, IsNumber, IsOptional, IsString, IsNotEmpty } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { assertPosAccessTo } from '../auth/pos-ownership.util';
import type { AuthedRequestUser } from '../auth/jwt.strategy';
import { PosReservationsService } from './pos-reservations.service';
import type { ReservationStatus } from './pos-reservations.service';

type AuthedRequest = { user: AuthedRequestUser };

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
  async list(
    @Req() req: AuthedRequest,
    @Param('restaurantId') restaurantId: string,
  ) {
    assertPosAccessTo(req.user, restaurantId);
    const data = await this.service.list(restaurantId);
    return { success: true, data };
  }

  @Post(':restaurantId')
  async create(
    @Req() req: AuthedRequest,
    @Param('restaurantId') restaurantId: string,
    @Body() dto: CreateReservationBody,
  ) {
    assertPosAccessTo(req.user, restaurantId);
    const data = await this.service.add(restaurantId, dto);
    return { success: true, data };
  }

  // 권한: reservationId → restaurant_id 사전 조회 후 토큰 일치 검증 (2026-05-13 보강)
  @Patch('item/:id/status')
  async updateStatus(
    @Req() req: AuthedRequest,
    @Param('id') id: string,
    @Body() dto: UpdateStatusBody,
  ) {
    const restaurantId = await this.service.getRestaurantIdByReservationId(id);
    assertPosAccessTo(req.user, restaurantId);
    const data = await this.service.updateStatus(id, dto.status);
    return { success: true, data };
  }

  // 권한: reservationId → restaurant_id 사전 조회 후 토큰 일치 검증 (2026-05-13 보강)
  @Delete('item/:id')
  async remove(
    @Req() req: AuthedRequest,
    @Param('id') id: string,
  ) {
    const restaurantId = await this.service.getRestaurantIdByReservationId(id);
    assertPosAccessTo(req.user, restaurantId);
    const data = await this.service.remove(id);
    return { success: true, data };
  }
}
