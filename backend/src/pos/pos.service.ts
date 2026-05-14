import {
  Injectable,
  InternalServerErrorException,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { PaymentsService } from '../payments/payments.service';

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
//
// 응답 보강 (2026-05-12 LSPOS 통합):
//   getOrdersByRestaurant 응답에 customer.name, items[] 추가 — LSPOS 의 OrderCard
//   가 손님명/메뉴 요약을 표시할 수 있도록. orders 테이블의 restaurant_id 직접 매칭으로
//   sessions.winner_restaurant_id JOIN 제거 (orders.restaurant_id NOT NULL 확정).
// ══════════════════════════════════════════════════════════

/// 점주 화면에서 사용할 주문 응답 타입.
/// 백엔드 ↔ Flutter PosOrder / LSPOS Order 양쪽 모두와 호환되도록
/// snake_case 와 camelCase 를 함께 노출.
/// export 됨 — PosController 가 응답 반환 타입 추론에 참조하므로.
export interface PosOrderResponse {
  id: string;
  sessionId: string;
  userId: string;
  restaurantId: string | null;
  status: string;
  totalPrice: number;
  totalAmount: number; // alias — Flutter PosOrder.totalAmount 호환
  paymentKey: string | null;
  paymentMethod: string | null; // TOSS | CARD | CASH | SIMULATE | null
  createdAt: string;
  updatedAt: string;
  orderNumber: string;
  customer: { name: string | null; org: string | null } | null;
  customerName: string | null;
  items: { name: string; quantity: number; price: number }[];
  itemsSummary: string | null;
}

@Injectable()
export class PosService {
  private readonly logger = new Logger(PosService.name);

  constructor(
    private readonly supabase: SupabaseService,
    // 2026-05-15 단계 2: 사장 거절 시 자동 환불 (토스 cancel API) 호출용.
    private readonly paymentsService: PaymentsService,
  ) {}

  // ── OW-10 + POS-08: 점주용 주문 목록 조회 ────────────
  // restaurantId 기준으로 해당 식당에 들어온 주문 전체 조회.
  // users / order_items / menu_items LEFT JOIN 으로 손님명·메뉴 같이 반환.
  async getOrdersByRestaurant(
    restaurantId: string,
    status?: string,
  ): Promise<PosOrderResponse[]> {
    let qb = this.supabase.client
      .from('orders')
      .select(`
        id, session_id, user_id, restaurant_id, status, total_price, payment_key, payment_method,
        created_at, updated_at,
        users(id, name, org),
        order_items(id, quantity, price, menu_items(id, name))
      `)
      .eq('restaurant_id', restaurantId)
      .order('created_at', { ascending: false });

    if (status) {
      qb = qb.eq('status', status);
    }

    const { data, error } = await qb;

    if (error) {
      throw new Error(`주문 조회 실패: ${error.message}`);
    }

    return (data ?? []).map((o: any) => {
      const items = (o.order_items ?? []).map((it: any) => ({
        name: (it.menu_items?.name as string) ?? '메뉴',
        quantity: (it.quantity as number) ?? 0,
        price: (it.price as number) ?? 0,
      }));

      const customerName = (o.users?.name as string | undefined) ?? null;
      const customerOrg = (o.users?.org as string | undefined) ?? null;

      return {
        id: o.id,
        sessionId: o.session_id,
        userId: o.user_id,
        restaurantId: o.restaurant_id ?? null,
        status: o.status,
        totalPrice: o.total_price,
        totalAmount: o.total_price, // alias
        paymentKey: o.payment_key ?? null,
        paymentMethod: o.payment_method ?? null,
        createdAt: o.created_at,
        updatedAt: o.updated_at,
        orderNumber: this.formatOrderNumber(o.id),
        customer: customerName || customerOrg
          ? { name: customerName, org: customerOrg }
          : null,
        customerName,
        items,
        itemsSummary: this.buildItemsSummary(items),
      };
    });
  }

  // ── POS-08: 결제 상태별 통계 + 결제수단별 매출 ────────
  // 매출은 PAID 이상(PAID/PREPARING/READY/COMPLETED) 상태에서만 누적.
  // CANCELLED 는 합산 제외.
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
      // 결제수단별 매출 분리 (2026-05-13 추가, 백엔드 협의 #9b)
      tossRevenue: 0,
      cardRevenue: 0,
      cashRevenue: 0,
      simulateRevenue: 0,
    };

    for (const order of orders) {
      let countAsRevenue = false;
      switch (order.status) {
        case 'PENDING':
          stats.pending++;
          break;
        case 'PAID':
          stats.paid++;
          countAsRevenue = true;
          break;
        case 'PREPARING':
          stats.preparing++;
          countAsRevenue = true;
          break;
        case 'READY':
          stats.ready++;
          countAsRevenue = true;
          break;
        case 'COMPLETED':
          stats.completed++;
          countAsRevenue = true;
          break;
        case 'CANCELLED':
          stats.cancelled++;
          break;
      }

      if (countAsRevenue) {
        stats.totalRevenue += order.totalPrice;
        switch (order.paymentMethod) {
          case 'TOSS':
            stats.tossRevenue += order.totalPrice;
            break;
          case 'CARD':
            stats.cardRevenue += order.totalPrice;
            break;
          case 'CASH':
            stats.cashRevenue += order.totalPrice;
            break;
          case 'SIMULATE':
          default:
            stats.simulateRevenue += order.totalPrice;
            break;
        }
      }
    }

    return stats;
  }

  // ── 권한 검증용: orderId → restaurant_id 사전 조회 ─────
  // 컨트롤러가 assertPosAccessTo 호출 전에 어느 매장의 주문인지 확인하기 위함.
  // 주문이 없으면 NotFoundException — 컨트롤러가 그대로 위로 전파.
  async getRestaurantIdByOrderId(orderId: string): Promise<string> {
    const { data, error } = await this.supabase.client
      .from('orders')
      .select('restaurant_id')
      .eq('id', orderId)
      .single();
    if (error || !data?.restaurant_id) {
      throw new NotFoundException('주문을 찾을 수 없습니다.');
    }
    return data.restaurant_id as string;
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

  // ── POS-09: 사장 거절 + 자동 환불 (원자성 보장) ─────────
  // 2026-05-15 단계 2 발전 (plan): TODO 제거 + 실제 환불 활성화.
  //
  // 원자성 정책 ([[feedback-root-cause-analysis]] 4단계 분석):
  //   - 환불 API 우선 호출 → 성공 시에만 status CANCELLED 적용
  //   - 환불 실패 시 status 미변경 + 예외 throw → 호출부가 손님에게 명확한 에러 응답
  //   - 사장님 결정 (Q3): 원자성 — cancel 실패 시 CANCELLED 도 미적용
  //
  // 거절 가능 구간 (Q2 결정):
  //   - PAID / ACCEPTED 두 상태에서 거절 가능
  //   - PREPARING 진입 후엔 차단 (이미 조리 시작했으면 환불 불가 정책)
  //   - 기존 CANCELLED / COMPLETED 차단 유지
  async cancelOrder(orderId: string, reason?: string) {
    // 1) 주문 조회
    const { data: order, error } = await this.supabase.client
      .from('orders')
      .select('id, status, total_price, payment_key')
      .eq('id', orderId)
      .single();

    if (error || !order) {
      throw new NotFoundException('주문을 찾을 수 없습니다.');
    }

    // 2) 거절 가능 상태 검증
    //   - CANCELLED / COMPLETED / DONE / PREPARING / READY 모두 거절 불가
    //   - PAID / ACCEPTED / PENDING 만 거절 가능 (조리 시작 전)
    const cancelableStatuses = new Set(['PAID', 'ACCEPTED', 'PENDING']);
    if (!cancelableStatuses.has(order.status)) {
      throw new InternalServerErrorException(
        `이미 ${order.status} 상태인 주문은 취소할 수 없습니다. ` +
          '조리 시작 후엔 거절 불가입니다.',
      );
    }

    // 3) 환불 우선 호출 (payment_key 있으면)
    //   - 환불 성공 시에만 다음 단계(status update) 진행
    //   - 실패 시 throw → status 미변경, 호출부가 사용자에게 친근 에러 표시
    let refundResult: {
      paymentKey: string;
      status: string;
      cancelAmount?: number;
      canceledAt?: string;
    } | null = null;

    if (order.payment_key && order.payment_key.trim().length > 0) {
      try {
        refundResult = await this.paymentsService.cancelPayment(
          order.payment_key,
          reason ?? '점주 취소',
        );
      } catch (refundError: any) {
        this.logger.error(
          `환불 실패 — status 미변경 유지: order=${orderId} ` +
            `payment_key=${order.payment_key} error=${refundError?.message}`,
        );
        // 원자성 — 환불 실패 시 status 도 변경하지 않고 예외 그대로 전파.
        // 호출부(컨트롤러)가 사용자에게 친근 에러 메시지 표시.
        throw refundError;
      }
    }

    // 4) 환불 성공(또는 payment_key 없음) → 상태 CANCELLED 로 변경
    await this.supabase.client
      .from('orders')
      .update({ status: 'CANCELLED' })
      .eq('id', orderId);

    return {
      id: orderId,
      status: 'CANCELLED',
      refundAmount: refundResult?.cancelAmount ?? order.total_price,
      refundMethod: refundResult ? 'TOSS_CANCEL' : 'NO_PAYMENT_KEY',
      canceledAt: refundResult?.canceledAt,
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

  // ── 주문번호 포맷 ────────────────────────────────────
  // UUID 의 앞 6자 + 대문자화 → "#A3F2C9" 형태. 점주/POS UI 표시용.
  private formatOrderNumber(orderId: string): string {
    return `#${(orderId ?? '').replace(/-/g, '').substring(0, 6).toUpperCase()}`;
  }

  // ── 메뉴 요약 텍스트 ─────────────────────────────────
  // 첫 메뉴 + "외 N건" 형태. 빈 배열이면 null.
  // 예: [{name:'비빔밥', q:1}, {name:'된장찌개', q:2}] → "비빔밥 외 1건"
  private buildItemsSummary(
    items: { name: string; quantity: number }[],
  ): string | null {
    if (items.length === 0) return null;
    if (items.length === 1) return items[0].name;
    return `${items[0].name} 외 ${items.length - 1}건`;
  }
}
