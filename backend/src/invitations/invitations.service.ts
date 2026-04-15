import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ConflictException,
} from '@nestjs/common';
import { randomBytes } from 'crypto';
import { SupabaseService } from '../supabase/supabase.service';
import { SessionsService } from '../sessions/sessions.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 초대 링크 비즈니스 로직
//
// 흐름:
//   1. 세션 생성자가 초대 코드 생성 (POST /invitations)
//   2. 초대 코드를 친구에게 공유
//   3. 친구가 코드 입력 → 유효성 확인 (GET /invitations/:code)
//   4. 초대 수락 → 세션 멤버에 추가 (POST /invitations/:code/accept)
// ══════════════════════════════════════════════════════════

export interface CreateInvitationDto {
  sessionId: string;
}

@Injectable()
export class InvitationsService {
  constructor(
    private readonly supabase: SupabaseService,
    private readonly sessionsService: SessionsService,
  ) {}

  // ── POST /invitations ─────────────────────────────────
  // 8자리 랜덤 초대 코드 생성
  async createInvitation(userId: string, dto: CreateInvitationDto) {
    const inviteCode = randomBytes(4).toString('hex'); // 8자리 hex

    // 만료 시각: 생성 시점으로부터 24시간 후
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

    const { data, error } = await this.supabase.client
      .from('invitations')
      .insert({
        session_id: dto.sessionId,
        invite_code: inviteCode,
        expires_at: expiresAt,
      })
      .select('id, session_id, invite_code, expires_at, created_at')
      .single();

    if (error || !data) {
      throw new Error(`초대 생성 실패: ${error?.message}`);
    }

    return {
      id: data.id,
      sessionId: data.session_id,
      inviteCode: data.invite_code,
      expiresAt: data.expires_at,
      createdAt: data.created_at,
    };
  }

  // ── GET /invitations/:code ────────────────────────────
  // 초대 코드 유효성 확인 + 세션 정보 반환
  async getByCode(code: string) {
    const { data, error } = await this.supabase.client
      .from('invitations')
      .select('id, session_id, invite_code, expires_at')
      .eq('invite_code', code)
      .single();

    if (error || !data) {
      throw new NotFoundException('유효하지 않은 초대 코드입니다.');
    }

    // 만료 확인
    if (new Date(data.expires_at) < new Date()) {
      throw new BadRequestException('만료된 초대 코드입니다.');
    }

    // 세션 정보 조회
    const session = await this.sessionsService.getSessionById(data.session_id);

    return {
      inviteCode: data.invite_code,
      session,
    };
  }

  // ── POST /invitations/:code/accept ────────────────────
  // 초대 수락: session_members에 본인 추가
  async acceptInvitation(code: string, userId: string) {
    const { data, error } = await this.supabase.client
      .from('invitations')
      .select('session_id, expires_at')
      .eq('invite_code', code)
      .single();

    if (error || !data) {
      throw new NotFoundException('유효하지 않은 초대 코드입니다.');
    }

    if (new Date(data.expires_at) < new Date()) {
      throw new BadRequestException('만료된 초대 코드입니다.');
    }

    // 세션에 멤버 추가 (SessionsService 재사용)
    try {
      await this.sessionsService.addMember(data.session_id, { userId });
    } catch (e) {
      if (e instanceof ConflictException) {
        throw e; // 이미 참가한 멤버
      }
      throw e;
    }

    return { success: true, sessionId: data.session_id };
  }
}
