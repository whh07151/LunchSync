import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { IsArray, IsIn, IsNumber, IsOptional, IsString } from 'class-validator';
import { Type } from 'class-transformer';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { PosSeatsService } from './pos-seats.service';
import type { UpsertSeatDto } from './pos-seats.service';

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

  @Get(':restaurantId')
  async list(@Param('restaurantId') restaurantId: string) {
    const data = await this.seatsService.listSeats(restaurantId);
    return { success: true, data };
  }

  @Post(':restaurantId')
  async create(
    @Param('restaurantId') restaurantId: string,
    @Body() dto: CreateSeatDto,
  ) {
    const data = await this.seatsService.addSeat(restaurantId, dto.label);
    return { success: true, data };
  }

  @Patch('item/:seatId')
  async update(@Param('seatId') seatId: string, @Body() dto: UpdateSeatDto) {
    const data = await this.seatsService.updateSeat(seatId, dto as UpsertSeatDto);
    return { success: true, data };
  }

  @Delete('item/:seatId')
  async remove(@Param('seatId') seatId: string) {
    const data = await this.seatsService.removeSeat(seatId);
    return { success: true, data };
  }
}

