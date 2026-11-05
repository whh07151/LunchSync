import { Logger } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

export interface PaidOrderPostActionsResult {
  cartSynced: boolean;
  reservationSynced: boolean;
}

// External payment approval is already committed. Failed local actions remain
// retryable by order ID without charging again or consuming the cart twice.
export async function syncPaidOrderPostActions(
  client: SupabaseService['client'],
  logger: Logger,
  orderId: string,
): Promise<PaidOrderPostActionsResult> {
  const result = { cartSynced: false, reservationSynced: false };
  try {
    const { error } = await client.rpc('consume_ordered_session_cart_items', {
      p_order_id: orderId,
    });
    result.cartSynced = !error;
    if (error) logger.warn('PAID_ORDER_CART_SYNC_PENDING');
  } catch {
    logger.warn('PAID_ORDER_CART_SYNC_PENDING');
  }

  try {
    const { data: order, error: orderError } = await client
      .from('orders')
      .select(
        'id, user_id, restaurant_id, status, dining_type, customer_note, payment_method',
      )
      .eq('id', orderId)
      .single();
    if (
      orderError ||
      !order ||
      !['PAID', 'PREPARING', 'READY', 'COMPLETED'].includes(order.status)
    ) {
      logger.warn('PAID_ORDER_RESERVATION_LOOKUP_PENDING');
      return result;
    }
    if (
      order.dining_type === 'TAKEOUT' ||
      ['POS_CASH', 'POS_TOSS'].includes(order.payment_method)
    )
      return result;

    const { data: existing, error: lookupError } = await client
      .from('pos_reservations')
      .select('id')
      .eq('order_id', orderId)
      .maybeSingle();
    if (lookupError) {
      logger.warn('PAID_ORDER_RESERVATION_SYNC_PENDING');
      return result;
    }
    if (existing) return { ...result, reservationSynced: true };

    const { data: items, error: itemsError } = await client
      .from('order_items')
      .select('quantity, menu_items(name)')
      .eq('order_id', orderId);
    const { data: user, error: userError } = await client
      .from('users')
      .select('name')
      .eq('id', order.user_id)
      .maybeSingle();
    if (itemsError || userError || !items?.length) {
      logger.warn('PAID_ORDER_RESERVATION_SYNC_PENDING');
      return result;
    }
    const summary = items
      .map(
        (item: any) => `${item.menu_items?.name ?? '메뉴'} x${item.quantity}`,
      )
      .join(', ');
    const note = [
      `선결제 방문 요청(#${orderId.slice(0, 6).toUpperCase()})`,
      summary,
      order.customer_note ? `요청사항: ${order.customer_note}` : null,
      '인원은 매장에서 확인 필요 · 좌석 확보를 보장하지 않음',
    ]
      .filter(Boolean)
      .join(' · ');
    const { error: insertError } = await client
      .from('pos_reservations')
      .insert({
        restaurant_id: order.restaurant_id,
        order_id: orderId,
        kind: 'RESERVATION',
        customer_name: `[선결제 요청] ${user?.name?.trim() || '점심싱크 고객'}`,
        // Menu quantities do not identify diners. One requester is the only known
        // attendee; the store confirms the party size before assigning seats.
        party_size: 1,
        scheduled_at: new Date(Date.now() + 15 * 60_000).toISOString(),
        status: 'OPEN',
        note,
      });
    if (!insertError) return { ...result, reservationSynced: true };
    if (insertError.code === '23505') {
      const { data: reconciled, error } = await client
        .from('pos_reservations')
        .select('id')
        .eq('order_id', orderId)
        .maybeSingle();
      if (!error && reconciled) return { ...result, reservationSynced: true };
    }
    logger.warn('PAID_ORDER_RESERVATION_SYNC_PENDING');
  } catch {
    logger.warn('PAID_ORDER_RESERVATION_SYNC_PENDING');
  }
  return result;
}
