import { SessionsService } from './sessions.service';
import { SupabaseService } from '../supabase/supabase.service';

function fixture() {
  const writes: {
    table: string;
    action: string;
    payload?: any;
    filters: Record<string, unknown>;
  }[] = [];
  const state = { member: true, failedWrite: false };
  const rows: Record<string, any> = {
    sessions: {
      id: 'session',
      status: 'ORDERED',
      winner_restaurant_id: 'restaurant',
    },
    menu_items: {
      id: 'menu',
      name: 'Server lunch',
      price: 12000,
      restaurant_id: 'restaurant',
      source: 'MANUAL',
      is_available: true,
    },
    users: { name: 'Customer' },
  };
  const db = {
    client: {
      from: (table: string) => {
        let action = 'read';
        let payload: any;
        const filters: Record<string, unknown> = {};
        const finish = () => {
          if (action !== 'read') {
            writes.push({ table, action, payload, filters });
            return {
              data: null,
              error: state.failedWrite ? { message: 'unavailable' } : null,
            };
          }
          return {
            data:
              table === 'session_members'
                ? state.member
                  ? { user_id: 'user' }
                  : null
                : table === 'session_cart_items'
                  ? []
                  : rows[table],
            error: null,
          };
        };
        const query: any = {
          select: () => query,
          eq: (key: string, value: unknown) => {
            filters[key] = value;
            return query;
          },
          gt: () => query,
          order: () => query,
          delete: () => {
            action = 'delete';
            return query;
          },
          upsert: (value: unknown) => {
            action = 'upsert';
            payload = value;
            return query;
          },
          maybeSingle: async () => finish(),
          then: (resolve: any, reject: any) =>
            Promise.resolve(finish()).then(resolve, reject),
        };
        return query;
      },
    },
  } as unknown as SupabaseService;
  return { service: new SessionsService(db), state, rows, writes };
}

describe('Shared cart ownership and validation', () => {
  it('uses authoritative menu price/name and authenticated author', async () => {
    const f = fixture();
    await f.service.upsertSharedCartItem('session', 'user', {
      menuItemId: 'menu',
      quantity: 2,
    });
    expect(f.writes[0].payload).toMatchObject({
      session_id: 'session',
      user_id: 'user',
      menu_name: 'Server lunch',
      price: 12000,
      quantity: 2,
    });
  });
  it.each([-1, 0.5, 100, NaN])(
    'rejects invalid quantity %s before mutation',
    async (quantity) => {
      const f = fixture();
      await expect(
        f.service.upsertSharedCartItem('session', 'user', {
          menuItemId: 'menu',
          quantity,
        }),
      ).rejects.toMatchObject({ status: 400 });
      expect(f.writes).toHaveLength(0);
    },
  );
  it('rejects a nonmember before mutation', async () => {
    const f = fixture();
    f.state.member = false;
    await expect(
      f.service.upsertSharedCartItem('session', 'outsider', {
        menuItemId: 'menu',
        quantity: 1,
      }),
    ).rejects.toMatchObject({ status: 403 });
    expect(f.writes).toHaveLength(0);
  });
  it('rejects a menu from another restaurant', async () => {
    const f = fixture();
    f.rows.menu_items.restaurant_id = 'other';
    await expect(
      f.service.upsertSharedCartItem('session', 'user', {
        menuItemId: 'menu',
        quantity: 1,
      }),
    ).rejects.toMatchObject({ status: 409 });
    expect(f.writes).toHaveLength(0);
  });
  it('scopes deletion to the current author', async () => {
    const f = fixture();
    await f.service.clearMySharedCart('session', 'user');
    expect(f.writes[0]).toMatchObject({
      action: 'delete',
      filters: {
        session_id: 'session',
        user_id: 'user',
      },
    });
  });
  it('does not report failed persistence as an empty successful cart', async () => {
    const f = fixture();
    f.state.failedWrite = true;
    await expect(
      f.service.upsertSharedCartItem('session', 'user', {
        menuItemId: 'menu',
        quantity: 1,
      }),
    ).rejects.toMatchObject({ status: 503 });
  });
});
