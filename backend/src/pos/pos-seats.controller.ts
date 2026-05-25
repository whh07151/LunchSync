import { Body, Controller, Delete, Get, Param, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { IsArray, IsIn, IsNumber, IsOptional, IsString } from 'class-validator';
import { Type } from 'class-transformer';
// 2026-05-13 SkipThrottle: LSPOS 데모 단말 진입 시 좌석 5개를 연속 POST 로
//   시드하다 6번째부터 429 발생. 좌석 목록 폴링 GET 과 시드용 POST 를 throttle
//   에서 제외. JWT + assertPosAccessTo 로 본인 매장만 접근하므로 영향 한정.
import { SkipThrottle } from '@nestjs/throttler';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { assertPosAccessTo } from '../auth/pos-ownership.util';
import type { AuthedRequestUser } from '../auth/jwt.strategy';
import { PosSeatsService } from './pos-seats.service';
import type { UpsertSeatDto } from './pos-seats.service';

type AuthedRequest = { user: AuthedRequestUser };

// ══════════════════════════════════════════════════════════
// 파일 역할: 점주앱/LSPOS 좌석 모듈 HTTP 엔드포인트
//
// 엔드포인트:
//   GET    /api/pos/seats/:restaurantId           — 좌석 목록
//   POST   /api/pos/seats/:restaurantId           — 좌석 추가
//   PATCH  /api/pos/seats/item/:seatId            — 좌석 갱신(점유/해제, items 등)
//   DELETE /api/pos/seats/item/:seatId            — 좌석 삭제
//
// 인증: JWT (사장/POS 단말 둘 다 사용)
// ══════════════════════════════════════════════════════════

class SeatItemPayload {
  @IsString() menuId: string;
  @IsString() name: string;
  @IsNumber() price: number;
  @IsNumber() quantity: number;
  @IsString() addedAt: string;
}

class CreateSeatDto {
  @IsOptional() @IsString() label?: string;
}

class UpdateSeatDto {
  @IsOptional() @IsString() label?: string;
  @IsOptional() @IsIn(['empty', 'occupied']) status?: 'empty' | 'occupied';
  // null 허용 — 좌석 해제 시 startedAt 클리어
  @IsOptional() startedAt?: string | null;
  @IsOptional() @IsArray() @Type(() => SeatItemPayload) items?: SeatItemPayload[];
  @IsOptional() @IsNumber() sortOrder?: number;
}

@Controller('pos/seats')
@UseGuards(JwtAuthGuard)
export class PosSeatsController {
  constructor(private readonly seatsService: PosSeatsService) {}

  @SkipThrottle({ default: true, auth: true, signup: true })
  @Get(':restaurantId')
  async list(
    @Req() req: AuthedRequest,
    @Param('restaurantId') restaurantId: string,
  ) {
    assertPosAccessTo(req.user, restaurantId);
    const data = await this.seatsService.listSeats(restaurantId);
    return { success: true, data };
  }

  @SkipThrottle({ default: true, auth: true, signup: true })
  @Post(':restaurantId')
  async create(
    @Req() req: AuthedRequest,
    @Param('restaurantId') restaurantId: string,
    @Body() dto: CreateSeatDto,
  ) {
    assertPosAccessTo(req.user, restaurantId);
    const data = await this.seatsService.addSeat(restaurantId, dto.label);
    return { success: true, data };
  }

  // 권한: seatId → restaurant_id 사전 조회 후 토큰 일치 검증 (2026-05-13 보강)
  @Patch('item/:seatId')
  async update(
    @Req() req: AuthedRequest,
    @Param('seatId') seatId: string,
    @Body() dto: UpdateSeatDto,
  ) {
    const restaurantId = await this.seatsService.getRestaurantIdBySeatId(seatId);
    assertPosAccessTo(req.user, restaurantId);
    const data = await this.seatsService.updateSeat(seatId, dto as UpsertSeatDto);
    return { success: true, data };
  }

  // 권한: seatId → restaurant_id 사전 조회 후 토큰 일치 검증 (2026-05-13 보강)
  @Delete('item/:seatId')
  async remove(
    @Req() req: AuthedRequest,
    @Param('seatId') seatId: string,
  ) {
    const restaurantId = await this.seatsService.getRestaurantIdBySeatId(seatId);
    assertPosAccessTo(req.user, restaurantId);
    const data = await this.seatsService.removeSeat(seatId);
    return { success: true, data };
  }
}

