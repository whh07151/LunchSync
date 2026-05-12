import { Body, Controller, Post } from '@nestjs/common';
import { IsEmail, IsNotEmpty, IsString, Length } from 'class-validator';
import { EmailOtpService } from './email-otp.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 이메일 OTP 인증 HTTP 엔드포인트
//
// 엔드포인트:
//   POST /api/auth/email/send-otp   — OTP 발송 요청 (Supabase Auth 가 메일 송신)
//   POST /api/auth/email/verify-otp — OTP 검증 + email_verified_at 갱신
//
// 인증:
//   본 엔드포인트는 인증 없이 호출됨 (이메일 인증 자체이므로).
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
export class EmailOtpController {
  constructor(private readonly emailOtpService: EmailOtpService) {}

  // ── POST /api/auth/email/send-otp ────────────────────
  // 가입한 사용자가 이메일 인증을 위해 호출. 메일이 발송됨.
  @Post('send-otp')
  async sendOtp(@Body() dto: SendOtpDto) {
    const result = await this.emailOtpService.sendOtp(dto.email);
    return { success: true, data: result };
  }

  // ── POST /api/auth/email/verify-otp ──────────────────
  // 사용자가 받은 6자리 코드 검증 → 성공 시 email_verified_at 채움.
  @Post('verify-otp')
  async verifyOtp(@Body() dto: VerifyOtpDto) {
    const result = await this.emailOtpService.verifyOtp(dto.email, dto.code);
    return { success: true, data: result };
  }
}
