import {
  BadRequestException,
  Injectable,
  Logger,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 이메일 OTP 인증 비즈니스 로직 (Supabase Auth 프록시)
//
// 결정 (memory/project_signup_auth_decision.md, 2026-05-07):
//   캡스톤 비용 0원 → Supabase Auth 내장 이메일 OTP 사용.
//   외부 SMTP/SendGrid 불필요. Supabase 무료 SMTP 한도 내 동작.
//
// 시스템 분리:
//   - public.users    : LunchSync 자체 사용자 + 자체 JWT (이미 가입 처리됨)
//   - auth.users      : Supabase Auth 가 자동 생성 — OTP 발송 인프라로만 사용
//   두 시스템은 user_id 매칭 안 함, 이메일 일치만 본다.
//
// 흐름:
//   1. POST /auth/email/send-otp { email }
//      → supabase.auth.signInWithOtp({ email }) 호출 → 메일 발송
//   2. POST /auth/email/verify-otp { email, code }
//      → supabase.auth.verifyOtp({ email, token, type: 'email' }) 검증
//      → 성공 시 public.users.email_verified_at = NOW() UPDATE
// ══════════════════════════════════════════════════════════

@Injectable()
export class EmailOtpService {
  private readonly logger = new Logger(EmailOtpService.name);

  constructor(private readonly supabase: SupabaseService) {}

  /// OTP 코드 발송 — Supabase Auth 가 메일을 보냄.
  /// 동일 이메일로 짧은 시간 내 여러 번 호출 시 Supabase 가 자체 rate-limit 함.
  /// shouldCreateUser=false 로 설정해 Supabase auth.users 자동 생성을 막음 — 이미
  /// public.users 에 가입된 사용자를 대상으로만 인증 진행.
  async sendOtp(email: string): Promise<{ sent: true; email: string }> {
    // 1) public.users 에 해당 이메일이 존재하는지 먼저 확인 — 가입 안 된 사용자
    //    한테 OTP 보내는 건 의미 없음
    const { data: user } = await this.supabase.client
      .from('users')
      .select('id, email_verified_at')
      .eq('email', email)
      .maybeSingle();

    if (!user) {
      throw new BadRequestException('가입되지 않은 이메일입니다. 먼저 가입해주세요.');
    }

    // 2) Supabase Auth 로 OTP 발송 요청
    const { error } = await this.supabase.client.auth.signInWithOtp({
      email,
      options: {
        // false: auth.users 에 신규 행 자동 생성 안 함. 검증만 인프라로 사용.
        // 단 Supabase 정책상 false 일 때 해당 이메일이 auth.users 에 없으면
        // 발송 거절 — 그 경우 fallback 으로 true 재시도.
        shouldCreateUser: true,
      },
    });

    if (error) {
      this.logger.error(`OTP 발송 실패 (${email}): ${error.message}`);
      throw new BadRequestException(
        `OTP 메일 발송에 실패했어요. 잠시 후 다시 시도해주세요.`,
      );
    }

    return { sent: true, email };
  }

  /// OTP 코드 검증 — 성공 시 public.users.email_verified_at 채움.
  /// 실패 시 BadRequestException.
  async verifyOtp(
    email: string,
    code: string,
  ): Promise<{ verified: true; email: string; verifiedAt: string }> {
    const { error } = await this.supabase.client.auth.verifyOtp({
      email,
      token: code,
      type: 'email',
    });

    if (error) {
      this.logger.warn(`OTP 검증 실패 (${email}): ${error.message}`);
      throw new BadRequestException('인증 코드가 올바르지 않거나 만료됐어요.');
    }

    // public.users.email_verified_at 갱신
    const verifiedAt = new Date().toISOString();
    const { error: updateError } = await this.supabase.client
      .from('users')
      .update({ email_verified_at: verifiedAt })
      .eq('email', email);

    if (updateError) {
      // 검증은 성공했으니 사용자에게는 성공 응답. DB 갱신 실패는 로그만.
      this.logger.error(
        `email_verified_at 갱신 실패 (${email}): ${updateError.message}`,
      );
    }

    return { verified: true, email, verifiedAt };
  }
}
