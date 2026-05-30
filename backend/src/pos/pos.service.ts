import {
  Injectable,
  InternalServerErrorException,
  Logger,
  NotFoundException,
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
    // 2026-05-15 단계 3: 푸시 알림 hook — 상태 전이 시 손님 user_id 받아두기.
    // notifications.createNotification 이 알림 INSERT + FCM 자동 송신 둘 다 처리.
    //
    // 2026-05-31 WOW#5: COMPLETED 진입 직후 단골 알림 발송 판단을 위해
    // restaurant_id 도 함께 select.
    const { data: prevOrder } = await this.supabase.client
      .from('orders')
      .select('user_id, status, restaurant_id')
      .eq('id', orderId)
      .single();

    const { data, error } = await this.supabase.client
      .from('orders')
      .update({ status })
      .eq('id', orderId)
      .select('id, status, updated_at')
      .single();

    if (error || !data) {
      throw new NotFoundException('주문을 찾을 수 없습니다.');
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
            `[updateOrderStatus] 알림 송신 실패 order=${orderId} ` +
              `status=${status} error=${notifErr?.message}`,
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
              `[loyalty] VIP 알림 발송 user=${prevOrder.user_id} ` +
                `restaurant=${prevOrder.restaurant_id} visits=${visits} rank=${rank}`,
            );
          }
        } catch (loyaltyErr: any) {
          // 단골 알림 실패는 전체 흐름을 막지 않음 — 로그만.
          this.logger.warn(
            `[loyalty] 단골 알림 발송 실패 order=${orderId} ` +
              `error=${loyaltyErr?.message}`,
          );
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

    // 2) 거절 가능 상태 검증
    //   - CANCELLED / COMPLETED / DONE / PREPARING / READY 모두 거절 불가
    //   - PAID / PENDING 만 거절 가능 (조리 시작 전)
    //   - 2026-05-31: 옛 ACCEPTED 표기는 발급 자체가 안 되므로 제거.
    const cancelableStatuses = new Set(['PAID', 'PENDING']);
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
        );
      } catch (refundError: any) {
        this.logger.error(
          `환불 실패 — status 미변경 유지: order=${orderId} ` +
            `payment_key=${order.payment_key} error=${refundError?.message}`,
        );
        // 원자성 — 실제 결제 환불 실패 시 status 도 변경하지 않고 예외 전파.
        throw refundError;
      }
    } else if (isSimulated) {
      this.logger.log(
        `SIMULATE 결제 — 토스 cancel 스킵, 즉시 CANCELLED: order=${orderId}`,
      );
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
  //   { restaurantId, todaysNote, updatedAt }
  //
  // 회귀 안전성:
  //   · DB 컬럼이 없는(마이그레이션 미적용) 환경에서는 UPDATE 가 컬럼 미존재 에러를
  //     던지므로 컨트롤러가 500 으로 응답. silent 무시(빈 결과) 방지.
  // ══════════════════════════════════════════════════════════
  async updateTodaysNote(
    restaurantId: string,
    note: string | null,
  ): Promise<{
    restaurantId: string;
    todaysNote: string | null;
    updatedAt: string | null;
  }> {
    const { data, error } = await this.supabase.client
      .from('restaurants')
      .update({ todays_note: note })
      .eq('id', restaurantId)
      .select('id, todays_note, updated_at')
      .maybeSingle();

    if (error) {
      this.logger.error(
        `[updateTodaysNote] 업데이트 실패 restaurant=${restaurantId} error=${error.message}`,
      );
      // 컬럼 미존재 등 DB 측 오류는 그대로 전파해 디버깅 용이.
      throw error;
    }
    if (!data) {
      throw new NotFoundException('식당을 찾을 수 없습니다.');
    }

    return {
      restaurantId: data.id as string,
      todaysNote: (data.todays_note as string | null) ?? null,
      // updated_at 컬럼이 없는 옛 스키마에서도 안전하게 null 폴백.
      updatedAt: (data as { updated_at?: string | null }).updated_at ?? null,
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
      this.logger.error(
        `Storage 업로드 실패: order=${orderId} path=${objectPath} ` +
          `error=${uploadError.message}`,
      );
      throw new InternalServerErrorException(
        `사진 업로드 실패: ${uploadError.message}`,
      );
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
      this.logger.error(
        `orders.completion_photo_url 갱신 실패: order=${orderId} ` +
          `error=${updateError?.message}`,
      );
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
      this.logger.warn(
        `[saveCompletionPhoto] 푸시 송신 실패 order=${orderId} ` +
          `error=${notifErr?.message}`,
      );
    }

    return {
      id: updated.id,
      completionPhotoUrl: publicUrl,
      updatedAt: updated.updated_at,
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
