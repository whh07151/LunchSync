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
  ///
  /// 스팸 방지 (2026-05-12 박검토A):
  ///   1단계: public.users 에 가입된 이메일만 통과 (미가입 이메일 = BadRequest).
  ///   2단계: shouldCreateUser=false 로 1차 시도 → auth.users 신규 생성 차단.
  ///   3단계: 1차 거절 시 (auth.users 미존재) shouldCreateUser=true 로 1회 재시도.
  ///   임의 이메일에 무한 OTP 발송하는 스팸 도구화 가능성을 1단계에서 사전 차단.
  async sendOtp(email: string): Promise<{ sent: true; email: string }> {
    // 1) public.users 에 해당 이메일이 존재하는지 먼저 확인 — 가입 안 된 사용자
    //    한테 OTP 보내는 건 의미 없음 + 스팸 도구화 차단
    const { data: user } = await this.supabase.client
      .from('users')
      .select('id, email_verified_at')
      .eq('email', email)
      .maybeSingle();

    if (!user) {
      throw new BadRequestException('가입되지 않은 이메일입니다. 먼저 가입해주세요.');
    }

    // 2) Supabase Auth 로 OTP 발송 요청 — 우선 shouldCreateUser=false 시도
    let { error } = await this.supabase.client.auth.signInWithOtp({
      email,
      options: { shouldCreateUser: false },
    });

    // 3) auth.users 에 미존재해서 거절된 경우 → 1회만 신규 생성 허용 후 재시도
    //    public.users 가 1단계에서 검증됐으므로 임의 이메일 자동 생성 위험 없음
    if (error) {
      const result2 = await this.supabase.client.auth.signInWithOtp({
        email,
        options: { shouldCreateUser: true },
      });
      error = result2.error;
    }

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
