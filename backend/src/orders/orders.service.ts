import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  BadRequestException,
  InternalServerErrorException,
  Logger,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 주문/결제 비즈니스 로직
//
// 티켓: CORE-09(메뉴 충돌 검증), CORE-10(결제 레이어),
//       CU-17(그룹 주문 검토), CU-18(결제 방식 선택),
//       CU-19(결제 호출/가상 결제)
//
// 주문 상태: PENDING → PAID → PREPARING → READY → COMPLETED
//           PENDING → CANCELLED (취소)
// ══════════════════════════════════════════════════════════

export interface CreateOrderDto {
  sessionId: string;
  items: { menuItemId: string; quantity: number }[];
  paymentMethod: string; // CARD | TRANSFER | CASH | SIMULATE
}

export interface UpdateOrderStatusDto {
  status: string;
}

type NormalizedPaymentMethod = 'TOSS' | 'CARD' | 'CASH' | 'SIMULATE';

@Injectable()
export class OrdersService {
  private readonly logger = new Logger(OrdersService.name);

  constructor(private readonly supabase: SupabaseService) {}

  // ── POST /orders — 주문 생성 (CU-17 + CORE-09) ────────
  async createOrder(userId: string, dto: CreateOrderDto) {
    // 1. 메뉴 아이템 가격 조회 + 충돌 검증 (CORE-09)
    const menuItemIds = dto.items.map((i) => i.menuItemId);

    const { data: menuItems, error: menuError } = await this.supabase.client
      .from('menu_items')
      .select('id, name, price, restaurant_id')
      .in('id', menuItemIds);

    if (menuError || !menuItems || menuItems.length === 0) {
      throw new NotFoundException('메뉴 아이템을 찾을 수 없습니다.');
    }

    // CORE-09: 메뉴 충돌 검증 — 모든 아이템이 같은 식당인지 확인
    const restaurantIds = new Set(menuItems.map((m) => m.restaurant_id));
    if (restaurantIds.size > 1) {
      // BadRequestException: 클라이언트 입력 오류 → 400 응답
      throw new BadRequestException(
        '서로 다른 식당의 메뉴를 동시에 주문할 수 없습니다.',
      );
    }
    // orders.restaurant_id 컬럼에 들어갈 단일 값
    const restaurantId = menuItems[0].restaurant_id as string;

    // 2026-05-31 자기매장 주문 차단 — 사장이 본인 가게에 주문하는 비정상 흐름 차단.
    //   배경: hyunho 같은 시연 계정이 role 토글로 사장↔손님을 오갈 때, 본인이
    //         운영하는 가게에 주문이 들어가면 사장 화면에서 자기 주문을 받는
    //         이상한 흐름이 됨. 일반 사장 계정도 OWNER+APPROVED 라면 자기 가게
    //         주문은 금지하는 게 비즈니스 룰.
    const { data: orderingUser } = await this.supabase.client
      .from('users')
      .select('role, restaurant_id')
      .eq('id', userId)
      .maybeSingle();
    if (
      orderingUser?.role === 'OWNER' &&
      orderingUser?.restaurant_id === restaurantId
    ) {
      throw new BadRequestException(
        '본인이 운영하는 매장에는 주문할 수 없어요. 손님 계정으로 로그인하거나 다른 매장을 선택해주세요.',
      );
    }

    // 2. 총 금액 계산
    const menuMap = new Map(menuItems.map((m) => [m.id, m]));
    let totalPrice = 0;
    const orderItems: {
      menuItemId: string;
      quantity: number;
      price: number;
    }[] = [];

    for (const item of dto.items) {
      const menu = menuMap.get(item.menuItemId);
      if (!menu) {
        throw new NotFoundException(
          `메뉴 아이템(${item.menuItemId})을 찾을 수 없습니다.`,
        );
      }
      const itemPrice = menu.price * item.quantity;
      totalPrice += itemPrice;
      orderItems.push({
        menuItemId: item.menuItemId,
        quantity: item.quantity,
        price: menu.price, // 주문 시점 스냅샷
      });
    }

    // 3. orders + order_items 원자적 생성
    // PostgreSQL 함수 안에서 어느 INSERT든 실패하면 주문 전체가 롤백된다.
    const paymentMethod = this.normalizePaymentMethod(dto.paymentMethod);
    const { data: orderRaw, error: orderError } =
      await this.supabase.client.rpc('create_order_with_items', {
        p_session_id: dto.sessionId,
        p_user_id: userId,
        p_restaurant_id: restaurantId,
        p_total_price: totalPrice,
        p_payment_method: paymentMethod,
        p_items: orderItems,
      });

    if (orderError || !orderRaw) {
      this.logger.error(
        `Order creation RPC failed: ${orderError?.message ?? 'empty response'}`,
      );
      throw new InternalServerErrorException('주문을 생성할 수 없습니다.');
    }

    // RPC 응답은 JSON 객체이므로 필요한 공개 응답 필드만 좁혀 사용한다.
    const order = orderRaw as unknown as {
      id: string;
      createdAt?: string;
      created_at?: string;
    };

    // 4. CORE-10: 결제 처리 (현재는 가상 결제 시뮬레이션)
    const paymentResult = await this.processPayment(
      order.id,
      totalPrice,
      paymentMethod,
    );

    return {
      id: order.id,
      sessionId: dto.sessionId,
      status: paymentResult.paid ? 'PAID' : 'PENDING',
      totalPrice,
      paymentMethod,
      paymentKey: paymentResult.paymentKey,
      items: orderItems,
      createdAt: order.createdAt ?? order.created_at,
    };
  }

