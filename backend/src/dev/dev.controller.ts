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
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { IsOptional, IsString, IsUUID } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SupabaseService } from '../supabase/supabase.service';

class PromoteToOwnerDto {
  /// 매핑할 식당 UUID. 미지정 시 사용자가 마지막에 결제한 식당 자동 매핑.
  @IsOptional() @IsUUID() restaurantId?: string;

  /// 기본은 OWNER. 'CUSTOMER' 전달 시 원복용으로 사용 가능.
  @IsOptional() @IsString() role?: 'OWNER' | 'CUSTOMER';
}

@Controller('dev')
export class DevController {
  private readonly logger = new Logger(DevController.name);

  constructor(private readonly supabase: SupabaseService) {}

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
}
