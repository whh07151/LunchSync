import {
  ConflictException,
  ForbiddenException,
  Injectable,
  InternalServerErrorException,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { PaymentsService } from '../payments/payments.service';
import { NotificationsService } from '../notifications/notifications.service';
// 2026-05-31 WOW#5 단골 랭킹: COMPLETED 분기에서 누적 픽업 횟수 → 등급
// 결정 후 매 5회마다 ORDER_VIP 알림 발송. RestaurantsModule 을 통째로
// 끌어오면 import 그래프가 복잡해지므로 순수 헬퍼 함수만 가져온다.
import {
  resolveLoyaltyRank,
  shouldSendLoyaltyMilestone,
} from '../restaurants/restaurants.service';

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
  // 2026-05-31 WOW#2: 사장 라이브 카메라 사진 URL (null = 미첨부).
  //   POS 카드가 "전송 완료" 배지로 활용.
  completionPhotoUrl: string | null;
}

@Injectable()
export class PosService {
  private readonly logger = new Logger(PosService.name);

  constructor(
    private readonly supabase: SupabaseService,
    // 2026-05-15 단계 2: 사장 거절 시 자동 환불 (토스 cancel API) 호출용.
    private readonly paymentsService: PaymentsService,
    // 2026-05-15 단계 3: 상태 전이 시 손님에게 푸시 알림 송신.
    private readonly notificationsService: NotificationsService,
  ) {}

  // ── OW-10 + POS-08: 점주용 주문 목록 조회 ────────────
  // restaurantId 기준으로 해당 식당에 들어온 주문 전체 조회.
  // users / order_items / menu_items LEFT JOIN 으로 손님명·메뉴 같이 반환.
  async getOrdersByRestaurant(
    restaurantId: string,
    status?: string,
  ): Promise<PosOrderResponse[]> {
    // 2026-05-31 WOW#2 회복탄력: completion_photo_url 컬럼이 아직
    // 마이그레이션 안 된 환경에선 select 전체가 실패할 수 있어 fallback 시도.
    const baseSelect = `
        id, session_id, user_id, restaurant_id, status, total_price, payment_key, payment_method,
        created_at, updated_at,
        users(id, name, org),
        order_items(id, quantity, price, menu_items(id, name))
      `;
    const selectWithPhoto = baseSelect.replace(
      'created_at, updated_at,',
      'created_at, updated_at, completion_photo_url,',
    );

    const buildQb = (selectStr: string) => {
      let q = this.supabase.client
        .from('orders')
        .select(selectStr)
        .eq('restaurant_id', restaurantId)
        .order('created_at', { ascending: false });
      if (status) q = q.eq('status', status);
      return q;
    };

    let { data, error } = await buildQb(selectWithPhoto);

    // 컬럼 미존재 시 graceful fallback — base select 로 재시도
    if (
      error &&
      typeof error.message === 'string' &&
      error.message.includes('completion_photo_url')
    ) {
      this.logger.warn(
        '[getOrdersByRestaurant] completion_photo_url 컬럼 미적용 환경 — fallback select',
      );
      ({ data, error } = await buildQb(baseSelect));
    }

    if (error) {
      throw new Error('POS_ORDER_LOOKUP_FAILED');
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
        completionPhotoUrl: (o.completion_photo_url as string | null) ?? null,
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
      // 2026-05-31 7회차 회귀 fix: REFUNDED 카운터 누락 — getPaymentHistory
      // 가 REFUNDED 를 PAYMENT_STATUSES 에 포함시켰는데 통계에 빠져 매출 카드 0원 회귀.
      refunded: 0,
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
        case 'REFUNDED':
          // 환불은 매출 합산 X(countAsRevenue=false), 카운터만 노출
          stats.refunded++;
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

  // ══════════════════════════════════════════════════════════
  // ── OW-10: 결제 내역 조회 + 환불 시뮬 (2026-05-31) ──
  //
  // 사장 화면 "결제 내역" 진입 시 사용. getOrdersByRestaurant 가 모든 상태를
  // 반환하는 것과 달리, 여기는 명시적으로 PAID 이상의 결제 발생 상태만 추림.
  //
  // 필터:
  //   - status IN ('PAID', 'PREPARING', 'READY', 'COMPLETED', 'REFUNDED', 'CANCELLED')
  //     → PENDING(결제 전) 은 제외. 결제 발생 이력만 보여주는 게 자연스러움.
  //   - dateFrom / dateTo (ISO 8601 string) — 선택. 미지정이면 전체.
  //     날짜 필터는 controller 에서 "오늘/어제/주간/월간" 칩 선택값을 변환해서 넘김.
  //
  // 응답:
  //   getOrdersByRestaurant 와 동일 스키마 (PosOrderResponse[]) — Flutter 가 동일
  //   PosOrder 모델로 받으므로 중복 매퍼 안 만듦.
  // ══════════════════════════════════════════════════════════
  async getPaymentHistory(
    restaurantId: string,
    dateFrom?: string,
    dateTo?: string,
  ): Promise<PosOrderResponse[]> {
    // 결제 발생 이력 상태만 — PENDING(결제 전) 제외.
    // CANCELLED / REFUNDED 는 환불 시뮬까지 포함해서 보여줘야 하므로 같이 노출.
    const PAYMENT_STATUSES = [
      'PAID',
      'PREPARING',
      'READY',
      'COMPLETED',
      'REFUNDED',
      'CANCELLED',
    ];

    // getOrdersByRestaurant 와 동일한 select 절 재사용 — 응답 스키마 일관성.
    // completion_photo_url 컬럼 미적용 환경 fallback 도 동일하게 적용.
    const baseSelect = `
        id, session_id, user_id, restaurant_id, status, total_price, payment_key, payment_method,
        created_at, updated_at,
        users(id, name, org),
        order_items(id, quantity, price, menu_items(id, name))
      `;
    const selectWithPhoto = baseSelect.replace(
      'created_at, updated_at,',
      'created_at, updated_at, completion_photo_url,',
    );

    const buildQb = (selectStr: string) => {
      let q = this.supabase.client
        .from('orders')
        .select(selectStr)
        .eq('restaurant_id', restaurantId)
        .in('status', PAYMENT_STATUSES)
        .order('created_at', { ascending: false });
      if (dateFrom) q = q.gte('created_at', dateFrom);
      if (dateTo) q = q.lte('created_at', dateTo);
      return q;
    };

    let { data, error } = await buildQb(selectWithPhoto);

    if (
      error &&
      typeof error.message === 'string' &&
      error.message.includes('completion_photo_url')
    ) {
      this.logger.warn(
        '[getPaymentHistory] completion_photo_url 컬럼 미적용 환경 — fallback select',
      );
      ({ data, error } = await buildQb(baseSelect));
    }

    if (error) {
      throw new Error('POS_PAYMENT_HISTORY_LOOKUP_FAILED');
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
        totalAmount: o.total_price,
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
        completionPhotoUrl: (o.completion_photo_url as string | null) ?? null,
      };
    });
  }

