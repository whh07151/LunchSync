import { Body, Controller, Get, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { IsOptional, IsString, IsNumber, IsArray, IsNotEmpty } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { UsersService } from './users.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 유저 관련 HTTP 엔드포인트
//
// 엔드포인트:
//   GET  /api/users/me            — 내 프로필 조회
//   PATCH /api/users/me           — 프로필/조건 수정
//   POST /api/users/me/fcm-token  — FCM 토큰 저장 (앱 로그인 직후 호출)
//
// @UseGuards(JwtAuthGuard): Authorization 헤더의 JWT 검증
//   → 성공 시 req.user = { userId: '...' } 주입
//   → 실패 시 401 반환
// ══════════════════════════════════════════════════════════

class SaveFcmTokenDto {
  @IsString()
  @IsNotEmpty({ message: 'FCM 토큰이 비어 있습니다.' })
  token: string;
}

class UpdateUserDto {
  @IsOptional() @IsString() name?: string;
  @IsOptional() @IsString() org?: string;
  @IsOptional() @IsString() profileImage?: string;
  @IsOptional() @IsString() radius?: string;
  @IsOptional() @IsNumber() budget?: number;
  @IsOptional() @IsString() speed?: string;
  @IsOptional() @IsArray() @IsString({ each: true }) allergies?: string[];
  @IsOptional() @IsArray() @IsString({ each: true }) dislikes?: string[];
  // OWNER 전용 필드 — 사장 내정보 탭에서 상호/사업자번호 수정
  @IsOptional() @IsString() businessName?: string;
  @IsOptional() @IsString() businessNumber?: string;
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

  // ── POST /api/users/me/fcm-token ─────────────────────
  // Flutter 앱이 firebase_messaging.getToken() 으로 발급받은 단말 토큰을 저장.
  // 로그인 직후 또는 onTokenRefresh 콜백에서 호출.
  @Post('me/fcm-token')
  async saveFcmToken(
    @Req() req: { user: { userId: string } },
    @Body() dto: SaveFcmTokenDto,
  ) {
    await this.usersService.saveFcmToken(req.user.userId, dto.token);
    return { success: true };
  }
}
