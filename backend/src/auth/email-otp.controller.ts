import {
  Body,
  Controller,
  ForbiddenException,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { IsEmail, IsNotEmpty, IsString, Length } from 'class-validator';
import { Throttle } from '@nestjs/throttler';
import { EmailOtpService } from './email-otp.service';
import { AuthService } from './auth.service';
import {
  EmailVerificationGuard,
  type EmailVerificationRequest,
} from './email-verification.guard';

// ══════════════════════════════════════════════════════════
// 파일 역할: 이메일 OTP 인증 HTTP 엔드포인트
//
// 엔드포인트:
//   POST /api/auth/email/send-otp   — OTP 발송 요청 (Supabase Auth 가 메일 송신)
//   POST /api/auth/email/verify-otp — OTP 검증 + email_verified_at 갱신
//
// 인증:
//   두 엔드포인트 모두 가입/미인증 로그인에서 받은 EMAIL_VERIFICATION 목적
//   Bearer JWT가 필요하다. body 이메일은 token subject와 일치해야 한다.
// ══════════════════════════════════════════════════════════

class SendOtpDto {
  @IsEmail({}, { message: '이메일 형식이 올바르지 않습니다.' })
  @IsNotEmpty()
  email: string;
}

class VerifyOtpDto {
  @IsEmail({}, { message: '이메일 형식이 올바르지 않습니다.' })
  @IsNotEmpty()
  email: string;

  // Supabase Auth 의 OTP 는 6자리 숫자. 너무 짧거나 길면 사전 거절.
  @IsString()
  @Length(6, 6, { message: '인증 코드는 6자리입니다.' })
  code: string;
}

@Controller('auth/email')
@UseGuards(EmailVerificationGuard)
export class EmailOtpController {
  constructor(
    private readonly emailOtpService: EmailOtpService,
    private readonly authService: AuthService,
  ) {}

  // ── POST /api/auth/email/send-otp ────────────────────
  // 가입한 사용자가 이메일 인증을 위해 호출. 메일이 발송됨.
  @Post('send-otp')
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  async sendOtp(
    @Req() request: EmailVerificationRequest,
    @Body() dto: SendOtpDto,
  ) {
    const principal = this.requireMatchingPrincipal(request, dto.email);
    const result = await this.emailOtpService.sendOtp(
      principal.userId,
      principal.email,
    );
    return { success: true, data: result };
  }

  // ── POST /api/auth/email/verify-otp ──────────────────
  // 사용자가 받은 6자리 코드 검증 → 성공 시 email_verified_at 채움.
  @Post('verify-otp')
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  async verifyOtp(
    @Req() request: EmailVerificationRequest,
    @Body() dto: VerifyOtpDto,
  ) {
    const principal = this.requireMatchingPrincipal(request, dto.email);
    await this.emailOtpService.verifyOtp(
      principal.userId,
      principal.email,
      dto.code,
    );
    const result = await this.authService.completeEmailVerification(
      principal.userId,
      principal.email,
    );
    return { success: true, data: result };
  }

  private requireMatchingPrincipal(
    request: EmailVerificationRequest,
    requestedEmail: string,
  ) {
    const principal = request.emailVerification;
    if (
      !principal ||
      principal.email.trim().toLowerCase() !==
        requestedEmail.trim().toLowerCase()
    ) {
      throw new ForbiddenException({
        statusCode: 403,
        code: 'EMAIL_VERIFICATION_SUBJECT_MISMATCH',
        message: '인증 세션과 요청 이메일이 일치하지 않습니다.',
        retryable: false,
      });
    }
    return principal;
  }
}
