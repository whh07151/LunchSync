import { NotificationsService } from '../notifications/notifications.service';
import { PaymentsService } from '../payments/payments.service';
import { SupabaseService } from '../supabase/supabase.service';
import { PosService } from './pos.service';

const ORDER_ID = '22222222-2222-4222-8222-222222222222';

class PosStateDatabase {
  readonly state = {
    id: ORDER_ID,
    user_id: '11111111-1111-4111-8111-111111111111',
    restaurant_id: '33333333-3333-4333-8333-333333333333',
    status: 'PAID',
    updated_at: '2026-08-05T15:00:00+09:00',
    payment_key: 'sim_test_payment',
    payment_method: 'SIMULATE',
  };
  readonly updateFilters: Array<Record<string, unknown>> = [];
  updateCalls = 0;

  constructor(private readonly concurrentStatus?: string) {}

  readonly client = {
    from: (table: string) => {
      if (table !== 'orders') throw new Error(`Unexpected table: ${table}`);
      return {
        select: () => {
          const builder = {
            eq: () => builder,
            single: async () => ({ data: { ...this.state }, error: null }),
            maybeSingle: async () => ({ data: { ...this.state }, error: null }),
          };
          return builder;
        },
        update: (payload: Partial<typeof this.state>) => {
          const filters = new Map<string, unknown>();
          const builder = {
            eq: (column: string, value: unknown) => {
              filters.set(column, value);
              return builder;
            },
            select: () => ({
              maybeSingle: async () => {
                this.updateCalls += 1;
                this.updateFilters.push(Object.fromEntries(filters));
                if (this.concurrentStatus) {
                  this.state.status = this.concurrentStatus;
                  return { data: null, error: null };
                }
                const matches = [...filters].every(
                  ([column, value]) =>
                    this.state[column as keyof typeof this.state] === value,
                );
                if (!matches) return { data: null, error: null };
                Object.assign(this.state, payload);
                return { data: { ...this.state }, error: null };
              },
            }),
          };
          return builder;
        },
      };
    },
  };
}

function createService(database: PosStateDatabase) {
  const notifications = { createNotification: jest.fn() };
  return {
    service: new PosService(
      database as unknown as SupabaseService,
      {} as PaymentsService,
      notifications as unknown as NotificationsService,
    ),
    notifications,
  };
}

describe('POS order status boundary', () => {
  it.each(['PENDING', 'CANCELLED', 'REFUNDED']) (
    'does not advance a %s order into preparation',
    async (sourceStatus) => {
      const database = new PosStateDatabase();
      database.state.status = sourceStatus;

      await expect(
        createService(database).service.updateOrderStatus(
          ORDER_ID,
          'PREPARING',
        ),
      ).rejects.toMatchObject({
        response: expect.objectContaining({
          code: 'INVALID_ORDER_STATUS_TRANSITION',
          retryable: false,
        }),
      });
      expect(database.updateCalls).toBe(0);
      expect(database.state.status).toBe(sourceStatus);
    },
  );

  it('uses the observed paid status as a compare-and-set precondition', async () => {
    const database = new PosStateDatabase();

    await expect(
      createService(database).service.updateOrderStatus(
        ORDER_ID,
        'PREPARING',
      ),
    ).resolves.toMatchObject({ status: 'PREPARING' });
    expect(database.updateFilters).toEqual([
      { id: ORDER_ID, status: 'PAID' },
    ]);
  });

  it('does not resurrect an order cancelled during a status transition', async () => {
    const database = new PosStateDatabase('CANCELLED');

    await expect(
      createService(database).service.updateOrderStatus(
        ORDER_ID,
        'PREPARING',
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: 'ORDER_STATUS_CHANGED',
        retryable: true,
      }),
    });
    expect(database.state.status).toBe('CANCELLED');
  });
});

describe('POS refund simulation boundary', () => {
  const originalNodeEnv = process.env.NODE_ENV;
  const originalRefundSimulation = process.env.ALLOW_REFUND_SIMULATION;

  afterEach(() => {
    if (originalNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = originalNodeEnv;
    if (originalRefundSimulation === undefined)
      delete process.env.ALLOW_REFUND_SIMULATION;
    else process.env.ALLOW_REFUND_SIMULATION = originalRefundSimulation;
  });

  it('is disabled by default before any order lookup', async () => {
    delete process.env.ALLOW_REFUND_SIMULATION;
    const database = new PosStateDatabase();

    await expect(
      createService(database).service.refundSim(ORDER_ID),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: 'REFUND_SIMULATION_DISABLED',
      }),
    });
    expect(database.updateCalls).toBe(0);
  });

  it('never marks a real Toss payment refunded without provider cancellation', async () => {
    process.env.NODE_ENV = 'development';
    process.env.ALLOW_REFUND_SIMULATION = 'true';
    const database = new PosStateDatabase();
    database.state.payment_key = 'real_toss_payment_key';
    database.state.payment_method = 'TOSS';

    await expect(
      createService(database).service.refundSim(ORDER_ID),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: 'REAL_PAYMENT_REQUIRES_PROVIDER_REFUND',
      }),
    });
    expect(database.state.status).toBe('PAID');
  });

  it('updates only the exact simulated payment snapshot', async () => {
    process.env.NODE_ENV = 'development';
    process.env.ALLOW_REFUND_SIMULATION = 'true';
    const database = new PosStateDatabase();

    await expect(
      createService(database).service.refundSim(ORDER_ID),
    ).resolves.toMatchObject({ status: 'REFUNDED' });
    expect(database.updateFilters).toEqual([
      {
        id: ORDER_ID,
        status: 'PAID',
        payment_key: 'sim_test_payment',
      },
    ]);
  });
});
