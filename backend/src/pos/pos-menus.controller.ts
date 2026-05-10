import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import {
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  Min,
} from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import {
  CreateMenuDto,
  PosMenusService,
  UpdateMenuDto,
} from './pos-menus.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 사장/POS 메뉴 관리 HTTP 엔드포인트
//
// 엔드포인트:
//   GET    /api/pos/menus/:restaurantId       — 메뉴 목록 (품절 포함)
//   POST   /api/pos/menus/:restaurantId       — 메뉴 추가
//   PATCH  /api/pos/menus/item/:id            — 메뉴 수정/품절 토글
//   DELETE /api/pos/menus/item/:id            — 메뉴 삭제 (FK 있으면 거절)
//
// 인증:
//   JwtAuthGuard — USER(role=OWNER) 또는 POS 토큰 모두 통과.
//   캡스톤 단계는 JWT 만 검증, 권한 매핑(restaurantId 일치)은 추후 보강.
// ══════════════════════════════════════════════════════════

class CreateMenuRequestDto implements CreateMenuDto {
  @IsString() name: string;
  @IsInt() @Min(0) price: number;
  @IsOptional() @IsString() category?: string;
  @IsOptional() @IsString() description?: string;
  @IsOptional() @IsString() imageUrl?: string;
}

class UpdateMenuRequestDto implements UpdateMenuDto {
  @IsOptional() @IsString() name?: string;
  @IsOptional() @IsInt() @Min(0) price?: number;
  @IsOptional() @IsString() category?: string;
  @IsOptional() @IsString() description?: string;
  @IsOptional() @IsString() imageUrl?: string;
  @IsOptional() @IsBoolean() isAvailable?: boolean;
}

@Controller('pos/menus')
@UseGuards(JwtAuthGuard)
export class PosMenusController {
  constructor(private readonly posMenusService: PosMenusService) {}

  @Get(':restaurantId')
  async list(@Param('restaurantId') restaurantId: string) {
    const result = await this.posMenusService.list(restaurantId);
    return { success: true, data: result };
  }

  @Post(':restaurantId')
  async create(
    @Param('restaurantId') restaurantId: string,
    @Body() dto: CreateMenuRequestDto,
  ) {
    const result = await this.posMenusService.create(restaurantId, dto);
    return { success: true, data: result };
  }

  @Patch('item/:id')
  async update(
    @Param('id') menuId: string,
    @Body() dto: UpdateMenuRequestDto,
  ) {
    const result = await this.posMenusService.update(menuId, dto);
    return { success: true, data: result };
  }

  @Delete('item/:id')
  async delete(@Param('id') menuId: string) {
    const result = await this.posMenusService.delete(menuId);
    return { success: true, data: result };
  }
}
