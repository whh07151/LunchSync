import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

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
  constructor(private readonly supabase: SupabaseService) {}

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
      throw new Error(`알림 조회 실패: ${error.message}`);
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
      throw new Error(`전체 읽음 처리 실패: ${error.message}`);
    }

    return (data ?? []).length;
  }

  // ── 알림 생성 (다른 모듈에서 호출하는 내부 메서드) ────
  // orders, votes 모듈 등에서 이벤트 발생 시 호출.
  // 예) 주문 상태가 PAID → 점주에게 ORDER_RECEIVED 알림 생성.
  async createNotification(params: {
    userId: string;
    type: string;
    title: string;
    message: string;
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
      throw new Error(`알림 생성 실패: ${error?.message}`);
    }

    return {
      id: data.id,
      type: data.type,
      title: data.title,
      message: data.message,
      isRead: data.is_read,
      createdAt: data.created_at,
    };
  }
}
