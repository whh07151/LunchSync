import { Injectable, NotFoundException } from '@nestjs/common';
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

@Injectable()
export class OrdersService {
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
      throw new Error('서로 다른 식당의 메뉴를 동시에 주문할 수 없습니다.');
    }

    // 2. 총 금액 계산
    const menuMap = new Map(menuItems.map((m) => [m.id, m]));
    let totalPrice = 0;
    const orderItems: { menuItemId: string; quantity: number; price: number }[] = [];

    for (const item of dto.items) {
      const menu = menuMap.get(item.menuItemId);
      if (!menu) {
        throw new NotFoundException(`메뉴 아이템(${item.menuItemId})을 찾을 수 없습니다.`);
      }
      const itemPrice = menu.price * item.quantity;
      totalPrice += itemPrice;
      orderItems.push({
        menuItemId: item.menuItemId,
        quantity: item.quantity,
        price: menu.price, // 주문 시점 스냅샷
      });
    }

    // 3. orders 테이블 INSERT
    const { data: order, error: orderError } = await this.supabase.client
      .from('orders')
      .insert({
        session_id: dto.sessionId,
        user_id: userId,
        total_price: totalPrice,
        status: 'PENDING',
      })
      .select('id, status, total_price, created_at')
      .single();

    if (orderError || !order) {
      throw new Error(`주문 생성 실패: ${orderError?.message}`);
    }

    // 4. order_items 테이블 INSERT
    const orderItemsData = orderItems.map((item) => ({
      order_id: order.id,
      menu_item_id: item.menuItemId,
      quantity: item.quantity,
      price: item.price,
    }));

    await this.supabase.client
      .from('order_items')
      .insert(orderItemsData);

    // 5. CORE-10: 결제 처리 (현재는 가상 결제 시뮬레이션)
    const paymentResult = await this.processPayment(
      order.id,
      totalPrice,
      dto.paymentMethod,
    );

    return {
      id: order.id,
      sessionId: dto.sessionId,
      status: paymentResult.paid ? 'PAID' : 'PENDING',
      totalPrice,
      paymentMethod: dto.paymentMethod,
      paymentKey: paymentResult.paymentKey,
      items: orderItems,
      createdAt: order.created_at,
    };
  }

  // ── CORE-10: 결제 처리 레이어 ─────────────────────────
  // 현재: 가상 결제 (SIMULATE 모드)
  // 추후: Toss Payments API 연동으로 교체
  private async processPayment(
    orderId: string,
    amount: number,
    method: string,
  ): Promise<{ paid: boolean; paymentKey: string | null }> {
    if (method === 'SIMULATE' || method === 'CASH') {
      // 가상 결제: 즉시 성공 처리
      const paymentKey = `sim_${orderId}_${Date.now()}`;

      await this.supabase.client
        .from('orders')
        .update({ status: 'PAID', payment_key: paymentKey })
        .eq('id', orderId);

      return { paid: true, paymentKey };
    }

    // TODO: Toss Payments 실제 연동
    // const response = await fetch('https://api.tosspayments.com/v1/payments/confirm', {
    //   method: 'POST',
    //   headers: {
    //     Authorization: `Basic ${Buffer.from(secretKey + ':').toString('base64')}`,
    //     'Content-Type': 'application/json',
    //   },
    //   body: JSON.stringify({ paymentKey, orderId, amount }),
    // });

    return { paid: false, paymentKey: null };
  }

  // ── GET /orders/:id ───────────────────────────────────
  async getOrderById(orderId: string) {
    const { data: order, error } = await this.supabase.client
      .from('orders')
      .select('id, session_id, user_id, status, total_price, payment_key, created_at, updated_at')
      .eq('id', orderId)
      .single();

    if (error || !order) {
      throw new NotFoundException('주문을 찾을 수 없습니다.');
    }

    // 주문 아이템 조회
    const { data: items } = await this.supabase.client
      .from('order_items')
      .select('id, menu_item_id, quantity, price, menu_items(name)')
      .eq('order_id', orderId);

    return {
      id: order.id,
      sessionId: order.session_id,
      userId: order.user_id,
      status: order.status,
      totalPrice: order.total_price,
      paymentKey: order.payment_key,
      createdAt: order.created_at,
      updatedAt: order.updated_at,
      items: (items ?? []).map((i: any) => ({
        id: i.id,
        menuItemId: i.menu_item_id,
        menuName: i.menu_items?.name,
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
      throw new Error(`주문 조회 실패: ${error.message}`);
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
  async updateOrderStatus(orderId: string, dto: UpdateOrderStatusDto) {
    const { data, error } = await this.supabase.client
      .from('orders')
      .update({ status: dto.status })
      .eq('id', orderId)
      .select('id, status, updated_at')
      .single();

    if (error || !data) {
      throw new NotFoundException('주문을 찾을 수 없습니다.');
    }

    return { id: data.id, status: data.status, updatedAt: data.updated_at };
  }
}
