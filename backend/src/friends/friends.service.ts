import {
  BadRequestException,
  ConflictException,
  Injectable,
  InternalServerErrorException,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 친구 관계 비즈니스 로직 (CU-08 보강)
//
// 흐름:
//   - 이메일로 친구 추가 (즉시 양방향 매칭, 수락 단계 없음 — 시연 MVP)
//   - 내 친구 목록 조회 (세션 만들기 화면에서 사용)
//   - 친구 삭제 (양방향 동시 삭제)
//
// 백엔드 정책:
//   2026-05-14 사장님 시연 발견 — bd18a19 에서 mock 친구 8명 제거 후
//   진짜 친구 시스템이 미구현이었음. MVP 로 양방향 자동 매칭(요청/수락
//   단계 없음) 도입. 후속 사이클에서 요청/수락 흐름으로 확장 가능.
// ══════════════════════════════════════════════════════════

export interface FriendDto {
  id: string;          // 친구 사용자 ID
  name: string;        // 친구 이름
  email: string | null;
  profileImage: string | null;
  since: string;       // ISO8601 친구 맺은 시각
}

@Injectable()
export class FriendsService {
  private readonly logger = new Logger(FriendsService.name);

  constructor(private readonly supabase: SupabaseService) {}

  // ── 친구 추가 (이메일로) ────────────────────────────────
  // 1) friendEmail 로 users 테이블에서 상대방 찾기
  // 2) 자기 자신/이미 친구 검증
  // 3) 양방향 2건 INSERT (user_id 기준 양쪽 모두 보이게)
  async addFriendByEmail(userId: string, friendEmail: string): Promise<FriendDto> {
    const normalized = (friendEmail ?? '').trim().toLowerCase();
    if (!normalized) {
      throw new BadRequestException('이메일을 입력해주세요.');
    }

    // 1단계: 상대방 사용자 조회
    const { data: friendUser, error: findError } = await this.supabase.client
      .from('users')
      .select('id, name, email, profile_image')
      .eq('email', normalized)
      .maybeSingle();

    if (findError) {
      this.logger.error('FRIEND_LOOKUP_PERSIST_FAILED');
      throw new InternalServerErrorException('친구를 찾는 중 오류가 났어요.');
    }
    if (!friendUser) {
      throw new NotFoundException(
        '해당 이메일로 가입한 사용자가 없어요. 친구가 먼저 가입해야 해요.',
      );
    }

    // 2단계: 자기 자신 차단
    if (friendUser.id === userId) {
      throw new BadRequestException('자기 자신은 친구로 추가할 수 없어요.');
    }

    // 3단계: 양방향 INSERT (2건)
    const { error: insertError } = await this.supabase.client
      .from('friends')
      .insert([
        { user_id: userId, friend_user_id: friendUser.id },
        { user_id: friendUser.id, friend_user_id: userId },
      ]);

    if (insertError) {
      // UNIQUE 제약 위반 → 이미 친구
      if (insertError.code === '23505') {
        throw new ConflictException('이미 친구로 등록되어 있어요.');
      }
      this.logger.error('FRIEND_CREATE_PERSIST_FAILED');
      throw new InternalServerErrorException('친구를 추가하지 못했어요.');
    }

    return {
      id: friendUser.id,
      name: friendUser.name,
      email: friendUser.email,
      profileImage: friendUser.profile_image ?? null,
      since: new Date().toISOString(),
    };
  }

  // ── 내 친구 목록 조회 ───────────────────────────────────
  // user_id == me 인 모든 friend_user_id 의 user 정보 join
  async listFriends(userId: string): Promise<FriendDto[]> {
    const { data, error } = await this.supabase.client
      .from('friends')
      .select(
        'friend_user_id, created_at, ' +
          'friend:users!friends_friend_user_id_fkey(id, name, email, profile_image)',
      )
      .eq('user_id', userId)
      .order('created_at', { ascending: false });

    if (error) {
      this.logger.error('FRIEND_LIST_PERSIST_FAILED');
      throw new InternalServerErrorException('친구 목록을 불러오지 못했어요.');
    }

    return (data ?? []).map((row: any) => {
      const f = row.friend ?? {};
      return {
        id: f.id ?? row.friend_user_id,
        name: f.name ?? '이름 없음',
        email: f.email ?? null,
        profileImage: f.profile_image ?? null,
        since: row.created_at,
      };
    });
  }

  // ── 친구 삭제 (양방향) ───────────────────────────────────
  // user_id↔friend_user_id 2건 모두 삭제 — Supabase or 필터 사용
  async removeFriend(
    userId: string,
    friendUserId: string,
  ): Promise<{ removed: true }> {
    if (userId === friendUserId) {
      throw new BadRequestException('자기 자신을 삭제할 수는 없어요.');
    }

    const { error } = await this.supabase.client
      .from('friends')
      .delete()
      .or(
        `and(user_id.eq.${userId},friend_user_id.eq.${friendUserId}),` +
          `and(user_id.eq.${friendUserId},friend_user_id.eq.${userId})`,
      );

    if (error) {
      this.logger.error('FRIEND_DELETE_PERSIST_FAILED');
      throw new InternalServerErrorException('친구를 삭제하지 못했어요.');
    }

    return { removed: true };
  }
}
