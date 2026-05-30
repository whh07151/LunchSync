import { Body, Controller, Param, Post } from '@nestjs/common';
import { IsEmail, IsOptional, IsString } from 'class-validator';
import { Throttle } from '@nestjs/throttler';
import { PosAuthService } from './pos-auth.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: POS 단말 로그인 HTTP 엔드포인트 (LSPOS 연동용)
//
// 엔드포인트:
//   POST /api/pos/login/:restaurantId  — 식당 고유번호로 POS JWT 발급
//
// 인증:
//   본 엔드포인트는 인증 없이 호출됨 (단말 로그인 시점 자체이므로).
//   전체 글로벌 가드를 쓰지 않으므로 JwtAuthGuard 적용 불필요.
// ══════════════════════════════════════════════════════════

class PosLoginDto {
  /// 단말 식별 라벨 (예: "카운터1", "주방POS") — 선택. 운영 로그용
  @IsOptional() @IsString() terminalName?: string;

  /// POS 단말 PIN (2026-05-12 추가) — 환경변수 POS_PIN 설정 시 필수 검증.
  /// 시드 매장 UUID 가 노출되어도 PIN 모르면 토큰 발급 불가.
  @IsOptional() @IsString() pin?: string;
}

class PosOwnerLoginDto {
  @IsEmail() email: string;
  @IsString() password: string;
}

@Controller('pos')
export class PosAuthController {
  constructor(private readonly posAuthService: PosAuthService) {}

  // ── POS 단말 로그인 ────────────────────────────────────
  // restaurantId 가 유효하면 type=POS JWT 발급. LSPOS 의 useAuth 가
  // localStorage 에 accessToken 저장 → client.ts 가 Bearer 헤더 자동 주입.
  //
  // 부르트포스 차단 (2026-05-12): IP 당 분당 5회 제한.
  // 시드 매장 UUID 패턴(11111111-...) 노출 시에도 자동 시도 차단.
  // 2026-05-30 회귀 수정: 'auth' 명명 throttler 가 전역적용 회귀를 일으켜
  // 전 API 가 429 로 막힘. default 오버라이드로 같은 분당 30회 한도 유지.
  // (다연님 23ef22c 패치 백포팅 — 결제/주문/폴링 정상화 핵심)
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @Post('login/:restaurantId')
  async login(
    @Param('restaurantId') restaurantId: string,
    @Body() dto: PosLoginDto,
  ) {
    const result = await this.posAuthService.login(
      restaurantId,
      dto.terminalName,
      dto.pin,
    );
    return { success: true, data: result };
  }

  // ── 사장 계정(이메일+비번)으로 LSPOS 로그인 ───────────
  // 식당 고유번호 없이 사장이 자신의 계정으로 바로 로그인.
  // 응답: { userToken, restaurant? } — 식당 미등록 시 restaurant=null
  // 2026-05-30 회귀 수정: 'auth' 명명 throttler 가 전역적용 회귀를 일으켜
  // 전 API 가 429 로 막힘. default 오버라이드로 같은 분당 30회 한도 유지.
  // (다연님 23ef22c 패치 백포팅 — 결제/주문/폴링 정상화 핵심)
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @Post('login-owner')
  async loginOwner(@Body() dto: PosOwnerLoginDto) {
    const result = await this.posAuthService.loginOwner(dto.email, dto.password);
    return { success: true, data: result };
  }
}
