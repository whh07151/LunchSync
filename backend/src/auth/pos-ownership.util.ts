// ══════════════════════════════════════════════════════════
// 파일 역할: POS/사장 권한 검증 헬퍼 유틸리티
//
// 배경 (2026-05-12 박검토A 지적):
//   pos.controller / pos-menus / pos-seats / pos-reservations 의 path 에
//   `:restaurantId` 가 들어있는 모든 메서드가 토큰 안의 restaurantId 와
//   path 의 restaurantId 일치 검증이 없었음. → 임의 매장 자료 조회/조작 가능.
//
// 처리 방침 (캡스톤 단계):
//   POS 토큰: payload.sub == restaurantId 이므로 token.restaurantId === path 확인.
//   USER 토큰: 일단 통과. 시연에서 사장은 자기 매장 restaurantId 로만 호출.
//   (USER 토큰 OWNER 자기매장 일치 검증은 시연 후 보강 — DB 조회 1회 추가됨)
//
// 사용처:
//   pos.controller       — Get/Patch/Post 의 :restaurantId 가 있는 메서드
//   pos-menus.controller — list/create 의 :restaurantId
//   pos-seats.controller — 동일
//   pos-reservations.controller — 동일
// ══════════════════════════════════════════════════════════

import {
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { AuthedRequestUser } from './jwt.strategy';
import { SupabaseService } from '../supabase/supabase.service';
import { ConfigService } from '@nestjs/config';

/// POS/점주 권한은 토큰 종류만으로 추정하지 않고 매 요청에서 서버 데이터로 확인한다.
/// service-role Supabase 클라이언트가 RLS를 우회하므로 이 검사가 실제 권한 경계다.
@Injectable()
export class PosAccessService {
  constructor(
    private readonly supabase: SupabaseService,
    private readonly config: ConfigService,
  ) {}

  async assertAccessTo(
    user: AuthedRequestUser | undefined,
    restaurantId: string,
  ): Promise<void> {
    if (!user) {
      throw new UnauthorizedException('인증 정보가 없습니다.');
    }

    if (user.type === 'POS') {
      if (!user.restaurantId || user.restaurantId !== restaurantId) {
        throw new ForbiddenException('다른 매장의 자료에 접근할 수 없습니다.');
      }

      if (user.authMode === 'SHARED_PIN') {
        const nodeEnv =
          this.config.get<string>('NODE_ENV') ?? process.env.NODE_ENV;
        const enabled =
          this.config.get<string>('POS_SHARED_PIN_LOGIN_ENABLED') === 'true';
        if (nodeEnv === 'production' || !enabled) {
          throw new ForbiddenException(
            '공용 PIN POS 세션이 비활성 상태입니다.',
          );
        }
        return;
      }

      if (user.authMode !== 'OWNER' || !user.ownerUserId) {
        throw new ForbiddenException('POS 세션을 다시 인증해주세요.');
      }

      await this.assertApprovedOwner(user.ownerUserId);
      const { data: restaurant, error } = await this.supabase.client
        .from('restaurants')
        .select('id, owner_user_id')
        .eq('id', restaurantId)
        .maybeSingle();
      if (error || restaurant?.owner_user_id !== user.ownerUserId) {
        throw new ForbiddenException(
          'POS 매장 권한이 더 이상 유효하지 않습니다.',
        );
      }
      return;
    }

    if (user.type !== 'USER' || !user.userId) {
      throw new UnauthorizedException('알 수 없는 토큰 종류입니다.');
    }

    const owner = await this.assertApprovedOwner(user.userId);

    const { data: restaurant, error } = await this.supabase.client
      .from('restaurants')
      .select('id, owner_user_id')
      .eq('id', restaurantId)
      .maybeSingle();

    if (error || !restaurant) {
      throw new ForbiddenException('다른 매장의 자료에 접근할 수 없습니다.');
    }

    if (restaurant.owner_user_id === user.userId) return;

    const canUseLegacyMapping =
      restaurant.owner_user_id == null && owner.restaurantId === restaurantId;
    if (!canUseLegacyMapping) {
      throw new ForbiddenException('다른 매장의 자료에 접근할 수 없습니다.');
    }

    // canonical 매장을 하나라도 가진 사용자는 legacy users.restaurant_id를
    // 동시에 사용할 수 없다. 두 소유권 소스가 합쳐져 다중 매장 권한이 되는 것을 차단한다.
    const { data: canonicalRestaurant, error: canonicalLookupError } =
      await this.supabase.client
        .from('restaurants')
        .select('id')
        .eq('owner_user_id', user.userId)
        .maybeSingle();
    if (canonicalLookupError || canonicalRestaurant) {
      throw new ForbiddenException('다른 매장의 자료에 접근할 수 없습니다.');
    }

    // 과거 users.restaurant_id 값이 여러 계정에 중복돼 있으면 어느 한쪽도
    // 먼저 접근했다는 이유만으로 canonical 소유권을 가져가면 안 된다.
    const { data: competingLegacyOwner, error: legacyMappingError } =
      await this.supabase.client
        .from('users')
        .select('id')
        .eq('restaurant_id', restaurantId)
        .neq('id', user.userId)
        .limit(1)
        .maybeSingle();
    if (legacyMappingError || competingLegacyOwner) {
      throw new ForbiddenException('매장 소유권 매핑을 확인할 수 없습니다.');
    }

    const { data: claimedRestaurant, error: claimError } =
      await this.supabase.client
        .from('restaurants')
        .update({ owner_user_id: user.userId })
        .eq('id', restaurantId)
        .is('owner_user_id', null)
        .select('id, owner_user_id')
        .maybeSingle();
    if (
      claimError ||
      !claimedRestaurant ||
      claimedRestaurant.owner_user_id !== user.userId
    ) {
      throw new ForbiddenException('다른 매장의 자료에 접근할 수 없습니다.');
    }
  }

  async assertApprovedOwner(
    userId: string,
  ): Promise<{ restaurantId: string | null }> {
    const { data: user, error } = await this.supabase.client
      .from('users')
      .select('role, status, restaurant_id')
      .eq('id', userId)
      .maybeSingle();

    if (error || !user || user.role !== 'OWNER' || user.status !== 'APPROVED') {
      throw new ForbiddenException('승인된 사장 계정만 접근할 수 있습니다.');
    }

    return { restaurantId: user.restaurant_id ?? null };
  }
}
