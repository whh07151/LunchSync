import { Logger } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { syncPaidOrderPostActions } from './paid-order-post-actions';

const ORDER = '11111111-1111-4111-8111-111111111111';

function fixture(
  options: {
    cartError?: boolean;
    takeout?: boolean;
    insertError?: boolean;
  } = {},
) {
  let reservation: { id: string } | null = null;
  let inserts = 0;
  const rpcCalls: unknown[] = [];
  const client = {
    rpc: async (name: string, args: unknown) => {
      rpcCalls.push({ name, args });
      return {
        data: {},
        error: options.cartError ? { message: 'DB unavailable' } : null,
      };
    },
    from: (table: string) => {
      const response = () => ({
        error: null,
        data:
          table === 'orders'
            ? {
                id: ORDER,
                status: 'PAID',
                user_id: 'user',
                restaurant_id: 'restaurant',
                dining_type: options.takeout ? 'TAKEOUT' : 'DINE_IN',
              }
            : table === 'pos_reservations'
              ? reservation
              : table === 'users'
                ? { name: 'Customer' }
                : [{ quantity: 2, menu_items: { name: 'Lunch' } }],
      });
      const query: any = {
        select: () => query,
        eq: () => query,
        single: async () => response(),
        maybeSingle: async () => response(),
        then: (resolve: (value: unknown) => unknown) =>
          Promise.resolve(response()).then(resolve),
        insert: async (payload: any) => {
          inserts++;
          expect(payload.order_id).toBe(ORDER);
          expect(payload.party_size).toBe(1);
          if (options.insertError) return { error: { code: 'XX000' } };
          reservation = { id: 'reservation' };
          return { error: null };
        },
      };
      return query;
    },
  } as unknown as SupabaseService['client'];
  return { client, rpcCalls, insertCount: () => inserts };
}

describe('Paid order local post actions', () => {
  const logger = { warn: jest.fn() } as unknown as Logger;

  it('retries by immutable order ID and reuses the existing reservation', async () => {
    const db = fixture();
    expect(await syncPaidOrderPostActions(db.client, logger, ORDER)).toEqual({
      cartSynced: true,
      reservationSynced: true,
    });
    expect(await syncPaidOrderPostActions(db.client, logger, ORDER)).toEqual({
      cartSynced: true,
      reservationSynced: true,
    });
    expect(db.rpcCalls).toEqual(
      Array(2).fill({
        name: 'consume_ordered_session_cart_items',
        args: { p_order_id: ORDER },
      }),
    );
    expect(db.insertCount()).toBe(1);
  });

  it('reports a resolved Supabase cart error without undoing paid status', async () => {
    const db = fixture({ cartError: true });
    expect(await syncPaidOrderPostActions(db.client, logger, ORDER)).toEqual({
      cartSynced: false,
      reservationSynced: true,
    });
  });

  it('does not create a visit reservation for takeout', async () => {
    const db = fixture({ takeout: true });
    expect(await syncPaidOrderPostActions(db.client, logger, ORDER)).toEqual({
      cartSynced: true,
      reservationSynced: false,
    });
    expect(db.insertCount()).toBe(0);
  });

  it('reports reservation persistence failure as pending local work', async () => {
    const db = fixture({ insertError: true });
    expect(await syncPaidOrderPostActions(db.client, logger, ORDER)).toEqual({
      cartSynced: true,
      reservationSynced: false,
    });
  });
});
