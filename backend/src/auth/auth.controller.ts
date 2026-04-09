import { Body, Controller, Post } from '@nestjs/common';
import { IsString, IsNotEmpty } from 'class-validator';
import { AuthService } from './auth.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 인증 관련 HTTP 엔드포인트
//
// 엔드포인트:
//   POST /api/auth/kakao — 카카오 토큰으로 로그인/회원가입
// ══════════════════════════════════════════════════════════

// 요청 바디 DTO: 카카오 access token 하나만 받음
class KakaoLoginDto {
  @IsString()
  @IsNotEmpty()
  kakaoAccessToken: string;
}

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  // ── POST /api/auth/kakao ──────────────────────────────
  // Flutter에서 카카오 SDK로 받은 access token을 전달하면
  // LunchSync JWT + isNewUser + 유저 기본 정보를 반환
  @Post('kakao')
  async kakaoLogin(@Body() dto: KakaoLoginDto) {
    try {
      const result = await this.authService.kakaoLogin(dto.kakaoAccessToken);
      return { success: true, data: result };
    } catch (e) {
      // 디버깅용: 실제 에러 메시지를 응답에 포함
      // TODO: 배포 전 제거
      throw new Error(`카카오 로그인 실패: ${e instanceof Error ? e.message : String(e)}`);
    }
  }
}