  // ── 결제수단 정규화 ────────────────────────────────
  // 클라이언트가 보낸 다양한 표기를 DB ENUM(TOSS/CARD/CASH/SIMULATE) 으로 매핑.
  // 모르는 값은 SIMULATE 로 기본 처리 (캡스톤 시연 안전 폴백).
  private normalizePaymentMethod(raw?: string): NormalizedPaymentMethod {
    const v = (raw ?? '').toUpperCase();
    if (v === 'TOSS' || v === 'TRANSFER' || v === 'KAKAOPAY' || v === 'BANK')
      return 'TOSS';
    if (v === 'CARD') return 'CARD';
    if (v === 'CASH') return 'CASH';
    return 'SIMULATE';
  }

  // ── CORE-10: 결제 처리 레이어 ─────────────────────────
  // SIMULATE/CASH: 서버에서 즉시 PAID 처리 (테스트/현금 결제)
  // TOSS: 프론트가 결제위젯 v2로 승인 요청 → 성공 시
  //       /api/payments/confirm 엔드포인트에서 최종 승인 처리
  //       (이 단계에서는 주문만 PENDING 상태로 둔다)
  private async processPayment(
    orderId: string,
    _amount: number,
    method: NormalizedPaymentMethod,
  ): Promise<{ paid: boolean; paymentKey: string | null }> {
    if (method === 'SIMULATE' || method === 'CASH') {
      // 가상 결제: 즉시 성공 처리
      const paymentKey = `sim_${orderId}_${Date.now()}`;

      const { data: paidOrder, error: paymentUpdateError } =
        await this.supabase.client
          .from('orders')
          .update({ status: 'PAID', payment_key: paymentKey })
          .eq('id', orderId)
          .eq('status', 'PENDING')
          .select('id, status, payment_key')
          .single();

      if (
        paymentUpdateError ||
        !paidOrder ||
        paidOrder.status !== 'PAID' ||
        paidOrder.payment_key !== paymentKey
      ) {
        this.logger.error(
          `Payment status update failed: ${
            paymentUpdateError?.message ?? 'updated row did not match'
          }`,
        );
        throw new InternalServerErrorException(
          '결제 상태를 저장할 수 없습니다.',
        );
      }

      return { paid: true, paymentKey };
    }

    // TOSS: 주문만 생성해두고 승인은 프론트가 /payments/confirm 에서 처리
    // 여기서는 PENDING 상태 유지 + paymentKey 없음
    return { paid: false, paymentKey: null };
  }