  // ══════════════════════════════════════════════════════════
  // ── OW-10: 환불 시뮬레이션 (2026-05-31) ──
  //
  // 실제 토스 cancel API 호출 없이 status 만 REFUNDED 로 변경.
  // cancelOrder(POS-09) 와 다른 점:
  //   - cancelOrder: PAID/PENDING 만 가능, 실제 토스 환불 발생, status=CANCELLED
  //   - refundSim:   COMPLETED/READY/PAID 까지 허용, 환불 미발생, status=REFUNDED
  //
  // 용도:
  //   사장 화면 "결제 내역" 에서 "환불 토글" 으로 사용. 데모/시연 환경에서
  //   실제 결제 취소 없이 매출 차감 효과만 시뮬레이션해 보여주려는 의도.
  //
  // 보안:
  //   - 컨트롤러가 JwtAuthGuard + assertPosAccessTo 로 권한 검증 후 진입.
  //   - 이미 REFUNDED / CANCELLED 인 주문은 idempotent — 그대로 반환 (재호출 방지).
  // ══════════════════════════════════════════════════════════
  async refundSim(orderId: string): Promise<{
    id: string;
    status: string;
    refundedAt: string;
  }> {
    const simulationEnabled =
      process.env.ALLOW_REFUND_SIMULATION === 'true' &&
      process.env.NODE_ENV !== 'production';
    if (!simulationEnabled) {
      throw new ForbiddenException({
        statusCode: 403,
        code: 'REFUND_SIMULATION_DISABLED',
        message: '환불 시뮬레이션이 허용되지 않은 환경입니다.',
        retryable: false,
      });
    }

    // 1) 주문 존재 + 현재 상태 확인 (이미 REFUNDED 면 idempotent 반환).
    const { data: existing, error: readError } = await this.supabase.client
      .from('orders')
      .select('id, status, updated_at, payment_key, payment_method')
      .eq('id', orderId)
      .single();

    if (readError || !existing) {
      throw new NotFoundException('주문을 찾을 수 없습니다.');
    }

    if (existing.status === 'REFUNDED') {
      // 이미 환불 시뮬된 주문 — 다시 호출해도 같은 결과 보장 (멱등성).
      return {
        id: existing.id,
        status: existing.status,
        refundedAt: existing.updated_at,
      };
    }

    const isSimulatedPayment =
      existing.payment_method === 'SIMULATE' ||
      existing.payment_key?.startsWith('sim_');
    if (!isSimulatedPayment) {
      throw new ConflictException({
        statusCode: 409,
        code: 'REAL_PAYMENT_REQUIRES_PROVIDER_REFUND',
        message: '실제 결제 주문은 결제사 환불 경로를 사용해야 합니다.',
        retryable: false,
        orderId,
      });
    }

    // 2) 환불 시뮬 가능 상태 검증.
    //    PAID 이상 + 진행 단계 모두 허용 (시연용이므로 관대하게).
    //    PENDING(결제 전) 은 환불 대상 자체가 없으므로 거절.
    const refundableStatuses = new Set([
      'PAID',
      'PREPARING',
      'READY',
      'COMPLETED',
    ]);
    if (!refundableStatuses.has(existing.status)) {
      throw new ConflictException({
        statusCode: 409,
        code: 'ORDER_NOT_REFUNDABLE_IN_SIMULATION',
        message: `${existing.status} 상태인 주문은 환불 시뮬할 수 없습니다.`,
        retryable: false,
        orderId,
      });
    }

    // 3) status 만 REFUNDED 로 변경 — 실제 토스 cancel API 호출 X.
    //    payment_key 그대로 두어 추후 실제 환불 필요 시 별도 처리 가능하도록.
    const { data, error } = await this.supabase.client
      .from('orders')
      .update({ status: 'REFUNDED', updated_at: new Date().toISOString() })
      .eq('id', orderId)
      .eq('status', existing.status)
      .eq('payment_key', existing.payment_key)
      .select('id, status, updated_at')
      .maybeSingle();

    if (error) {
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: 'REFUND_SIMULATION_DB_SYNC_FAILED',
        message: '환불 시뮬레이션 상태를 저장하지 못했습니다.',
        retryable: true,
        orderId,
      });
    }
    if (!data || data.status !== 'REFUNDED') {
      throw new ConflictException({
        statusCode: 409,
        code: 'ORDER_STATUS_CHANGED',
        message: '주문 상태가 동시에 변경되어 환불 시뮬레이션을 적용하지 않았습니다.',
        retryable: true,
        orderId,
      });
    }

    this.logger.log('POS_SIMULATED_REFUND_COMPLETED');

    return {
      id: data.id,
      status: data.status,
      refundedAt: data.updated_at,
    };
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
    // 2026-05-15 단계 3: 푸시 알림 hook — 상태 전이 시 손님 user_id 받아두기.
    // notifications.createNotification 이 알림 INSERT + FCM 자동 송신 둘 다 처리.
    //
    // 2026-05-31 WOW#5: COMPLETED 진입 직후 단골 알림 발송 판단을 위해
    // restaurant_id 도 함께 select.
    const { data: prevOrder, error: readError } = await this.supabase.client
      .from('orders')
      .select('id, user_id, status, restaurant_id, updated_at')
      .eq('id', orderId)
      .single();

    if (readError || !prevOrder) {
      throw new NotFoundException('주문을 찾을 수 없습니다.');
    }

    if (prevOrder.status === status) {
      return {
        id: prevOrder.id,
        status: prevOrder.status,
        updatedAt: prevOrder.updated_at,
        alreadyApplied: true,
      };
    }

    const allowedNextStatus: Record<string, string> = {
      PAID: 'PREPARING',
      PREPARING: 'READY',
      READY: 'COMPLETED',
    };
    if (allowedNextStatus[prevOrder.status] !== status) {
      throw new ConflictException({
        statusCode: 409,
        code: 'INVALID_ORDER_STATUS_TRANSITION',
        message: `${prevOrder.status} 상태에서 ${status} 상태로 변경할 수 없습니다.`,
        retryable: false,
        orderId,
      });
    }

    const { data, error } = await this.supabase.client
      .from('orders')
      // 2026-06-03: updated_at 트리거가 실DB 에 없어 status 만 바꾸면 updated_at 이
      //   생성시각 그대로 고정됨(결제관리 오늘집계/통계 처리시간 부정확). 명시적으로 갱신.
      .update({ status, updated_at: new Date().toISOString() })
      .eq('id', orderId)
      .eq('status', prevOrder.status)
      .select('id, status, updated_at')
      .maybeSingle();

    if (error) {
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: 'ORDER_STATUS_DB_SYNC_FAILED',
        message: '주문 상태를 저장하지 못했습니다. 다시 시도해주세요.',
        retryable: true,
        orderId,
      });
    }
    if (!data || data.status !== status) {
      const { data: reconciled } = await this.supabase.client
        .from('orders')
        .select('id, status, updated_at')
        .eq('id', orderId)
        .maybeSingle();
      if (reconciled?.status === status) {
        return {
          id: reconciled.id,
          status: reconciled.status,
          updatedAt: reconciled.updated_at,
          alreadyApplied: true,
          reconciled: true,
        };
      }
      throw new ConflictException({
        statusCode: 409,
        code: 'ORDER_STATUS_CHANGED',
        message: '주문 상태가 동시에 변경되어 요청을 적용하지 않았습니다.',
        retryable: true,
        orderId,
      });
    }

    // 알림 송신 — best-effort (실패해도 응답 정상)
    // 상태별 친근 메시지 매핑 (배민 패턴 톤)
    if (prevOrder?.user_id && prevOrder.status !== status) {
      // 2026-05-31 회귀 fix: ACCEPTED 는 사장이 직접 전환하는 단계가 아니라
      // 백엔드/POS 어느 라우트에서도 발급되지 않음. 죽은 분기 제거.
      const titleMap: Record<string, { title: string; msg: string }> = {
        PREPARING: { title: '조리가 시작됐어요', msg: '사장님이 메뉴를 만들고 있어요' },
        READY: { title: '픽업 준비 완료', msg: '메뉴가 준비됐어요. 식당으로 가주세요' },
        COMPLETED: { title: '주문 완료', msg: '맛있게 드셨나요? 리뷰를 남겨봐요' },
        DONE: { title: '주문 완료', msg: '맛있게 드셨나요?' },
      };
      const notif = titleMap[status];
      if (notif) {
        try {
          await this.notificationsService.createNotification({
            userId: prevOrder.user_id,
            type: `ORDER_${status}`,
            title: notif.title,
            message: notif.msg,
            pushData: { orderId, status },
          });
        } catch (notifErr: any) {
          // 알림 실패는 주문 상태 변경에 영향 없음 — 로그만
          this.logger.warn(
            `POS_ORDER_STATUS_NOTIFICATION_FAILED status=${status}`,
          );
        }
      }

      // ── WOW#5 단골 마일스톤 알림 (2026-05-31) ─────────────
      //
      // 정책 (restaurants.service.ts shouldSendLoyaltyMilestone 와 1:1):
      //   - COMPLETED 진입 시점에만 발동 (READY 가 아닌 픽업 완료 기준)
      //   - 카운트엔 방금 COMPLETED 된 이 주문 1건이 이미 포함됨
      //     (status 업데이트가 위에서 끝나서 COUNT 가 +1 반영)
      //   - 5/10/15/20/...회차에만 "ORDER_VIP" 알림 발송 (등급 승급/축하)
      //   - 5회차: VIP 승급, 10회+: 누적 단골 축하
      //
      // 실패 시 swallow — 본 주문 상태 변경에 영향 없음.
      if (status === 'COMPLETED' && prevOrder.restaurant_id) {
        try {
          // 같은 식당 + 같은 손님 + COMPLETED 카운트.
          // restaurants.service.getLoyalty 와 정확히 같은 쿼리.
          const { count: visitCount } = await this.supabase.client
            .from('orders')
            .select('id', { count: 'exact', head: true })
            .eq('user_id', prevOrder.user_id)
            .eq('restaurant_id', prevOrder.restaurant_id)
            .eq('status', 'COMPLETED');

          const visits = visitCount ?? 0;
          if (shouldSendLoyaltyMilestone(visits)) {
            const rank = resolveLoyaltyRank(visits);
            // 5회 = VIP 승급, 10/15/20 = 누적 단골 축하
            const isFirstVip = visits === 5;
            const title = isFirstVip
              ? '🎉 VIP 단골 승급!'
              : `🏆 단골 ${visits}회차 달성`;
            const msg = isFirstVip
              ? '이 식당의 VIP 단골이 되셨어요. 다음 방문도 기대할게요'
              : `벌써 ${visits}번째 방문이에요. 사장님이 알아볼지도 몰라요`;

            await this.notificationsService.createNotification({
              userId: prevOrder.user_id,
              type: 'ORDER_VIP',
              title,
              message: msg,
              pushData: {
                orderId,
                restaurantId: prevOrder.restaurant_id,
                visitCount: String(visits),
                rank,
              },
            });
            this.logger.log(
              `POS_LOYALTY_NOTIFICATION_SENT visits=${visits} rank=${rank}`,
            );
          }
        } catch (loyaltyErr: any) {
          // 단골 알림 실패는 전체 흐름을 막지 않음 — 로그만.
          this.logger.warn('POS_LOYALTY_NOTIFICATION_FAILED');
        }
      }
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

    // 응답 유실 뒤 같은 취소를 재시도해도 실패로 바꾸지 않는다.
    if (order.status === 'CANCELLED') {
      const wasSimulated = order.payment_key?.startsWith('sim_') ?? false;
      return {
        id: orderId,
        status: 'CANCELLED',
        refundAmount: order.total_price,
        refundMethod: wasSimulated
          ? 'SIMULATED'
          : order.payment_key
            ? 'TOSS_CANCEL'
            : 'NO_PAYMENT_KEY',
        reason: reason ?? '점주 취소',
        alreadyCancelled: true,
        reconciled: true,
      };
    }

    // 2) 거절 가능 상태 검증
    //   - CANCELLED / COMPLETED / DONE / PREPARING / READY 모두 거절 불가
    //   - PAID / PENDING 만 거절 가능 (조리 시작 전)
    //   - 2026-05-31: 옛 ACCEPTED 표기는 발급 자체가 안 되므로 제거.
    const cancelableStatuses = new Set(['PAID', 'PENDING']);
    if (!cancelableStatuses.has(order.status)) {
      throw new ConflictException({
        statusCode: 409,
        code: 'ORDER_NOT_CANCELLABLE',
        message:
          `이미 ${order.status} 상태인 주문은 취소할 수 없습니다. ` +
          '조리 시작 후엔 거절 불가입니다.',
        retryable: false,
        orderId,
      });
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

    // 2026-05-15 회귀 fix (폰 라이브 검증 — SIMULATE 환불 불가):
    //   SIMULATE(가상) 결제는 payment_key 가 'sim_' prefix 로 실제 토스
    //   결제가 아니다. 기존엔 무조건 토스 cancel API 호출 → NOT_FOUND_PAYMENT
    //   → 원자성 가드가 status 를 PAID 에 영구히 묶음 (데모 거절 시 주문 갇힘).
    //   재발방지: sim_ prefix 는 실제 돈이 안 나갔으므로 토스 cancel 을
    //   스킵하고 바로 CANCELLED. 실제 토스결제만 cancelPayment 호출(원자성 유지).
    const isSimulated = order.payment_key?.startsWith('sim_') ?? false;

    if (
      order.payment_key &&
      order.payment_key.trim().length > 0 &&
      !isSimulated
    ) {
      try {
        refundResult = await this.paymentsService.cancelPayment(
          order.payment_key,
          reason ?? '점주 취소',
          orderId,
        );
      } catch (refundError: any) {
        this.logger.error('POS_REFUND_FAILED_STATUS_UNCHANGED');
        // 원자성 — 실제 결제 환불 실패 시 status 도 변경하지 않고 예외 전파.
        throw refundError;
      }
    } else if (isSimulated) {
      this.logger.log('POS_SIMULATED_PAYMENT_CANCELLED');
    }

    // 4) 환불 성공(또는 payment_key 없음) → 상태 CANCELLED 로 변경
    const cancelUpdate = this.supabase.client
      .from('orders')
      .update({ status: 'CANCELLED', updated_at: new Date().toISOString() })
      .eq('id', orderId)
      .eq('status', order.status);
    const snapshotMatchedUpdate =
      order.payment_key === null || order.payment_key === undefined
        ? cancelUpdate.is('payment_key', null)
        : cancelUpdate.eq('payment_key', order.payment_key);
    const { data: cancelledOrder, error: cancelUpdateError } =
      await snapshotMatchedUpdate
      .select('id, status')
      .maybeSingle();

    if (
      cancelUpdateError ||
      !cancelledOrder ||
      cancelledOrder.status !== 'CANCELLED'
    ) {
      const externalRefundCompleted = refundResult !== null;

      // 같은 주문의 동시 취소 요청이 모두 결제사에서 멱등 성공한 뒤,
      // 한 요청만 조건부 UPDATE를 선점할 수 있다. 0-row 또는 불확실한
      // UPDATE 오류가 나도 현재 DB가 이미 CANCELLED라면 성공으로 조정한다.
      const { data: reconciledOrder, error: reconcileError } =
        await this.supabase.client
          .from('orders')
          .select('id, status, total_price, payment_key')
          .eq('id', orderId)
          .maybeSingle();

      if (!reconcileError && reconciledOrder?.status === 'CANCELLED') {
        this.logger.warn('POS_CANCEL_STATUS_ALREADY_RECONCILED');
        return {
          id: orderId,
          status: 'CANCELLED',
          refundAmount: refundResult?.cancelAmount ?? order.total_price,
          refundMethod: refundResult ? 'TOSS_CANCEL' : 'NO_PAYMENT_KEY',
          canceledAt: refundResult?.canceledAt,
          reason: reason ?? '점주 취소',
          reconciled: true,
        };
      }

      if (externalRefundCompleted && order.payment_key) {
        const refundReconciled =
          await this.reconcileRefundedOrderToCancelled(
            orderId,
            order.payment_key,
          );
        if (refundReconciled) {
          this.logger.warn('POS_REFUND_PREPARATION_RACE_RECONCILED');
          return {
            id: orderId,
            status: 'CANCELLED',
            refundAmount: refundResult?.cancelAmount ?? order.total_price,
            refundMethod: 'TOSS_CANCEL',
            canceledAt: refundResult?.canceledAt,
            reason: reason ?? '점주 취소',
            reconciled: true,
            fulfillmentRaceReconciled: true,
          };
        }
      }

      // PENDING/no-key 스냅샷 뒤 Toss 승인이 먼저 PAID/key를 기록한 경우,
      // 오래된 취소로 PAID를 덮지 않고 최신 결제키를 다시 읽어 환불한다.
      if (
        !externalRefundCompleted &&
        !reconcileError &&
        reconciledOrder?.status === 'PAID' &&
        typeof reconciledOrder.payment_key === 'string' &&
        reconciledOrder.payment_key.length > 0
      ) {
        this.logger.warn('POS_CANCEL_PAYMENT_RACE_RETRYING');
        return this.cancelOrder(orderId, reason);
      }

      this.logger.error(
        `POS_CANCEL_STATUS_PERSIST_FAILED externalRefundCompleted=${externalRefundCompleted} ` +
          `dbError=${cancelUpdateError ? 'present' : 'none'} ` +
          `matchedRow=${cancelledOrder ? 'yes' : 'no'} ` +
          `reconcileError=${reconcileError ? 'present' : 'none'}`,
      );
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: externalRefundCompleted
          ? 'REFUND_COMPLETED_DB_SYNC_PENDING'
          : 'ORDER_CANCEL_DB_SYNC_FAILED',
        message: externalRefundCompleted
          ? '환불은 완료됐지만 주문 상태 저장을 확인하지 못했습니다. 같은 주문으로 다시 시도해주세요.'
          : '주문 취소 상태를 저장하지 못했습니다. 다시 시도해주세요.',
        retryable: true,
        reconciliationRequired: externalRefundCompleted,
        orderId,
      });
    }

    return {
      id: orderId,
      status: 'CANCELLED',
      refundAmount: refundResult?.cancelAmount ?? order.total_price,
      refundMethod: refundResult ? 'TOSS_CANCEL' : 'NO_PAYMENT_KEY',
      canceledAt: refundResult?.canceledAt,
      reason: reason ?? '점주 취소',
    };
  }

  // 외부 환불은 완료됐지만 조리 상태 전이가 먼저 DB를 선점한 경우의
  // 단기 안전망. 최신 상태/결제키를 매번 다시 확인하고 제한 횟수 CAS한다.
  // 장기적으로는 REFUNDING 상태 + durable reconciliation worker가 필요하다.
  private async reconcileRefundedOrderToCancelled(
    orderId: string,
    paymentKey: string,
  ): Promise<boolean> {
    const reconcilableStatuses = new Set([
      'PAID',
      'PREPARING',
      'READY',
      'COMPLETED',
    ]);

    for (let attempt = 0; attempt < 5; attempt += 1) {
      const { data: current, error: readError } = await this.supabase.client
        .from('orders')
        .select('id, status, payment_key')
        .eq('id', orderId)
        .maybeSingle();
      if (readError || !current) return false;
      if (current.status === 'CANCELLED') return true;
      if (
        current.payment_key !== paymentKey ||
        !reconcilableStatuses.has(current.status)
      ) {
        return false;
      }

      const { data: cancelled, error: updateError } =
        await this.supabase.client
          .from('orders')
          .update({ status: 'CANCELLED', updated_at: new Date().toISOString() })
          .eq('id', orderId)
          .eq('status', current.status)
          .eq('payment_key', paymentKey)
          .select('id, status')
          .maybeSingle();
      if (updateError) return false;
      if (cancelled?.status === 'CANCELLED') return true;
    }

    return false;
  }

  // ══════════════════════════════════════════════════════════
  // 2026-05-31 WOW#1: 사장님 "오늘의 한 줄" 업데이트
  //
  // 입력:
  //   · restaurantId — assertPosAccessTo 로 권한 검증 끝난 상태에서 호출
  //   · note         — string(≤200자, trim 완료) 또는 null
  //                    컨트롤러에서 빈 문자열은 이미 null 로 normalize 됨.
  //
  // 처리:
  //   · restaurants.todays_note 컬럼만 UPDATE.
  //   · returning 절로 변경 결과 (id, todays_note) 만 받아 응답에 동봉.
  //   · 식당 ID 가 잘못된 경우(존재하지 않음) PostgREST 가 row 0개를 반환 →
  //     NotFoundException 으로 전환해 호출부에 명확한 에러 전파.
  //
  // 응답:
  //   { restaurantId, todaysNote }
  //
  // 회귀 안전성:
  //   · DB 컬럼이 없는(마이그레이션 미적용) 환경에서는 UPDATE 가 컬럼 미존재 에러를
  //     던지므로 컨트롤러가 500 으로 응답. silent 무시(빈 결과) 방지.
  //   · 2026-05-31 fix: select 절에 restaurants.updated_at 포함 시 컬럼 미존재 →
  //     500 회귀가 있었음. updated_at 은 응답에서 노출하지 않으므로 select 에서 제거.
  //     필요해지면 backend/scripts/migrations/2026-05-31-add-restaurants-updated-at.sql 적용.
  // ══════════════════════════════════════════════════════════
  async updateTodaysNote(
    restaurantId: string,
    note: string | null,
  ): Promise<{
    restaurantId: string;
    todaysNote: string | null;
  }> {
    // 2026-05-31 fix: 기존 구현은 .select('id, todays_note, updated_at') 였으나
    //   restaurants 테이블에 updated_at 컬럼이 없는 환경(현 production/local)에서
    //   PostgREST 가 "column restaurants.updated_at does not exist" 로 500 을 던졌다.
    //   응답 컨트랙트({ restaurantId, todaysNote })에는 updatedAt 이 노출되지 않아
    //   select 와 반환 타입에서 updated_at 을 제거한다. (CLAUDE.md DB 스키마 변경 규칙 위반 복구)
    const { data, error } = await this.supabase.client
      .from('restaurants')
      .update({ todays_note: note })
      .eq('id', restaurantId)
      .select('id, todays_note')
      .maybeSingle();

    if (error) {
      this.logger.error('POS_TODAYS_NOTE_PERSIST_FAILED');
      throw new InternalServerErrorException(
        '오늘의 안내를 저장하지 못했습니다.',
      );
    }
    if (!data) {
      throw new NotFoundException('식당을 찾을 수 없습니다.');
    }

    return {
      restaurantId: data.id as string,
      todaysNote: (data.todays_note as string | null) ?? null,
    };
  }

  // ══════════════════════════════════════════════════════════
  // WOW 포인트 2순위 — 사장 라이브 카메라 한 장 (2026-05-31)
  //
  // 흐름:
  //   1) LSPOS 가 카메라 캡처 → multipart/form-data 로 백엔드에 전송
  //   2) 백엔드 (이 메서드) 가 Supabase Storage `order-photos` 버킷에 업로드
  //      (service_role 이라 anon 키 노출 없이 안전)
  //   3) public URL 을 orders.completion_photo_url 에 저장
  //   4) 손님 추적 화면이 3초 폴링 도중 completionPhotoUrl 수신 → 페이드인
  //
  // 보안:
  //   컨트롤러가 assertPosAccessTo 로 매장 권한 검증 후 호출
  //   → 다른 매장 주문에 사진 첨부 불가
  //
  // 사진 파일 정책:
  //   - 확장자: jpg/jpeg/png/webp 허용 (mime 도 동일하게 검증)
  //   - 크기: 5MB 이하 (multer 단에서 1차 컷, 서비스에서도 방어)
  //   - 파일명: `<orderId>/<timestamp>.<ext>` — 폴더 분리로 디버깅 편의
  // ══════════════════════════════════════════════════════════

  /// POS 가 업로드한 조리 완료 사진을 Storage 에 저장하고
  /// orders.completion_photo_url 컬럼을 갱신한다.
  ///
  /// 반환: 저장된 public URL + 변경 시각.
  async saveCompletionPhoto(
    orderId: string,
    file: {
      buffer: Buffer;
      mimetype: string;
      originalname: string;
      size: number;
    },
  ): Promise<{ id: string; completionPhotoUrl: string; updatedAt: string }> {
    // 1) 입력 검증 — 5MB 초과 시 거부 (multer limits 와 이중 방어)
    const MAX_SIZE = 5 * 1024 * 1024;
    if (!file || file.size === 0) {
      throw new NotFoundException('업로드된 사진이 없습니다.');
    }
    if (file.size > MAX_SIZE) {
      throw new InternalServerErrorException(
        '사진 크기가 5MB 를 초과합니다.',
      );
    }

    // mime 검증 — 허용 외 거부 (악성 업로드 차단)
    const ALLOWED_MIME = new Set([
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/webp',
    ]);
    if (!ALLOWED_MIME.has(file.mimetype)) {
      throw new InternalServerErrorException(
        `허용되지 않은 사진 형식: ${file.mimetype}`,
      );
    }

    // 2) 파일명 구성 — `<orderId>/<timestamp>.<ext>`
    //   같은 주문에 여러 번 업로드해도 충돌 안 나도록 timestamp 포함.
    //   확장자는 mime 기준으로 정규화 (originalname 의 .HEIC 등 차단).
    const extMap: Record<string, string> = {
      'image/jpeg': 'jpg',
      'image/jpg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
    };
    const ext = extMap[file.mimetype] ?? 'jpg';
    const objectPath = `${orderId}/${Date.now()}.${ext}`;

    // 3) Storage 업로드
    //   upsert: false — 같은 경로 충돌이면 명시적으로 실패 (디버깅 편의)
    //   service_role 클라이언트라 RLS bypass.
    const { error: uploadError } = await this.supabase.client.storage
      .from('order-photos')
      .upload(objectPath, file.buffer, {
        contentType: file.mimetype,
        upsert: false,
      });

    if (uploadError) {
      this.logger.error('POS_COMPLETION_PHOTO_UPLOAD_FAILED');
      throw new InternalServerErrorException('사진을 업로드하지 못했습니다.');
    }

    // 4) public URL 획득 — bucket 이 public 이면 즉시 사용 가능한 영구 URL
    const { data: urlData } = this.supabase.client.storage
      .from('order-photos')
      .getPublicUrl(objectPath);

    const publicUrl = urlData?.publicUrl;
    if (!publicUrl) {
      throw new InternalServerErrorException(
        'Storage public URL 생성 실패',
      );
    }

    // 5) orders.completion_photo_url 갱신
    const { data: updated, error: updateError } = await this.supabase.client
      .from('orders')
      .update({ completion_photo_url: publicUrl })
      .eq('id', orderId)
      .select('id, updated_at')
      .single();

    if (updateError || !updated) {
      this.logger.error('POS_COMPLETION_PHOTO_PERSIST_FAILED');
      throw new InternalServerErrorException(
        '사진 URL 저장에 실패했습니다.',
      );
    }

    // 6) FCM 푸시 — best-effort. 손님이 주문 추적 화면을 열어두지 않아도
    //    푸시로 "사장님이 사진을 보냈어요" 안내. data 에 type/url 동봉.
    //    상태 전이와 별개 이벤트라 createNotification 의 ORDER_* 와 충돌 X.
    try {
      const { data: orderForPush } = await this.supabase.client
        .from('orders')
        .select('user_id')
        .eq('id', orderId)
        .single();
      if (orderForPush?.user_id) {
        await this.notificationsService.createNotification({
          userId: orderForPush.user_id,
          type: 'COMPLETION_PHOTO',
          title: '사장님이 사진을 보냈어요',
          message: '조리 완료 사진을 주문 추적에서 확인하세요',
          pushData: {
            orderId,
            url: publicUrl,
          },
        });
      }
    } catch (notifErr: any) {
      // 알림 실패는 사진 업로드 흐름에 영향 없음 — 로그만
      this.logger.warn('POS_COMPLETION_PHOTO_NOTIFICATION_FAILED');
    }

    return {
      id: updated.id,
      completionPhotoUrl: publicUrl,
      updatedAt: updated.updated_at,
    };
  }

  // ══════════════════════════════════════════════════════════
  // ── POS-13: Toss POS 시뮬 결제 (2026-05-31) ──
  //
  // 시연용 시뮬 단계 — 실제 토스 POS API 미연동.
  // POS 단말에서 사장님이 매장 손님에게 직접 결제를 받는 흐름을 모사한다.
  //
  // 동작:
  //   1) 주문 존재 + 현재 상태 확인 (이미 PAID 면 멱등 반환 — 새 업데이트 X)
  //   2) PENDING 상태에서만 결제 가능 (재결제·이미 진행 중 주문 차단)
  //   3) method 에 따라 payment_method 결정:
  //        - CARD → 'POS_TOSS' (POS 토스 카드 결제 시뮬)
  //        - CASH → 'POS_CASH' (POS 현금 수납)
  //   4) status='PAID' + payment_method 일괄 UPDATE
  //   5) approvedAt 은 DB 의 updated_at(트리거가 NOW() 로 갱신) 그대로 사용
  //
  // 멱등성 (Q3 원자성과 동일 원칙):
  //   - 이미 PAID/PREPARING/READY/COMPLETED 인 주문은 새 업데이트 없이 현재 상태 반환.
  //     같은 결제 요청을 두 번 눌러도 부작용 없음.
  //   - REFUNDED/CANCELLED 같은 종료 상태는 명시적 거절(409 의미) 로 throw.
  //
  // 보안:
  //   컨트롤러에서 JwtAuthGuard + assertPosAccessTo 통과 후 진입.
  //
  // receivedAmount:
  //   현금 결제 시 사장이 받은 금액(거스름돈 표시용). DB 에는 저장 X — UI 즉시 표시 전용.
  //   추후 cash 거스름돈 이력이 필요해지면 별도 컬럼 추가 (현재는 시연 임팩트 작아 미저장).
  // ══════════════════════════════════════════════════════════
  async chargeViaPosToss(
    orderId: string,
    method: 'CARD' | 'CASH',
    _receivedAmount?: number,
  ): Promise<{
    orderId: string;
    status: string;
    paymentMethod: string;
    approvedAt: string;
  }> {
    if (
      method === 'CARD' &&
      !(
        process.env.ALLOW_POS_CARD_SIMULATION === 'true' &&
        process.env.NODE_ENV !== 'production'
      )
    ) {
      throw new ForbiddenException({
        statusCode: 403,
        code: 'POS_CARD_SIMULATION_DISABLED',
        message: '실제 POS 카드 승인 연동 전에는 카드 결제 시뮬레이션을 사용할 수 없습니다.',
        retryable: false,
        orderId,
      });
    }

    // 1) 주문 존재 + 현재 상태 사전 확인 (idempotent 분기).
    const { data: existing, error: readError } = await this.supabase.client
      .from('orders')
      .select('id, status, payment_method, updated_at')
      .eq('id', orderId)
      .single();

    if (readError || !existing) {
      throw new NotFoundException('주문을 찾을 수 없습니다.');
    }

    // 2) 이미 PAID 이상이면 멱등 — 새 UPDATE 없이 현재 상태 그대로 반환.
    //    같은 결제 버튼 두 번 클릭 / 네트워크 재시도 시 부작용 차단.
    const paidStatuses = new Set([
      'PAID',
      'PREPARING',
      'READY',
      'COMPLETED',
    ]);
    if (paidStatuses.has(existing.status)) {
      this.logger.log(
        `POS_PAYMENT_ALREADY_FINALIZED status=${existing.status}`,
      );
      return {
        orderId: existing.id,
        status: existing.status,
        paymentMethod: (existing.payment_method as string | null) ?? 'POS_TOSS',
        approvedAt: existing.updated_at,
      };
    }

    // 3) 종료 상태(취소/환불) 는 명시적으로 거절 — 재결제 우회 차단.
    if (
      existing.status === 'CANCELLED' ||
      existing.status === 'REFUNDED'
    ) {
      throw new InternalServerErrorException(
        `${existing.status} 상태인 주문은 POS 결제할 수 없습니다.`,
      );
    }

    // 4) PENDING 외 상태(없을 가능성 높지만 안전망) 차단.
    if (existing.status !== 'PENDING') {
      throw new InternalServerErrorException(
        `${existing.status} 상태인 주문은 POS 결제 흐름 대상이 아닙니다.`,
      );
    }

    // 5) method → payment_method ENUM 매핑.
    //    POS_TOSS = POS 단말 토스 카드 결제 시뮬, POS_CASH = POS 현금 수납.
    const paymentMethod = method === 'CARD' ? 'POS_TOSS' : 'POS_CASH';

    // 6) status='PAID' + payment_method 동시 업데이트.
    //    2026-06-03: updated_at 트리거가 실DB 에 없으므로 명시적으로 갱신 → approvedAt 으로 활용.
    const nowIso = new Date().toISOString();
    const { data: updated, error: updateError } = await this.supabase.client
      .from('orders')
      .update({ status: 'PAID', payment_method: paymentMethod, updated_at: nowIso })
      .eq('id', orderId)
      .eq('status', 'PENDING')
      .select('id, status, payment_method, updated_at')
      .maybeSingle();

    if (updateError) {
      this.logger.error(`POS_PAYMENT_STATUS_PERSIST_FAILED method=${method}`);
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: 'POS_PAYMENT_DB_SYNC_FAILED',
        message: 'POS 결제 상태를 저장하지 못했습니다. 다시 시도해주세요.',
        retryable: true,
        orderId,
      });
    }

    if (
      !updated ||
      updated.status !== 'PAID' ||
      updated.payment_method !== paymentMethod
    ) {
      const { data: reconciled, error: reconcileError } =
        await this.supabase.client
          .from('orders')
          .select('id, status, payment_method, updated_at')
          .eq('id', orderId)
          .maybeSingle();

      if (
        !reconcileError &&
        reconciled &&
        paidStatuses.has(reconciled.status) &&
        reconciled.payment_method === paymentMethod
      ) {
        return {
          orderId: reconciled.id,
          status: reconciled.status,
          paymentMethod: reconciled.payment_method,
          approvedAt: reconciled.updated_at,
        };
      }

      throw new ConflictException({
        statusCode: 409,
        code: 'POS_PAYMENT_STATE_CHANGED',
        message:
          '주문 상태가 동시에 변경되어 POS 결제를 적용하지 않았습니다. 최신 주문 상태를 확인해주세요.',
        retryable: false,
        orderId,
      });
    }

    this.logger.log(`POS_SIMULATED_PAYMENT_COMPLETED method=${paymentMethod}`);

    return {
      orderId: updated.id,
      status: updated.status,
      paymentMethod:
        (updated.payment_method as string | null) ?? paymentMethod,
      approvedAt: updated.updated_at,
    };
  }

  // ── POS-13: 환불 인터페이스 (기존 토스 환불 미연결 자리) ──
  // 실제 환불은 PaymentsService.cancelPayment 가 처리하므로 이 헬퍼는 자리만 유지.
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  private async refundViaToss(paymentKey: string, amount: number, reason?: string) {
    // TODO: 실제 환불 구현 (현재는 PaymentsService.cancelPayment 가 담당)
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
