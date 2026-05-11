import { Body, Controller, Get, Patch, Post, Req, UseGuards } from '@nestjs/common';
import {
  IsOptional,
  IsString,
  IsNumber,
  IsArray,
  IsNotEmpty,
  MaxLength,
  Min,
  Max,
  Matches,
} from 'class-validator';
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
  @MaxLength(500, { message: 'FCM 토큰이 너무 깁니다.' })
  token: string;
}

// 보안 패치: 모든 입력 필드에 길이/범위 제한 추가 (DoS + DB bloat 방어)
class UpdateUserDto {
  @IsOptional()
  @IsString()
  @MaxLength(50, { message: '이름은 50자 이하여야 해요.' })
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100, { message: '소속은 100자 이하여야 해요.' })
  org?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  profileImage?: string;

  @IsOptional()
  @IsString()
  @Matches(/^\d+(m|km)$/i, { message: '반경 형식은 "500m" 또는 "1km" 입니다.' })
  radius?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100000, { message: '예산은 10만원 이하여야 해요.' })
  budget?: number;

  @IsOptional()
  @IsString()
  @Matches(/^(FAST|NORMAL|SLOW)$/, { message: '속도는 FAST/NORMAL/SLOW 중 하나입니다.' })
  speed?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(30, { each: true })
  allergies?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(30, { each: true })
  dislikes?: string[];

  // OWNER 전용 필드 — 사장 내정보 탭에서 상호/사업자번호 수정
  @IsOptional()
  @IsString()
  @MaxLength(100, { message: '상호는 100자 이하여야 해요.' })
  businessName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20, { message: '사업자번호 형식이 맞지 않아요.' })
  businessNumber?: string;
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
