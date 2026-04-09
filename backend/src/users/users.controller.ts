import { Body, Controller, Get, Patch, Req, UseGuards } from '@nestjs/common';
import { IsOptional, IsString, IsNumber } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { UsersService } from './users.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 유저 관련 HTTP 엔드포인트
//
// 엔드포인트:
//   GET  /api/users/me  — 내 프로필 조회
//   PATCH /api/users/me — 프로필/조건 수정
//
// @UseGuards(JwtAuthGuard): Authorization 헤더의 JWT 검증
//   → 성공 시 req.user = { userId: '...' } 주입
//   → 실패 시 401 반환
// ══════════════════════════════════════════════════════════

class UpdateUserDto {
  @IsOptional() @IsString() name?: string;
  @IsOptional() @IsString() org?: string;
  @IsOptional() @IsString() profileImage?: string;
  @IsOptional() @IsString() radius?: string;
  @IsOptional() @IsNumber() budget?: number;
  @IsOptional() @IsString() speed?: string;
}

@Controller('users')
@UseGuards(JwtAuthGuard) // 모든 엔드포인트에 JWT 인증 적용
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  // ── GET /api/users/me ────────────────────────────────
  @Get('me')
  async getMe(@Req() req: { user: { userId: string } }) {
    const result = await this.usersService.getMe(req.user.userId);
    return { success: true, data: result };
  }

  // ── PATCH /api/users/me ──────────────────────────────
  // 온보딩 CU-03(이름/소속) + CU-05(반경/예산/속도) 완료 시 호출
  @Patch('me')
  async updateMe(
    @Req() req: { user: { userId: string } },
    @Body() dto: UpdateUserDto,
  ) {
    const result = await this.usersService.updateMe(req.user.userId, dto);
    return { success: true, data: result };
  }
}
