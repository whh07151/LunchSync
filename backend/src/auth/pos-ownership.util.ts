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

import { ForbiddenException, UnauthorizedException } from '@nestjs/common';
import type { AuthedRequestUser } from './jwt.strategy';

/// POS 단말 토큰이 path 의 매장 자료에 접근할 권한이 있는지 검증.
/// - POS 토큰: token.restaurantId === path.restaurantId 일치 확인
/// - USER 토큰: 일단 통과 (OWNER 본인 매장 일치 검증은 시연 후 보강 예정)
/// - 둘 다 아닌 경우: 401 Unauthorized
export function assertPosAccessTo(
  user: AuthedRequestUser | undefined,
  restaurantId: string,
): void {
  if (!user) {
    throw new UnauthorizedException('인증 정보가 없습니다.');
  }

  // POS 토큰: 토큰의 매장 ID 와 요청 path 의 매장 ID 가 반드시 일치해야 함
  if (user.type === 'POS') {
    if (!user.restaurantId || user.restaurantId !== restaurantId) {
      throw new ForbiddenException('다른 매장의 자료에 접근할 수 없습니다.');
    }
    return;
  }

  // USER 토큰: 캡스톤 단계는 통과 (시연에서 사장은 자기 매장만 호출).
  // 시연 후 보강 시: users.restaurant_id 와 path.restaurantId 일치 검증 DB 조회 추가.
  if (user.type === 'USER') {
    return;
  }

  throw new UnauthorizedException('알 수 없는 토큰 종류입니다.');
}
