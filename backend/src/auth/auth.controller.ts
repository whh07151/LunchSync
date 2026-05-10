import { Body, Controller, Post } from '@nestjs/common';
import {
  IsEmail,
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  MinLength,
} from 'class-validator';
import { AuthService } from './auth.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 인증 관련 HTTP 엔드포인트
//
// 엔드포인트:
//   POST /api/auth/kakao         — 카카오 토큰으로 로그인/회원가입
//   POST /api/auth/signup/email  — 이메일+비밀번호 회원가입 (역할 선택 포함)
//   POST /api/auth/login/email   — 이메일+비밀번호 로그인
// ══════════════════════════════════════════════════════════

// ── 카카오 로그인 DTO ──────────────────────────────────
class KakaoLoginDto {
  @IsString()
  @IsNotEmpty()
  kakaoAccessToken: string;
}

// ── 이메일 회원가입 DTO ────────────────────────────────
// role=OWNER일 때 businessName/businessNumber가 필요하지만,
// IsOptional()로 선언하고 service 레이어에서 추가 검증.
class EmailSignupDto {
  @IsEmail({}, { message: '이메일 형식이 올바르지 않습니다.' })
  email: string;

  @IsString()
  @MinLength(8, { message: '비밀번호는 8자 이상이어야 합니다.' })
  password: string;

  @IsString()
  @IsNotEmpty({ message: '이름을 입력해주세요.' })
  name: string;

  // 역할: 회원가입 화면의 라디오 선택값
  @IsIn(['CUSTOMER', 'OWNER'], { message: 'role은 CUSTOMER 또는 OWNER여야 합니다.' })
  role: 'CUSTOMER' | 'OWNER';

  // OWNER일 때만 사용
  @IsOptional()
  @IsString()
  businessName?: string;

  @IsOptional()
  @IsString()
  businessNumber?: string;
}

// ── 이메일 로그인 DTO ──────────────────────────────────
class EmailLoginDto {
  @IsEmail({}, { message: '이메일 형식이 올바르지 않습니다.' })
  email: string;

  @IsString()
  @IsNotEmpty({ message: '비밀번호를 입력해주세요.' })
  password: string;
}

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  // ── POST /api/auth/kakao ──────────────────────────────
  // Flutter에서 카카오 SDK로 받은 access token을 전달하면
  // LunchSync JWT + isNewUser + 유저 기본 정보를 반환
  @Post('kakao')
  async kakaoLogin(@Body() dto: KakaoLoginDto) {
    const result = await this.authService.kakaoLogin(dto.kakaoAccessToken);
    return { success: true, data: result };
  }

  // ── POST /api/auth/signup/email ────────────────────────
  // 이메일+비밀번호로 신규 가입. role 선택에 따라 분기:
  //   CUSTOMER → 즉시 활성화 (status=APPROVED), nextStep=PROFILE_SETUP
  //   OWNER    → 승인 대기 (status=PENDING),  nextStep=OWNER_PENDING
  @Post('signup/email')
  async emailSignup(@Body() dto: EmailSignupDto) {
    const result = await this.authService.emailSignup({
      email: dto.email,
      password: dto.password,
      name: dto.name,
      role: dto.role,
      businessName: dto.businessName,
      businessNumber: dto.businessNumber,
    });
    return { success: true, data: result };
  }

  // ── POST /api/auth/login/email ─────────────────────────
  // 이메일+비밀번호 로그인. 응답은 카카오 로그인과 동일 구조.
  @Post('login/email')
  async emailLogin(@Body() dto: EmailLoginDto) {
    const result = await this.authService.emailLogin(dto.email, dto.password);
    return { success: true, data: result };
  }
}
