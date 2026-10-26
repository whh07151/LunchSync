import {
  Injectable,
  InternalServerErrorException,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { FirebaseService } from '../auth/firebase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 알림(notifications) 비즈니스 로직
//
// DB 스키마 (notifications):
//   id UUID PK, user_id UUID FK→users CASCADE, type VARCHAR(50)
//   title VARCHAR(100), message TEXT, is_read BOOLEAN, created_at TIMESTAMP
//
// 알림 타입 (프론트 enum과 1:1 대응):
//   ORDER_RECEIVED  — 점주에게 주문이 들어옴
//   ORDER_ACCEPTED  — 점주가 주문 수락
//   ORDER_DONE      — 조리 완료
//   VOTE_RESULT     — 투표 결과 확정
//
// 보안: 모든 쿼리에 user_id 조건 포함 (타인 알림 접근 차단).
// ══════════════════════════════════════════════════════════

export interface NotificationDto {
  id: string;
  type: string;
  title: string;
  message: string;
  isRead: boolean;
  createdAt: string;
}

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly supabase: SupabaseService,
    // FCM 푸시 송신용 — 미초기화 환경에서도 동작 (sendPush 가 안전 false 반환)
    private readonly firebase: FirebaseService,
  ) {}

  // ── GET /notifications — 내 알림 목록 ────────────────
  // 최신순으로 정렬. 페이지네이션은 추후 limit/offset 추가 가능.
  async getMyNotifications(userId: string): Promise<NotificationDto[]> {
    const { data, error } = await this.supabase.client
      .from('notifications')
      .select('id, type, title, message, is_read, created_at')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(50);

    if (error) {
      // 500: 알림 SELECT 실패 → 운영팀 알람용
      throw new InternalServerErrorException('알림을 불러오지 못했어요.');
    }

    return (data ?? []).map((n) => ({
      id: n.id,
      type: n.type,
      title: n.title,
      message: n.message,
      isRead: n.is_read,
      createdAt: n.created_at,
    }));
  }

  // ── PATCH /notifications/:id/read — 단건 읽음 ────────
  // 본인 소유 알림이 아니면 NotFoundException (정보 노출 방지).
  async markAsRead(userId: string, notificationId: string) {
    const { data, error } = await this.supabase.client
      .from('notifications')
      .update({ is_read: true })
      .eq('id', notificationId)
      .eq('user_id', userId)  // 본인 알림만 업데이트 가능
      .select('id, is_read')
      .single();

    if (error || !data) {
      throw new NotFoundException('알림을 찾을 수 없습니다.');
    }

    return { id: data.id, isRead: data.is_read };
  }

  // ── PATCH /notifications/read-all — 전체 읽음 ────────
  // 미읽음 알림만 업데이트 → 불필요한 write 회피.
  async markAllAsRead(userId: string): Promise<number> {
    const { data, error } = await this.supabase.client
      .from('notifications')
      .update({ is_read: true })
      .eq('user_id', userId)
      .eq('is_read', false)
      .select('id');

    if (error) {
      throw new InternalServerErrorException(
        '알림을 모두 읽음 처리하지 못했어요.',
      );
    }

    return (data ?? []).length;
  }

  // ── 알림 생성 (다른 모듈에서 호출하는 내부 메서드) ────
  // orders, votes 모듈 등에서 이벤트 발생 시 호출.
  // 예) 주문 상태가 PAID → 점주에게 ORDER_RECEIVED 알림 생성.
  //
  // DB 저장과 별개로 사용자의 fcm_token 이 있으면 FCM 푸시도 함께 송신.
  // 푸시 송신 실패는 비즈니스 흐름을 막지 않음 (DB 저장은 무조건 성공).
  async createNotification(params: {
    userId: string;
    type: string;
    title: string;
    message: string;
    // 클라이언트가 받을 수 있는 딥링크용 페이로드 (예: { orderId, sessionId })
    pushData?: Record<string, string>;
  }): Promise<NotificationDto> {
    const { data, error } = await this.supabase.client
      .from('notifications')
      .insert({
        user_id: params.userId,
        type: params.type,
        title: params.title,
        message: params.message,
        is_read: false,
      })
      .select('id, type, title, message, is_read, created_at')
      .single();

    if (error || !data) {
      throw new InternalServerErrorException('알림을 만들지 못했어요.');
    }

    // ── FCM 푸시 송신 (best-effort) ──────────────────────
    // fcm_token 조회 → 있으면 송신, 없으면 건너뜀.
    // 토큰 만료/네트워크 오류는 sendPush 내부에서 swallow.
    void this.sendPushIfPossible({
      userId: params.userId,
      title: params.title,
      body: params.message,
      data: {
        type: params.type,
        notificationId: data.id,
        ...(params.pushData ?? {}),
      },
    });

    return {
      id: data.id,
      type: data.type,
      title: data.title,
      message: data.message,
      isRead: data.is_read,
      createdAt: data.created_at,
    };
  }

  // ── 내부: 사용자 fcm_token 조회 후 푸시 송신 ──────────
  // 노티 생성과 비동기로 분리 (push 실패가 응답을 느리게 만들지 않도록).
  private async sendPushIfPossible(params: {
    userId: string;
    title: string;
    body: string;
    data: Record<string, string>;
  }): Promise<void> {
    try {
      const { data: user } = await this.supabase.client
        .from('users')
        .select('fcm_token')
        .eq('id', params.userId)
        .single();

      const token = user?.fcm_token as string | null | undefined;
      if (!token) return; // 토큰 미저장 — 푸시 건너뜀

      await this.firebase.sendPush({
        token,
        title: params.title,
        body: params.body,
        data: params.data,
      });
    } catch {
      // FCM 송신은 best-effort — 실패해도 비즈니스 흐름 계속 진행
      this.logger.warn('NOTIFICATION_PUSH_SEND_FAILED');
    }
  }
}
