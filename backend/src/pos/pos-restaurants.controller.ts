import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { IsInt, IsNumber, IsOptional, IsString, Min } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import {
  CreateRestaurantDto,
  PosRestaurantsService,
} from './pos-restaurants.service';
import type { AuthedRequestUser } from '../auth/jwt.strategy';
import { PosAccessService } from '../auth/pos-ownership.util';

// ══════════════════════════════════════════════════════════
// 파일 역할: 사장 계정 기반 식당 등록/조회 HTTP 엔드포인트
//
// 엔드포인트:
//   POST /api/pos/restaurants   — 식당 등록 (USER JWT 필수)
//   GET  /api/pos/my-restaurant — 내 식당 조회 (USER JWT 필수)
//
// 인증:
//   JwtAuthGuard 통과 후 type='USER' 추가 검증.
//   POS 토큰(type='POS')으로는 접근 불가 — 식당 생성/조회는 사장 계정 전용.
// ══════════════════════════════════════════════════════════

type AuthedRequest = { user: AuthedRequestUser };

class CreateRestaurantRequestDto implements CreateRestaurantDto {
  @IsString() name: string;
  @IsString() category: string;
  @IsString() address: string;
  @IsNumber() lat: number;
  @IsNumber() lng: number;
  @IsOptional() @IsInt() @Min(0) priceRange?: number;
  @IsOptional() @IsString() imageUrl?: string;
}

@Controller('pos')
@UseGuards(JwtAuthGuard)
export class PosRestaurantsController {
  constructor(
    private readonly service: PosRestaurantsService,
    private readonly posAccess: PosAccessService,
  ) {}

  // ── POST /api/pos/restaurants — 식당 등록 ─────────────
  // 사장이 LSPOS 최초 진입 시 식당 정보를 입력해 DB에 저장.
  // 성공 시 POS JWT(posToken) 도 함께 반환 → LSPOS 가 바로 대시보드 진입.
  @Post('restaurants')
  async createRestaurant(
    @Req() req: AuthedRequest,
    @Body() dto: CreateRestaurantRequestDto,
  ) {
    if (req.user.type !== 'USER' || !req.user.userId) {
      throw new BadRequestException('사용자 계정(USER)으로만 식당을 등록할 수 있습니다.');
    }
    await this.posAccess.assertApprovedOwner(req.user.userId);
    const result = await this.service.create(req.user.userId, dto);
    return { success: true, data: result };
  }

  // ── GET /api/pos/my-restaurant — 내 식당 조회 ──────────
  // LSPOS 재방문 시 사장 계정으로 이미 등록된 식당 정보 + posToken 획득.
  @Get('my-restaurant')
  async getMyRestaurant(@Req() req: AuthedRequest) {
    if (req.user.type !== 'USER' || !req.user.userId) {
      throw new BadRequestException('사용자 계정(USER)으로만 조회할 수 있습니다.');
    }
    await this.posAccess.assertApprovedOwner(req.user.userId);
    const result = await this.service.getMyRestaurant(req.user.userId);
    return { success: true, data: result };
  }
}