  // ── GET /orders/:id ───────────────────────────────────
  // 2026-05-13 보안 패치: 본인 주문 또는 같은 세션 멤버만 조회 가능.
  // 그룹 식사 특성상 같은 세션 멤버가 서로의 주문 상태/금액 확인할 수 있어야 함.
  async getOrderById(orderId: string, requesterId: string) {
    // 2026-05-15 별점/리뷰 표시 위해 review_score/review_text/review_at 추가 select.
    // 컬럼이 없는 환경(마이그레이션 미적용)에서도 PostgREST 는 silent fail 하지 않고
    // 에러를 반환하므로 마이그레이션 적용 여부 확인 후 노출.
    // 2026-05-15 자율 E2E build 회귀: select 문자열을 ' + ' 로 분리하면
    // supabase 타입 추론이 GenericStringError 로 떨어져 빌드 실패.
    // 한 줄 리터럴 + as 캐스팅으로 수정.
    type OrderRow = {
      id: string;
      session_id: string;
      user_id: string;
      status: string;
      total_price: number;
      payment_key: string | null;
      created_at: string;
      updated_at: string;
      restaurant_id?: string | null;
      review_score?: number | null;
      review_text?: string | null;
      review_at?: string | null;
      // 2026-05-31 WOW2: 사장 라이브 카메라 사진 URL (Storage public URL).
      //   null = 아직 사진 첨부 안 됨. 손님 추적 화면이 hero 이미지로 표시.
      completion_photo_url?: string | null;
    };
    // 2026-05-15 회귀 fix (폰 라이브 검증 — 주문 상세 404):
    //   별점 commit d07d3ca 가 select 에 review_* 컬럼을 넣었는데,
    //   add-order-review.sql 미적용 환경에서는 PostgREST 가 "없는 컬럼"
    //   때문에 쿼리 전체를 실패시켜 → 주문 상세/추적 화면 전체가 깨짐.
    //   재발방지: 확실히 존재하는 기본 컬럼만 먼저 조회하고,
    //   review_* 는 별도 안전 조회(실패 시 null)로 분리해 스키마에
    //   회복탄력적이게 만든다. ([[feedback-db-schema-migration]])
    const { data: orderRaw, error } = await this.supabase.client
      .from('orders')
      .select(
        'id, session_id, user_id, status, total_price, payment_key, created_at, updated_at, restaurant_id',
      )
      .eq('id', orderId)
      .single();

    if (error || !orderRaw) {
      throw new NotFoundException('주문을 찾을 수 없습니다.');
    }
    const order = orderRaw as unknown as OrderRow;

    // 2026-05-31 WOW2: completion_photo_url 별도 안전 조회 — review_* 와 동일
    // 회복탄력 패턴. 마이그레이션 미적용 환경에서도 silent fail 안 하도록 분리.
    try {
      const { data: photoRaw } = await this.supabase.client
        .from('orders')
        .select('completion_photo_url')
        .eq('id', orderId)
        .single();
      if (photoRaw) {
        order.completion_photo_url =
          (photoRaw as { completion_photo_url?: string | null })
            .completion_photo_url ?? null;
      }
    } catch {
      order.completion_photo_url = null;
    }

    // review_* 별도 안전 조회 — 컬럼 미존재(마이그레이션 전)면 조용히 null
    try {
      const { data: reviewRaw } = await this.supabase.client
        .from('orders')
        .select('review_score, review_text, review_at')
        .eq('id', orderId)
        .single();
      if (reviewRaw) {
        const rv = reviewRaw as {
          review_score?: number | null;
          review_text?: string | null;
          review_at?: string | null;
        };
        order.review_score = rv.review_score ?? null;
        order.review_text = rv.review_text ?? null;
        order.review_at = rv.review_at ?? null;
      }
    } catch {
      order.review_score = null;
      order.review_text = null;
      order.review_at = null;
    }

    // 본인 주문이 아니면 같은 세션 멤버인지 확인
    if (order.user_id !== requesterId) {
      const { data: membership } = await this.supabase.client
        .from('session_members')
        .select('user_id')
        .eq('session_id', order.session_id)
        .eq('user_id', requesterId)
        .maybeSingle();
      if (!membership) {
        throw new ForbiddenException('주문 조회 권한이 없어요.');
      }
    }

    // 주문 아이템 조회 — 2026-05-16: menu_items.prep_time_minutes 도 함께 가져와 ETA 계산
    const { data: items } = await this.supabase.client
      .from('order_items')
      .select(
        'id, menu_item_id, quantity, price, menu_items(name, prep_time_minutes)',
      )
      .eq('order_id', orderId);

    // 2026-05-16 배민 패턴 — 예상 픽업 시각 계산
    // 한 주문 중 가장 오래 걸리는 메뉴 기준 = max(prep_time_minutes)
    // 기준 시각: PREPARING 이면 updated_at(조리 시작 시각), 그 외에는 created_at
    // estimated_ready_at 은 null 가능 (READY/COMPLETED/CANCELLED 등에는 굳이 표시 X)
    //
    // 2026-05-31 회귀 fix: CLAUDE.md 의 현재 사용 ENUM
    // (PENDING/PAID/PREPARING/READY/COMPLETED/CANCELLED) 와 정합. 옛 표기
    // ACCEPTED 는 백엔드가 더 이상 발급하지 않으므로 분기에서 제거.
    let estimatedReadyAt: string | null = null;
    const activeStatuses = ['PAID', 'PREPARING'];
    if (activeStatuses.includes(order.status) && items && items.length > 0) {
      let maxPrep = 0;
      for (const it of items as any[]) {
        const m: number = Number(it.menu_items?.prep_time_minutes ?? 15);
        if (m > maxPrep) maxPrep = m;
      }
      if (maxPrep > 0) {
        const base =
          order.status === 'PAID'
            ? new Date(order.created_at)
            : new Date(order.updated_at);
        estimatedReadyAt = new Date(
          base.getTime() + maxPrep * 60_000,
        ).toISOString();
      }
    }

    return {
      id: order.id,
      sessionId: order.session_id,
      userId: order.user_id,
      status: order.status,
      totalPrice: order.total_price,
      paymentKey: order.payment_key,
      createdAt: order.created_at,
      updatedAt: order.updated_at,
      // 2026-05-15 별점/리뷰 — 손님 어플이 "이미 작성된 리뷰" 인지 판단해
      // 별점 카드 노출 여부를 결정하기 위해 함께 내려보낸다.
      restaurantId: (order as { restaurant_id?: string }).restaurant_id ?? null,
      reviewScore:
        (order as { review_score?: number | null }).review_score ?? null,
      reviewText:
        (order as { review_text?: string | null }).review_text ?? null,
      reviewAt: (order as { review_at?: string | null }).review_at ?? null,
      // 2026-05-31 WOW2 — 사장 라이브 카메라 사진 URL (null = 미첨부)
      completionPhotoUrl:
        (order as { completion_photo_url?: string | null })
          .completion_photo_url ?? null,
      // 2026-05-16 배민 패턴 — 예상 픽업 시각 (ISO8601, null 가능)
      estimatedReadyAt,
      items: (items ?? []).map((i: any) => ({
        id: i.id,
        menuItemId: i.menu_item_id,
        menuName: i.menu_items?.name,
        prepTimeMinutes: i.menu_items?.prep_time_minutes ?? 15,
        quantity: i.quantity,
        price: i.price,
      })),
    };
  }

