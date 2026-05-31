// ══════════════════════════════════════════════════════════
// 파일 역할: 개발/테스트 전용 우회 라우트 (보안 게이트 포함)
//
// 배경:
//   사장(OWNER) 모드 통합 테스트(모바일/웹/POS 연동)는 OWNER 계정
//   + status=APPROVED + restaurant_id 매핑이 필요하다. 정식 흐름은
//   회원가입 → 사업자 정보 입력 → 관리자 승인 단계라 자동화/QA 가
//   매번 SQL 한 줄에 의존해야 했음.
//
// 이 모듈은 그 의존을 자동화한다 — 단, 보안 게이트가 핵심:
//   1) JwtAuthGuard 가 본인 JWT 검증 (다른 사용자 promote 불가)
//   2) DEV_PROMOTE_ENABLED 환경변수 명시적으로 'true' 일 때만 활성
//      (production EC2 에 이 변수가 없으면 401 으로 즉시 차단됨)
//   3) 로그에 promote 한 user/restaurant 명시 — 흔적 보존
//
// 사용 패턴 (자동 QA):
//   - 손님으로 로그인 → 이 라우트 호출 → 토큰은 그대로 두고 role 만 OWNER
//   - 앱 재진입 시 _RootNavigator 가 GET /api/users/me 응답으로 role 감지
//     → OwnerHomeScreen 자동 진입
// ══════════════════════════════════════════════════════════

import {
  Body,
  Controller,
  ForbiddenException,
  Logger,
  NotFoundException,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { IsIn, IsOptional, IsString, IsUUID } from 'class-validator';
import { JwtService } from '@nestjs/jwt';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SupabaseService } from '../supabase/supabase.service';

// 2026-05-31 시연 셋업: 3화면(폰 손님 + web 사장 + POS) 동시 시연 시 같은 카카오
// 계정으로 폰/web 둘 다 진입하면 role 토글이 양쪽에 동시 영향이라 시연이 망가짐.
// 시드 사용자(이메일 가입형)의 JWT 를 즉시 발급해서 web 만 다른 계정으로 띄울 수
// 있게 한다. 운영용 가드 동일 — DEV_PROMOTE_ENABLED=true 일 때만 활성.
class LoginAsSeedDto {
  // 2026-05-31 fix: 실제 DB 시드 5명(minjun/jihyo/dayeon/taehwan/seoyeon)과 일치.
  // hyunho_owner 는 카카오 가입자라 별도 이메일이 없어 제외 — 시연 사장은
  // dev/promote-to-owner 로 직접 토글하는 방법 안내.
  @IsString()
  @IsIn([
    'minjun_customer',
    'jihyo_customer',
    'dayeon_customer',
    'taehwan_customer',
    'seoyeon_customer',
  ])
  seedKey!: string;
}

class PromoteToOwnerDto {
  /// 매핑할 식당 UUID. 미지정 시 사용자가 마지막에 결제한 식당 자동 매핑.
  @IsOptional() @IsUUID() restaurantId?: string;

  /// 기본은 OWNER. 'CUSTOMER' 전달 시 원복용으로 사용 가능.
  @IsOptional() @IsString() role?: 'OWNER' | 'CUSTOMER';
}

// 시연용 시드 사용자 매핑 (이메일은 실제 DB 시드 데이터와 1:1 일치)
const SEED_USER_MAP: Record<string, { email: string; expectedRole: 'OWNER' | 'CUSTOMER' }> = {
  minjun_customer: { email: 'demo.minjun@lunchsync.test', expectedRole: 'CUSTOMER' },
  jihyo_customer: { email: 'demo.jihyo@lunchsync.test', expectedRole: 'CUSTOMER' },
  dayeon_customer: { email: 'demo.dayeon@lunchsync.test', expectedRole: 'CUSTOMER' },
  taehwan_customer: { email: 'demo.taehwan@lunchsync.test', expectedRole: 'CUSTOMER' },
  seoyeon_customer: { email: 'demo.seoyeon@lunchsync.test', expectedRole: 'CUSTOMER' },
};

@Controller('dev')
export class DevController {
  private readonly logger = new Logger(DevController.name);

