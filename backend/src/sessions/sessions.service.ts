import {
  Injectable,
  InternalServerErrorException,
  NotFoundException,
  ConflictException,
  ForbiddenException,
  BadRequestException,
  UnauthorizedException,
  Logger,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 점심 세션 비즈니스 로직
//
// 세션이란?
//   "오늘 점심 같이 먹자" 한 번의 이벤트.
//   세션 생성 → 멤버 초대 → 추천 → 투표 → 확정 → 주문 흐름의 시작점.
//
// 상태 전이 (보안 에이전트 권장 — 잘못된 전이 거부):
//   WAITING → VOTING
//   VOTING  → ORDERED | WAITING (투표 취소)
//   ORDERED → DONE
//   DONE    → (terminal — 변경 불가)
//
// 권한 정책 (보안 Critical):
//   - updateSessionStatus / addMember / removeMember(타인) — 호스트만
//   - removeMember(자기 자신) — 누구나 (세션 나가기)
// ══════════════════════════════════════════════════════════

// 허용된 상태 전이 매트릭스 — Critical 보안 패치 (2026-05-11)
const VALID_SESSION_TRANSITIONS: Record<string, ReadonlyArray<string>> = {
  WAITING: ['VOTING'],
  VOTING: ['ORDERED', 'WAITING'],
  ORDERED: ['DONE'],
  DONE: [],
};

export interface CreateSessionDto {
  name: string;
  scheduledAt?: string;
  radius?: number;
  budget?: number;
  returnMinutes?: number;
  memo?: string;
  lat?: number;
  lng?: number;
}

export interface UpdateSessionStatusDto {
  status: string;
}

export interface AddMemberDto {
  userId: string;
}

@Injectable()
export class SessionsService {
  private readonly logger = new Logger(SessionsService.name);

  constructor(private readonly supabase: SupabaseService) {}

  private statusLabel(status: string): string {
    const map: Record<string, string> = {
      WAITING: '대기 중',
      VOTING: '투표 중',
      ORDERED: '주문 완료',
      DONE: '세션 종료',
    };
    return map[status] ?? status;
  }

  // ── 내부 헬퍼: 세션 호스트 검증 ─────────────────────────
  // 권한 검증이 필요한 모든 변이 메서드(상태 변경/멤버 추가 등) 진입점에서 호출.
  // 본인이 호스트가 아니면 403 ForbiddenException.
  //
  // 2026-05-13 견고화:
  //   - userId 가 falsy(POS 토큰/잘못된 JWT 등) 면 즉시 401.
  //     기존엔 undefined !== <uuid> 비교로 무조건 403 이 떴는데, 이게 호스트인
  //     실사용자가 "호스트만 시작할 수 있어요" 토스트를 보는 핵심 원인이었음.
  //   - String/trim 으로 비교 — UUID 양끝 공백/대소문자 차이로 인한 오탐 차단.
  //   - 비교 실패 시 디버그 로그(host vs requester) 로 향후 원인 추적 용이.
  private async assertHost(
    sessionId: string,
    userId: string | undefined,
  ): Promise<void> {
    // 0단계: JWT payload 에서 userId 가 빠진 경우(POS 토큰 등) 명확한 401 반환.
    //   기존 코드는 undefined !== <hostId> 로 무조건 403 을 던졌고, 사용자에겐
    //   "호스트만 시작할 수 있어요" 메시지가 떠서 진짜 원인(미인증)을 가렸음.
    if (!userId) {
      throw new UnauthorizedException(
        '사용자 인증 정보가 없습니다. 다시 로그인해주세요.',
      );
    }

    const { data, error } = await this.supabase.client
      .from('sessions')
      .select('created_by')
      .eq('id', sessionId)
      .single();

    if (error || !data) {
      throw new NotFoundException('세션을 찾을 수 없습니다.');
    }

    // UUID 양끝 공백 등 잠재 이질감 제거 후 비교.
    // PostgreSQL UUID 컬럼은 일반적으로 정규화된 소문자 string 으로 직렬화되지만
    // 외부 시드/스크립트가 다른 표기를 박았을 가능성을 방어.
    const hostId = String(data.created_by ?? '').trim().toLowerCase();
    const requesterId = String(userId).trim().toLowerCase();

    if (hostId !== requesterId) {
      this.logger.warn('SESSION_HOST_AUTHORIZATION_DENIED');
      throw new ForbiddenException('세션 호스트만 가능한 작업이에요.');
    }
  }

  // ── POST /sessions ────────────────────────────────────
  // 트랜잭션 보장 (2026-05-14):
  //   create_session_with_host_member RPC 사용 — sessions + session_members
  //   INSERT 가 PostgreSQL 함수 단일 트랜잭션으로 묶임.
  //   중간 실패 시 전체 롤백 → "세션만 남고 호스트 미멤버" 정합성 버그 차단.
  //
  // 2026-05-13 견고화:
  //   userId 가 falsy 면 RPC 에 NULL 이 들어가 sessions.created_by NOT NULL 위반.
  //   사전에 401 로 차단해 의미 없는 INSERT 실패 로그를 줄임.
  async createSession(userId: string | undefined, dto: CreateSessionDto) {
    if (!userId) {
      throw new UnauthorizedException(
        '사용자 인증 정보가 없습니다. 다시 로그인해주세요.',
      );
    }
    const { data, error } = await this.supabase.client.rpc(
      'create_session_with_host_member',
      {
        p_name: dto.name,
        p_created_by: userId,
        p_scheduled_at: dto.scheduledAt ?? null,
        p_radius: dto.radius ?? null,
        p_budget: dto.budget ?? null,
        p_return_minutes: dto.returnMinutes ?? null,
        p_memo: dto.memo ?? null,
        p_lat: dto.lat ?? null,
        p_lng: dto.lng ?? null,
      },
    );

    if (error || !data) {
      this.logger.error('SESSION_CREATE_PERSIST_FAILED');
      throw new InternalServerErrorException(
        '세션을 만들지 못했어요. 잠시 후 다시 시도해주세요.',
      );
    }

    // RPC가 이미 camelCase JSON 응답을 반환하므로 그대로 사용
    return data;
  }

  // ── GET /sessions/today ───────────────────────────────
  async getTodaySessions(userId: string | undefined) {
    if (!userId) {
      throw new UnauthorizedException(
        '사용자 인증 정보가 없습니다. 다시 로그인해주세요.',
      );
    }
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayISO = today.toISOString();

    const { data: myMemberships } = await this.supabase.client
      .from('session_members')
      .select('session_id')
      .eq('user_id', userId);

    const sessionIds = myMemberships?.map((m) => m.session_id) ?? [];
    if (sessionIds.length === 0) return [];

    // 2026-05-14 추가: budget/radius/return_minutes/memo 포함
    //   사장님 시연 발견 — 홈에서 로비 진입 시 정보 박스(예산·반경·복귀)가 안 보였음.
    //   원인: getTodaySessions select에 위 필드 누락 → Session 객체가 null 박스라
    //   _buildConditionChips가 칩을 0개 그림.
    const { data: sessions } = await this.supabase.client
      .from('sessions')
      .select('id, name, status, created_by, scheduled_at, created_at, radius, budget, return_minutes, memo')
      .in('id', sessionIds)
      .gte('created_at', todayISO)
      .order('created_at', { ascending: false });

    if (!sessions || sessions.length === 0) return [];

    const { data: allMembers } = await this.supabase.client
      .from('session_members')
      .select('session_id')
      .in('session_id', sessions.map((s) => s.id));

    const memberCountMap: Record<string, number> = {};
    (allMembers ?? []).forEach((m) => {
      memberCountMap[m.session_id] = (memberCountMap[m.session_id] ?? 0) + 1;
    });

    const creatorIds = [...new Set(sessions.map((s) => s.created_by))];
    const { data: creators } = await this.supabase.client
      .from('users')
      .select('id, name')
      .in('id', creatorIds);

    const creatorMap: Record<string, string> = {};
    (creators ?? []).forEach((u) => {
      creatorMap[u.id] = u.name;
    });

    return sessions.map((s) => ({
      id: s.id,
      name: s.name,
      status: s.status,
      statusLabel: this.statusLabel(s.status),
      scheduledAt: s.scheduled_at,
      memberCount: memberCountMap[s.id] ?? 0,
      createdBy: { id: s.created_by, name: creatorMap[s.created_by] ?? null },
      // 2026-05-14 추가 — 로비 정보 박스용
      radius: s.radius,
      budget: s.budget,
      returnMinutes: s.return_minutes,
      memo: s.memo,
    }));
  }

  // ── GET /sessions/:id ─────────────────────────────────
  async getSessionById(sessionId: string) {
    const { data, error } = await this.supabase.client
      .from('sessions')
      .select(
        'id, name, status, created_by, winner_restaurant_id, scheduled_at, radius, budget, return_minutes, memo, lat, lng, created_at',
      )
      .eq('id', sessionId)
      .single();

    if (error || !data) {
      throw new NotFoundException('세션을 찾을 수 없습니다.');
    }

    const { data: creator } = await this.supabase.client
      .from('users')
      .select('id, name')
      .eq('id', data.created_by)
      .single();

    return {
      id: data.id,
      name: data.name,
      status: data.status,
      winnerRestaurantId: data.winner_restaurant_id,
      scheduledAt: data.scheduled_at,
      radius: data.radius,
      budget: data.budget,
      returnMinutes: data.return_minutes,
      memo: data.memo,
      lat: data.lat,
      lng: data.lng,
      createdAt: data.created_at,
      createdBy: creator
        ? { id: creator.id, name: creator.name }
        : { id: data.created_by, name: null },
    };
  }

  // ── PATCH /sessions/:id/status ────────────────────────
  // 보안 패치 (2026-05-11):
  //   1) 호스트 검증 (assertHost)
  //   2) 상태 전이 매트릭스 검증 (역방향/jumping 거부)
  async updateSessionStatus(
    sessionId: string,
    requesterId: string | undefined,
    dto: UpdateSessionStatusDto,
  ) {
    await this.assertHost(sessionId, requesterId);

    // 현재 상태 조회 후 전이 매트릭스 검증
    const { data: current, error: fetchError } = await this.supabase.client
      .from('sessions')
      .select('status')
      .eq('id', sessionId)
      .single();
    if (fetchError || !current) {
      throw new NotFoundException('세션을 찾을 수 없습니다.');
    }

    const allowed = VALID_SESSION_TRANSITIONS[current.status] ?? [];
    if (!allowed.includes(dto.status)) {
      throw new BadRequestException(
        `${current.status} 상태에서 ${dto.status} 로는 전환할 수 없어요.`,
      );
    }

    const { data, error } = await this.supabase.client
      .from('sessions')
      .update({ status: dto.status })
      .eq('id', sessionId)
      .select('id, name, status')
      .single();

    if (error || !data) {
      this.logger.error('SESSION_STATUS_UPDATE_PERSIST_FAILED');
      throw new InternalServerErrorException('세션 상태를 변경하지 못했어요.');
    }

    return { id: data.id, name: data.name, status: data.status };
  }

  // ── GET /sessions/:id/members ─────────────────────────
  async getSessionMembers(sessionId: string) {
    const { data: session } = await this.supabase.client
      .from('sessions')
      .select('created_by')
      .eq('id', sessionId)
      .single();

    const hostId = session?.created_by;

    const { data, error } = await this.supabase.client
      .from('session_members')
      .select('user_id, joined_at, users(id, name, profile_image, org)')
      .eq('session_id', sessionId);

    if (error) {
      this.logger.error('SESSION_MEMBER_LIST_PERSIST_FAILED');
      throw new InternalServerErrorException('멤버를 불러오지 못했어요.');
    }

    const members = (data ?? []).map((m: any) => ({
      id: m.user_id,
      name: m.users?.name,
      profileImage: m.users?.profile_image,
      org: m.users?.org,
      isHost: m.user_id === hostId,
      joinedAt: m.joined_at,
    }));

    return {
      totalCount: members.length,
      joinedCount: members.length,
      members,
    };
  }

  // ── POST /sessions/:id/members ────────────────────────
  // 보안 패치: 호스트만 멤버 추가 가능 + WAITING 상태에서만
  async addMember(
    sessionId: string,
    requesterId: string | undefined,
    dto: AddMemberDto,
  ) {
    await this.assertHost(sessionId, requesterId);
    return this.addMemberInternal(sessionId, dto.userId, {
      enforceWaiting: true,
    });
  }

  // ── 내부 전용: 초대코드 수락 등 다른 모듈이 호출 ────────
  // 호스트 검증을 건너뜀. 초대 코드 검증이 권한 게이트키 역할.
  // - InvitationsService 가 코드 검증 후 호출하는 진입점
  // - WAITING 상태에서만 추가 허용 (enforceWaiting 기본 true)
  async addMemberInternal(
    sessionId: string,
    userId: string,
    options: { enforceWaiting?: boolean } = {},
  ) {
    const enforceWaiting = options.enforceWaiting ?? true;

    if (enforceWaiting) {
      const { data: session } = await this.supabase.client
        .from('sessions')
        .select('status')
        .eq('id', sessionId)
        .single();
      if (session && session.status !== 'WAITING') {
        throw new ConflictException(
          '투표가 시작된 세션엔 참가할 수 없어요.',
        );
      }
    }

    const { error } = await this.supabase.client
      .from('session_members')
      .insert({ session_id: sessionId, user_id: userId });

    if (error) {
      if (error.code === '23505') {
        throw new ConflictException('이미 세션에 참가한 멤버예요.');
      }
      this.logger.error('SESSION_MEMBER_ADD_PERSIST_FAILED');
      throw new InternalServerErrorException('멤버를 추가하지 못했어요.');
    }

    return { success: true };
  }

  // ── DELETE /sessions/:id ──────────────────────────────
  // 사장님 시연 피드백(2026-05-13) 반영:
  //   "만든 세션 삭제도 가능하게 만들고싶고" — 잘못 만든 세션을 청소할 수 있게.
  //
  // 권한 정책:
  //   - 호스트만 삭제 가능 (assertHost)
  //   - WAITING / DONE 상태만 삭제 허용
  //     (VOTING/ORDERED 는 다른 멤버에게 영향이 커 차단)
  //
  // 트랜잭션 안전성:
  //   delete_session_cascade RPC 사용 — order_items / orders / votes /
  //   session_members / sessions 다섯 테이블 DELETE 가 PostgreSQL 함수
  //   단일 트랜잭션으로 묶임. 중간 실패 시 전체 롤백.
  //
  // RPC 내부에서도 status 를 재확인 — race condition 최후 방어선.
  async deleteSession(
    sessionId: string,
    requesterId: string | undefined,
  ): Promise<{ deletedSessionId: string; deletedAt: string }> {
    // 1) 호스트 검증 (assertHost 내부에서 userId falsy → 401, 호스트 불일치 → 403)
    await this.assertHost(sessionId, requesterId);

    // 2) 현재 상태 조회 후 화이트리스트 검증 (사용자 친화 메시지를 미리 던지기 위해)
    //    RPC 안에서도 동일하게 막지만, 여기서 먼저 잡으면 400 + 한국어 메시지 응답이 가능.
    const { data: current, error: fetchError } = await this.supabase.client
      .from('sessions')
      .select('status')
      .eq('id', sessionId)
      .single();

    if (fetchError || !current) {
      throw new NotFoundException('세션을 찾을 수 없습니다.');
    }

    const deletableStatuses = ['WAITING', 'DONE'];
    if (!deletableStatuses.includes(current.status)) {
      // VOTING / ORDERED 중에는 멤버들이 이미 참여하고 있어 삭제 차단.
      // 한국어 안내로 다음 액션(투표 종료 후 다시 시도) 유도.
      throw new BadRequestException(
        '투표/주문이 진행 중인 세션은 삭제할 수 없어요. 세션을 종료한 뒤 다시 시도해주세요.',
      );
    }

    // 3) RPC 호출 — 다섯 테이블 cascade 삭제를 트랜잭션으로 묶음.
    const { data, error } = await this.supabase.client.rpc(
      'delete_session_cascade',
      { p_session_id: sessionId },
    );

    if (error) {
      // RPC 가 RAISE EXCEPTION 으로 던지는 SESSION_NOT_DELETABLE 은 race condition 보호용.
      // 메시지 패턴 매칭으로 사용자 친화 응답으로 변환.
      const message = error.message ?? '';
      if (message.includes('SESSION_NOT_DELETABLE')) {
        throw new BadRequestException(
          '투표/주문이 진행 중인 세션은 삭제할 수 없어요. 세션을 종료한 뒤 다시 시도해주세요.',
        );
      }
      this.logger.error('SESSION_DELETE_PERSIST_FAILED');
      throw new InternalServerErrorException(
        '세션을 삭제하지 못했어요. 잠시 후 다시 시도해주세요.',
      );
    }

    if (!data) {
      // RPC 가 NULL 을 돌려준 경우 — 우리가 확인한 직후 다른 요청이 먼저 삭제한 상황.
      throw new NotFoundException('세션이 이미 삭제되었거나 존재하지 않아요.');
    }

    this.logger.log('SESSION_DELETE_COMPLETED');

    // RPC 는 { deletedSessionId, deletedAt } 형태로 응답 (camelCase).
    return data as { deletedSessionId: string; deletedAt: string };
  }

  // ── DELETE /sessions/:id/members/:userId ───────────────
  // 보안 패치:
  //   - 본인이 자기 자신을 제거 — 허용 (세션 나가기)
  //   - 호스트가 다른 멤버 제거 — 허용
  //   - 그 외 — 거부
  async removeMember(
    sessionId: string,
    requesterId: string | undefined,
    targetUserId: string,
  ) {
    if (!requesterId) {
      throw new UnauthorizedException(
        '사용자 인증 정보가 없습니다. 다시 로그인해주세요.',
      );
    }
    if (requesterId !== targetUserId) {
      // 타인 제거는 호스트만
      await this.assertHost(sessionId, requesterId);
    }

    const { error } = await this.supabase.client
      .from('session_members')
      .delete()
      .eq('session_id', sessionId)
      .eq('user_id', targetUserId);

    if (error) {
      this.logger.error('SESSION_MEMBER_REMOVE_PERSIST_FAILED');
      throw new InternalServerErrorException('멤버를 제거하지 못했어요.');
    }

    return { success: true };
  }

  // ── GET /sessions/:id/invite ───────────────────────────
  // WOW#8 친구 초대 시스템 (2026-05-31):
  //   세션 로비의 "친구 초대" 버튼이 호출하는 단일 엔드포인트.
  //   기존 POST /invitations 흐름은 그대로 두고, 손님 페르소나용으로 한 번에
  //   { inviteCode, deepLink, shortLink, expiresAt } 4종 페이로드를 반환한다.
  //
  // 동작 원리:
  //   1) invitations 테이블에서 이 세션의 "아직 만료되지 않은" 코드 1건 조회
  //      - 최신 생성순으로 정렬해 가장 신선한 코드를 우선 사용
  //      - 동일 세션에 여러 코드가 있을 수 있어도 첫 유효 코드만 노출
  //   2) 유효 코드가 없으면(없음 / 모두 만료) 8자리 hex 랜덤 코드 신규 INSERT
  //      - 만료 시각: 세션이 expires_at 컬럼을 갖지 않으므로 지금 +6시간
  //        (미션 요구 사항: "sessions.expires_at 또는 +6h")
  //      - InvitationsService 의 24시간과 다른 이유:
  //        WOW#8 은 "지금 점심 같이 가자" 일회용 흐름이라 짧게 유지
  //   3) 응답에 deepLink / shortLink 동봉 — Flutter 가 share_plus 로 그대로 공유
  //
  // 보안:
  //   호스트가 아닌 일반 멤버도 친구를 추가 초대할 수 있도록 호스트 검증은 생략.
  //   (코드 자체가 권한 토큰 역할이므로 노출되어도 추가 멤버 합류만 가능)
  //   세션 존재 여부만 확인하고 NotFound 시 명확한 한국어 메시지 반환.
  //
  // 환경 변수:
  //   INVITE_SHORT_LINK_BASE — 운영 시 nginx 가 호스트하는 짧은 링크 도메인.
  //   미설정이면 미션 기본값 `https://lunchsync.duckdns.org/j/` 사용.
  //   딥링크 스킴은 `lunchsync://join?code=` 고정.
  async getInviteInfo(sessionId: string) {
    // 0단계: 세션 존재 확인 — 잘못된 ID 즉시 404
    const { data: session, error: sessionError } = await this.supabase.client
      .from('sessions')
      .select('id')
      .eq('id', sessionId)
      .single();
    if (sessionError || !session) {
      throw new NotFoundException('세션을 찾을 수 없어요.');
    }

    // 1단계: 활성 초대 코드 재사용 시도 — 가장 최근 생성 + 미만료
    const nowIso = new Date().toISOString();
    const { data: existing } = await this.supabase.client
      .from('invitations')
      .select('invite_code, expires_at')
      .eq('session_id', sessionId)
      .gt('expires_at', nowIso)
      .order('created_at', { ascending: false })
      .limit(1);

    let inviteCode: string;
    let expiresAt: string;

    if (existing && existing.length > 0) {
      // 살아있는 코드 — 그대로 재사용 (동일 세션에 N개의 코드 난립 방지)
      inviteCode = existing[0].invite_code as string;
      expiresAt = existing[0].expires_at as string;
    } else {
      // 2단계: 새 코드 생성 — 8자리 hex, +6시간 만료
      // randomBytes(4) → 8자리 hex. InvitationsService 와 동일 포맷 유지해
      // 기존 POST /invitations/:code/accept 흐름과 호환된다.
      const { randomBytes } = await import('crypto');
      inviteCode = randomBytes(4).toString('hex');
      expiresAt = new Date(Date.now() + 6 * 60 * 60 * 1000).toISOString();

      const { error: insertError } = await this.supabase.client
        .from('invitations')
        .insert({
          session_id: sessionId,
          invite_code: inviteCode,
          expires_at: expiresAt,
        });
      if (insertError) {
        // INSERT 실패는 운영 추적 필요 — 로그 + 500
        this.logger.error('SESSION_INVITE_CREATE_PERSIST_FAILED');
        throw new InternalServerErrorException(
          '초대 링크를 만들지 못했어요. 잠시 후 다시 시도해주세요.',
        );
      }
    }

    // 3단계: deepLink / shortLink 합성 — Flutter 가 share_plus 로 그대로 공유
    const shortLinkBase =
      process.env.INVITE_SHORT_LINK_BASE ?? 'https://lunchsync.duckdns.org/j/';
    // base 끝에 슬래시가 있든 없든 안전하게 코드를 붙이기 위한 정규화
    const normalizedBase = shortLinkBase.endsWith('/')
      ? shortLinkBase
      : `${shortLinkBase}/`;

    return {
      inviteCode,
      deepLink: `lunchsync://join?code=${inviteCode}`,
      shortLink: `${normalizedBase}${inviteCode}`,
      expiresAt,
    };
  }
}