  // ── GET /orders/today ─────────────────────────────────
  async getTodayOrders(userId: string) {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const { data, error } = await this.supabase.client
      .from('orders')
      .select('id, session_id, status, total_price, created_at')
      .eq('user_id', userId)
      .gte('created_at', today.toISOString())
      .order('created_at', { ascending: false });

    if (error) {
      // InternalServerErrorException: DB 조회 실패 → 500 응답
      throw new InternalServerErrorException(
        `주문 조회 실패: ${error.message}`,
      );
    }

    return (data ?? []).map((o) => ({
      id: o.id,
      sessionId: o.session_id,
      status: o.status,
      totalPrice: o.total_price,
      createdAt: o.created_at,
    }));
  }

  // ── PATCH /orders/:id/status ──────────────────────────
  // 보안 패치 (2026-05-12):
  //   - 주문 소유자(user_id) 만 변경 가능 (사장은 별도 /pos/orders/:id/status 사용)
  //   - 상태 전이 매트릭스 검증
  async updateOrderStatus(
    orderId: string,
    requesterId: string,
    dto: UpdateOrderStatusDto,
  ) {
    // 주문 조회 + 소유자 검증
    const { data: order, error: orderError } = await this.supabase.client
      .from('orders')
      .select('id, user_id, status')
      .eq('id', orderId)
      .single();
    if (orderError || !order) {
      throw new NotFoundException('주문을 찾을 수 없어요.');
    }
    if (order.user_id !== requesterId) {
      throw new ForbiddenException('본인의 주문만 변경할 수 있어요.');
    }

    // 상태 전이 매트릭스 (손님 입장)
    const VALID_TRANSITIONS: Record<string, ReadonlyArray<string>> = {
      PENDING: ['PAID', 'CANCELLED'],
      PAID: [], // 이후는 POS 권한
      PREPARING: [],
      READY: [],
      COMPLETED: [],
      CANCELLED: [],
    };
    const allowed = VALID_TRANSITIONS[order.status] ?? [];
    if (!allowed.includes(dto.status)) {
      throw new BadRequestException(
        `${order.status} 상태에서 ${dto.status} 로 변경할 수 없어요.`,
      );
    }

    const { data, error } = await this.supabase.client
      .from('orders')
      .update({ status: dto.status })
      .eq('id', orderId)
      .select('id, status, updated_at')
      .single();

    if (error || !data) {
      throw new InternalServerErrorException('주문 상태를 변경하지 못했어요.');
    }

    return { id: data.id, status: data.status, updatedAt: data.updated_at };
  }