  constructor(
    private readonly supabase: SupabaseService,
    private readonly jwtService: JwtService,
  ) {}

  // ── POST /api/dev/promote-to-owner ────────────────────
  // 본인 JWT 로 자기 자신의 role/status/restaurant_id 를 변경한다.
  // DEV_PROMOTE_ENABLED=true 가 명시되지 않으면 ForbiddenException.
  @UseGuards(JwtAuthGuard)
  @Post('promote-to-owner')
  async promoteToOwner(
    @Req() req: { user: { userId: string } },
    @Body() dto: PromoteToOwnerDto,
  ) {
    if (process.env.DEV_PROMOTE_ENABLED !== 'true') {
      throw new ForbiddenException(
        'dev promote 라우트가 비활성 상태입니다. EC2 .env 에 DEV_PROMOTE_ENABLED=true 추가 후 재시작하세요.',
      );
    }

    const userId = req.user.userId;
    const targetRole = dto.role ?? 'OWNER';

    // restaurant_id 결정:
    //   - 명시값 우선 (테스트 컨트롤)
    //   - 미지정 시 마지막 PAID 주문의 식당으로 자동 매핑 (검증 흐름 자연화)
    //   - 둘 다 없으면 null (CUSTOMER 원복 시)
    let restaurantId: string | null = dto.restaurantId ?? null;
    if (targetRole === 'OWNER' && !restaurantId) {
      const { data: last } = await this.supabase.client
        .from('orders')
        .select('restaurant_id')
        .eq('user_id', userId)
        .eq('status', 'PAID')
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      restaurantId = last?.restaurant_id ?? null;
    }

    const { data, error } = await this.supabase.client
      .from('users')
      .update({
        role: targetRole,
        status: 'APPROVED',
        restaurant_id: targetRole === 'OWNER' ? restaurantId : null,
      })
      .eq('id', userId)
      .select('id, role, status, restaurant_id, name')
      .single();

    if (error || !data) {
      this.logger.error(`[dev] promote 실패: ${error?.message}`);
      throw new ForbiddenException('promote 실패: ' + (error?.message ?? '응답 없음'));
    }

    this.logger.warn(
      `[dev] promote user=${data.id} (${data.name}) → role=${data.role} restaurant_id=${data.restaurant_id ?? 'null'}`,
    );

    return { success: true, data };
  }

  // ── POST /api/dev/login-as-seed ────────────────────────
  // 시연용: 시드 사용자의 JWT 를 발급한다. 폰=hyunho 손님, web=다른 시드 사장
  // 같은 분리 시연이 필요한 경우 활용. DEV_PROMOTE_ENABLED 미설정 시 즉시 거절.
  @Post('login-as-seed')
  async loginAsSeed(@Body() dto: LoginAsSeedDto) {
    if (process.env.DEV_PROMOTE_ENABLED !== 'true') {
      throw new ForbiddenException(
        'dev 라우트 비활성. EC2 .env 에 DEV_PROMOTE_ENABLED=true 추가 후 재시작 필요.',
      );
    }

    const meta = SEED_USER_MAP[dto.seedKey];
    if (!meta) {
      throw new NotFoundException('알 수 없는 seedKey 입니다.');
    }

    const { data: user, error } = await this.supabase.client
      .from('users')
      .select('id, name, email, role, status, restaurant_id')
      .eq('email', meta.email)
      .maybeSingle();

    if (error || !user) {
      throw new NotFoundException(
        `시드 사용자(${meta.email}) 미존재. 시드 마이그레이션 필요.`,
      );
    }

    // 일반 카카오/이메일 로그인과 동일한 페이로드 — JwtAuthGuard 가 그대로 수용.
    const accessToken = this.jwtService.sign({ sub: user.id });

    this.logger.warn(
      `[dev] login-as-seed key=${dto.seedKey} user=${user.id} (${user.name}) role=${user.role}`,
    );

    return {
      success: true,
      data: {
        accessToken,
        userId: user.id,
        name: user.name,
        role: user.role,
        status: user.status,
        restaurantId: user.restaurant_id,
      },
    };
  }
}
