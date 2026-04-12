import {
  Injectable,
  NotFoundException,
  ConflictException,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 점심 세션 비즈니스 로직
//
// 세션이란?
//   "오늘 점심 같이 먹자" 한 번의 이벤트를 의미.
//   세션 생성 → 멤버 초대 → 추천 → 투표 → 확정 → 주문 흐름의 시작점.
//
// 상태 전이:
//   WAITING → VOTING → DECIDED → COMPLETED
// ══════════════════════════════════════════════════════════

export interface CreateSessionDto {
  name: string;
  scheduledAt?: string; // ISO8601
}

export interface UpdateSessionStatusDto {
  status: string; // WAITING | VOTING | DECIDED | COMPLETED
}

export interface AddMemberDto {
  userId: string;
}

@Injectable()
export class SessionsService {
  constructor(private readonly supabase: SupabaseService) {}

  // ── POST /sessions ────────────────────────────────────
  // 세션 생성 + 생성자를 자동으로 멤버에 추가
  async createSession(userId: string, dto: CreateSessionDto) {
    // 1. sessions 테이블에 INSERT
    const insertData: Record<string, unknown> = {
      name: dto.name,
      created_by: userId,
    };
    if (dto.scheduledAt) {
      insertData.scheduled_at = dto.scheduledAt;
    }

    const { data: session, error } = await this.supabase.client
      .from('sessions')
      .insert(insertData)
      .select('id, name, status, created_by, scheduled_at, created_at')
      .single();

    if (error || !session) {
      throw new Error(`세션 생성 실패: ${error?.message}`);
    }

    // 2. 생성자를 session_members에 자동 추가
    await this.supabase.client
      .from('session_members')
      .insert({ session_id: session.id, user_id: userId });

    return {
      id: session.id,
      name: session.name,
      status: session.status,
      createdBy: session.created_by,
      scheduledAt: session.scheduled_at,
      createdAt: session.created_at,
    };
  }

  // ── GET /sessions/today ───────────────────────────────
  // 오늘 날짜 기준으로 내가 속한 세션 목록 조회
  async getTodaySessions(userId: string) {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayISO = today.toISOString();

    // 내가 멤버인 세션의 ID 목록
    const { data: myMemberships } = await this.supabase.client
      .from('session_members')
      .select('session_id')
      .eq('user_id', userId);

    const sessionIds = myMemberships?.map((m) => m.session_id) ?? [];
    if (sessionIds.length === 0) return [];

    const { data: sessions } = await this.supabase.client
      .from('sessions')
      .select('id, name, status, created_by, scheduled_at, created_at')
      .in('id', sessionIds)
      .gte('created_at', todayISO)
      .order('created_at', { ascending: false });

    return (sessions ?? []).map((s) => ({
      id: s.id,
      name: s.name,
      status: s.status,
      createdBy: s.created_by,
      scheduledAt: s.scheduled_at,
      createdAt: s.created_at,
    }));
  }

  // ── GET /sessions/:id ─────────────────────────────────
  async getSessionById(sessionId: string) {
    const { data, error } = await this.supabase.client
      .from('sessions')
      .select('id, name, status, created_by, winner_restaurant_id, scheduled_at, created_at')
      .eq('id', sessionId)
      .single();

    if (error || !data) {
      throw new NotFoundException('세션을 찾을 수 없습니다.');
    }

    return {
      id: data.id,
      name: data.name,
      status: data.status,
      createdBy: data.created_by,
      winnerRestaurantId: data.winner_restaurant_id,
      scheduledAt: data.scheduled_at,
      createdAt: data.created_at,
    };
  }

  // ── PATCH /sessions/:id/status ────────────────────────
  async updateSessionStatus(sessionId: string, dto: UpdateSessionStatusDto) {
    const { data, error } = await this.supabase.client
      .from('sessions')
      .update({ status: dto.status })
      .eq('id', sessionId)
      .select('id, name, status')
      .single();

    if (error || !data) {
      throw new NotFoundException('세션을 찾을 수 없습니다.');
    }

    return { id: data.id, name: data.name, status: data.status };
  }

  // ── GET /sessions/:id/members ─────────────────────────
  async getSessionMembers(sessionId: string) {
    const { data, error } = await this.supabase.client
      .from('session_members')
      .select('user_id, joined_at, users(id, name, profile_image, org)')
      .eq('session_id', sessionId);

    if (error) {
      throw new Error(`멤버 조회 실패: ${error.message}`);
    }

    return (data ?? []).map((m: any) => ({
      userId: m.user_id,
      joinedAt: m.joined_at,
      name: m.users?.name,
      profileImage: m.users?.profile_image,
      org: m.users?.org,
    }));
  }

  // ── POST /sessions/:id/members ────────────────────────
  async addMember(sessionId: string, dto: AddMemberDto) {
    const { error } = await this.supabase.client
      .from('session_members')
      .insert({ session_id: sessionId, user_id: dto.userId });

    if (error) {
      if (error.code === '23505') {
        throw new ConflictException('이미 세션에 참가한 멤버입니다.');
      }
      throw new Error(`멤버 추가 실패: ${error.message}`);
    }

    return { success: true };
  }

  // ── DELETE /sessions/:id/members/:userId ───────────────
  async removeMember(sessionId: string, userId: string) {
    const { error } = await this.supabase.client
      .from('session_members')
      .delete()
      .eq('session_id', sessionId)
      .eq('user_id', userId);

    if (error) {
      throw new Error(`멤버 제거 실패: ${error.message}`);
    }

    return { success: true };
  }
}