  // ══════════════════════════════════════════════════════════
  // 별점/리뷰 (배민 패턴 — 2026-05-15 자율 발전 로드맵)
  //
  // 정책:
  //   - COMPLETED 상태에서만 리뷰 작성 가능
  //   - 본인 주문만 (orders.user_id 비교)
  //   - 1주문 1리뷰 (update 패턴 — 재작성 시 덮어쓰기)
  //   - score 1~5, text 최대 500자 (서비스 단 검증)
  // ══════════════════════════════════════════════════════════

  // ── PATCH /orders/:id/review ───────────────────────────
  // 본인 주문에 별점/리뷰 작성 또는 수정.
  async addReview(
    userId: string,
    orderId: string,
    dto: { score: number; text?: string },
  ) {
    // 입력 검증
    if (!Number.isInteger(dto.score) || dto.score < 1 || dto.score > 5) {
      throw new BadRequestException('별점은 1~5 사이 정수여야 해요.');
    }
    if (dto.text && dto.text.length > 500) {
      throw new BadRequestException('리뷰는 500자 이하로 작성해주세요.');
    }

    // 주문 조회 + 본인 검증 + 상태 검증
    const { data: order, error: getError } = await this.supabase.client
      .from('orders')
      .select('id, user_id, status')
      .eq('id', orderId)
      .single();

    if (getError || !order) {
      throw new NotFoundException('주문을 찾을 수 없어요.');
    }
    if (order.user_id !== userId) {
      throw new ForbiddenException('본인 주문에만 리뷰 작성 가능해요.');
    }
    if (order.status !== 'COMPLETED' && order.status !== 'DONE') {
      throw new BadRequestException('주문이 완료된 후에 리뷰 작성 가능해요.');
    }

    // 리뷰 INSERT/UPDATE (단일 컬럼 update)
    const { data, error } = await this.supabase.client
      .from('orders')
      .update({
        review_score: dto.score,
        review_text: dto.text ?? null,
        review_at: new Date().toISOString(),
      })
      .eq('id', orderId)
      .select('id, review_score, review_text, review_at')
      .single();

    if (error || !data) {
      throw new InternalServerErrorException('리뷰를 저장하지 못했어요.');
    }

    return {
      id: data.id,
      reviewScore: data.review_score,
      reviewText: data.review_text,
      reviewAt: data.review_at,
    };
  }

  // ── GET /restaurants/:id/reviews — 매장 별 리뷰 목록 ───
  // 사장 어플에서 매장 평점/리뷰 보기 용. 공개 정보 — 인증 필요하지만 본인 매장만 권한 X.
  // (향후 사장 권한 검증 추가 가능 — 현재는 단순 조회)
  async getReviewsByRestaurant(restaurantId: string) {
    const { data, error } = await this.supabase.client
      .from('orders')
      .select(
        'id, review_score, review_text, review_at, ' +
          'user:users!orders_user_id_fkey(name)',
      )
      .eq('restaurant_id', restaurantId)
      .not('review_score', 'is', null)
      .order('review_at', { ascending: false })
      .limit(50);

    if (error) {
      throw new InternalServerErrorException('리뷰를 불러오지 못했어요.');
    }

    const reviews = (data ?? []).map((r: any) => ({
      id: r.id,
      score: r.review_score,
      text: r.review_text,
      at: r.review_at,
      authorName: r.user?.name ?? '익명',
    }));

    // 평균 평점 계산
    const sum = reviews.reduce((acc, r) => acc + (r.score ?? 0), 0);
    const avg = reviews.length > 0 ? sum / reviews.length : 0;

    return {
      averageScore: Math.round(avg * 10) / 10, // 소수점 1자리
      count: reviews.length,
      reviews,
    };
  }
}
