import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 점주앱/POS 비즈니스 로직
//
// 티켓:
//   OW-10  — 결제 확인/시뮬 (점주가 주문의 결제 상태 확인)
//   POS-08 — 결제 상태 패널 (POS 대시보드)
//   POS-09 — 취소/환불 시뮬레이션
//   POS-13 — Toss POS 연동 준비 (인터페이스만 정의)
//
// 주문 상태 전이 (점주 관점):
//   PAID → PREPARING → READY → COMPLETED
//   PAID → CANCELLED (취소/환불)
// ══════════════════════════════════════════════════════════

@Injectable()
export class PosService {
  constructor(private readonly supabase: SupabaseService) {}

  // ── OW-10 + POS-08: 점주용 주문 목록 조회 ────────────
  // restaurantId 기준으로 해당 식당에 들어온 주문 전체 조회
  async getOrdersByRestaurant(restaurantId: string, status?: string) {
    let qb = this.supabase.client
      .from('orders')
      .select(`
        id, session_id, user_id, status, total_price, payment_key,
        created_at, updated_at,
        sessions!inner(winner_restaurant_id)
      `)
      .eq('sessions.winner_restaurant_id', restaurantId)
      .order('created_at', { ascending: false });

    if (status) {
      qb = qb.eq('status', status);
    }

    const { data, error } = await qb;

    if (error) {
      throw new Error(`주문 조회 실패: ${error.message}`);
    }

    return (data ?? []).map((o: any) => ({
      id: o.id,
      sessionId: o.session_id,
      userId: o.user_id,
      status: o.status,
      totalPrice: o.total_price,
      paymentKey: o.payment_key,
      createdAt: o.created_at,
      updatedAt: o.updated_at,
    }));
  }

  // ── POS-08: 결제 상태별 통계 ──────────────────────────
  async getPaymentStats(restaurantId: string) {
    const orders = await this.getOrdersByRestaurant(restaurantId);

    const stats = {
      total: orders.length,
      pending: 0,
      paid: 0,
      preparing: 0,
      ready: 0,
      completed: 0,
      cancelled: 0,
      totalRevenue: 0,
    };

    for (const order of orders) {
      switch (order.status) {
        case 'PENDING': stats.pending++; break;
        case 'PAID': stats.paid++; stats.totalRevenue += order.totalPrice; break;
        case 'PREPARING': stats.preparing++; stats.totalRevenue += order.totalPrice; break;
        case 'READY': stats.ready++; stats.totalRevenue += order.totalPrice; break;
        case 'COMPLETED': stats.completed++; stats.totalRevenue += order.totalPrice; break;
        case 'CANCELLED': stats.cancelled++; break;
      }
    }

    return stats;
  }

  // ── 점주 주문 상태 변경 (조리중 → 준비완료 등) ────────
  async updateOrderStatus(orderId: string, status: string) {
    const { data, error } = await this.supabase.client
      .from('orders')
      .update({ status })
      .eq('id', orderId)
      .select('id, status, updated_at')
      .single();

    if (error || !data) {
      throw new NotFoundException('주문을 찾을 수 없습니다.');
    }

    return { id: data.id, status: data.status, updatedAt: data.updated_at };
  }

  // ── POS-09: 취소/환불 시뮬레이션 ─────────────────────
  async cancelOrder(orderId: string, reason?: string) {
    // 주문 조회
    const { data: order, error } = await this.supabase.client
      .from('orders')
      .select('id, status, total_price, payment_key')
      .eq('id', orderId)
      .single();

    if (error || !order) {
      throw new NotFoundException('주문을 찾을 수 없습니다.');
    }

    // 이미 취소/완료된 주문은 취소 불가
    if (order.status === 'CANCELLED' || order.status === 'COMPLETED') {
      throw new Error(`이미 ${order.status} 상태인 주문은 취소할 수 없습니다.`);
    }

    // 상태를 CANCELLED로 변경
    await this.supabase.client
      .from('orders')
      .update({ status: 'CANCELLED' })
      .eq('id', orderId);

    // TODO POS-13: Toss Payments 실제 환불 API 호출
    // if (order.payment_key) {
    //   await this.refundViaToss(order.payment_key, order.total_price, reason);
    // }

    return {
      id: orderId,
      status: 'CANCELLED',
      refundAmount: order.total_price,
      refundMethod: 'SIMULATE', // 가상 환불
      reason: reason ?? '점주 취소',
    };
  }

  // ── POS-13: Toss POS 연동 준비 (인터페이스) ──────────
  // 추후 Toss Payments secretKey를 .env에서 읽어 실제 API 호출
  // 현재는 인터페이스만 정의
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  private async refundViaToss(paymentKey: string, amount: number, reason?: string) {
    // TODO: 실제 환불 구현
    // const secretKey = this.configService.get('TOSS_SECRET_KEY');
    // const response = await fetch(`https://api.tosspayments.com/v1/payments/${paymentKey}/cancel`, {
    //   method: 'POST',
    //   headers: {
    //     Authorization: `Basic ${Buffer.from(secretKey + ':').toString('base64')}`,
    //     'Content-Type': 'application/json',
    //   },
    //   body: JSON.stringify({ cancelReason: reason ?? '점주 취소' }),
    // });
    return { success: true };
  }
}
