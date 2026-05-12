import { Body, Controller, Post } from '@nestjs/common';
import {
  IsEmail,
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  MinLength,
} from 'class-validator';
import { Throttle } from '@nestjs/throttler';
import { AuthService } from './auth.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 인증 관련 HTTP 엔드포인트
//
// 엔드포인트:
//   POST /api/auth/kakao         — 카카오 토큰으로 로그인/회원가입
//   POST /api/auth/signup/email  — 이메일+비밀번호 회원가입 (역할 선택 포함)
//   POST /api/auth/login/email   — 이메일+비밀번호 로그인
//   POST /api/auth/verify-phone  — Firebase Phone Auth ID 토큰 검증 후 사용자 갱신
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

// ── 휴대폰 인증 DTO ────────────────────────────────────
// Flutter 가 Firebase Phone Auth 로 받은 ID 토큰을 그대로 전달.
// existingUserId: 로그인된 상태에서 휴대폰만 추가 검증할 때 사용 (없으면 신규/전화로그인).
class VerifyPhoneDto {
  @IsString()
  @IsNotEmpty({ message: 'Firebase ID 토큰이 비어 있습니다.' })
  idToken: string;

  // 이미 로그인된 사용자가 본인확인 차원으로 휴대폰만 등록할 때 전달.
  // 미전달 시: phone_number 로 사용자 조회/생성하는 흐름으로 진입.
  @IsOptional()
  @IsString()
  existingUserId?: string;
}

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  // ── POST /api/auth/kakao ──────────────────────────────
  // Flutter에서 카카오 SDK로 받은 access token을 전달하면
  // LunchSync JWT + isNewUser + 유저 기본 정보를 반환
  // 부르트포스 차단 (2026-05-12): 카카오/이메일 로그인은 분당 5회로 강한 제한.
  // 정상 사용자는 1~2회면 끝나고, 봇이 자동 시도 시 6번째부터 429 응답.
  @Throttle({ auth: { limit: 5, ttl: 60_000 } })
  @Post('kakao')
  async kakaoLogin(@Body() dto: KakaoLoginDto) {
    const result = await this.authService.kakaoLogin(dto.kakaoAccessToken);
    return { success: true, data: result };
  }

  // ── POST /api/auth/signup/email ────────────────────────
  // 이메일+비밀번호로 신규 가입. role 선택에 따라 분기:
  //   CUSTOMER → 즉시 활성화 (status=APPROVED), nextStep=PROFILE_SETUP
  //   OWNER    → 승인 대기 (status=PENDING),  nextStep=OWNER_PENDING
  //
  // 폭주 차단 (2026-05-12): 한 IP 당 시간당 10회로 제한.
  // 봇이 무한 가입해 Supabase 무료 티어 행 quota 소진하는 공격 차단.
  @Throttle({ signup: { limit: 10, ttl: 3_600_000 } })
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
  //
  // 부르트포스 차단 (2026-05-12): 한 IP 당 분당 5회 제한.
  // bcrypt 10라운드(~100ms) + rate limit → 강한 비번 사실상 영원, 약한 비번도 시도 횟수 제한.
  @Throttle({ auth: { limit: 5, ttl: 60_000 } })
  @Post('login/email')
  async emailLogin(@Body() dto: EmailLoginDto) {
    const result = await this.authService.emailLogin(dto.email, dto.password);
    return { success: true, data: result };
  }

  // ── POST /api/auth/verify-phone ────────────────────────
  // Flutter 가 Firebase Phone Auth 로 받은 ID 토큰을 검증한다.
  //
  // 동작 분기:
  //   1) existingUserId 전달  → 로그인 사용자의 휴대폰 본인확인 (phone_verified_at 갱신)
  //   2) 미전달                → 전화번호로 사용자 조회/생성 → 카카오 로그인과 동일 구조 반환
  //
  // 응답 형식: AuthResult (accessToken + nextStep + user) — 카카오/이메일과 동일
  @Post('verify-phone')
  async verifyPhone(@Body() dto: VerifyPhoneDto) {
    const result = await this.authService.phoneVerify({
      idToken: dto.idToken,
      existingUserId: dto.existingUserId,
    });
    return { success: true, data: result };
  }
}
