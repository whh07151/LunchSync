import { NotificationsService } from '../notifications/notifications.service';
import { PaymentsService } from '../payments/payments.service';
import { SupabaseService } from '../supabase/supabase.service';
import { PosService } from './pos.service';

const ORDER_ID = '22222222-2222-4222-8222-222222222222';

class PosChargeDatabase {
  readonly state = {
    id: ORDER_ID,
    status: 'PENDING',
    payment_method: 'CASH',
    updated_at: '2026-08-05T15:00:00+09:00',
  };
  readonly filters = new Map<string, unknown>();

  constructor(
    private readonly concurrentResult?: {
      status: string;
      paymentMethod: string;
    },
  ) {}

  readonly client = {
    from: (table: string) => {
      if (table !== 'orders') throw new Error(`Unexpected table: ${table}`);

      return {
        select: () => {
          const builder = {
            eq: () => builder,
            single: async () => ({ data: { ...this.state }, error: null }),
            maybeSingle: async () => ({
              data: { ...this.state },
              error: null,
            }),
          };
          return builder;
        },
        update: (payload: Partial<typeof this.state>) => {
          const builder = {
            eq: (column: string, value: unknown) => {
              this.filters.set(column, value);
              return builder;
            },
            select: () => ({
              maybeSingle: async () => {
                if (this.concurrentResult) {
                  this.state.status = this.concurrentResult.status;
                  this.state.payment_method =
                    this.concurrentResult.paymentMethod;
                  return { data: null, error: null };
                }

                const matches =
                  this.filters.get('id') === this.state.id &&
                  this.filters.get('status') === this.state.status;
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

function createService(database: PosChargeDatabase) {
  return new PosService(
    database as unknown as SupabaseService,
    {} as PaymentsService,
    {} as NotificationsService,
  );
}

describe('POS payment state consistency', () => {
  const originalNodeEnv = process.env.NODE_ENV;
  const originalCardSimulation = process.env.ALLOW_POS_CARD_SIMULATION;

  afterEach(() => {
    if (originalNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = originalNodeEnv;
    if (originalCardSimulation === undefined)
      delete process.env.ALLOW_POS_CARD_SIMULATION;
    else process.env.ALLOW_POS_CARD_SIMULATION = originalCardSimulation;
  });

  it('changes only the pending snapshot to paid', async () => {
    const database = new PosChargeDatabase();

    await expect(
      createService(database).chargeViaPosToss(ORDER_ID, 'CASH', 12_000),
    ).resolves.toMatchObject({
      orderId: ORDER_ID,
      status: 'PAID',
      paymentMethod: 'POS_CASH',
    });
    expect(Object.fromEntries(database.filters)).toEqual({
      id: ORDER_ID,
      status: 'PENDING',
    });
  });

  it('does not revive an order cancelled while POS payment is being recorded', async () => {
    const database = new PosChargeDatabase({
      status: 'CANCELLED',
      paymentMethod: 'CASH',
    });

    await expect(
      createService(database).chargeViaPosToss(ORDER_ID, 'CASH', 12_000),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: 'POS_PAYMENT_STATE_CHANGED',
        retryable: false,
        orderId: ORDER_ID,
      }),
    });
    expect(database.state.status).toBe('CANCELLED');
  });

  it('reconciles a concurrent identical POS payment without a second update', async () => {
    const database = new PosChargeDatabase({
      status: 'PAID',
      paymentMethod: 'POS_CASH',
    });

    await expect(
      createService(database).chargeViaPosToss(ORDER_ID, 'CASH', 12_000),
    ).resolves.toMatchObject({
      orderId: ORDER_ID,
      status: 'PAID',
      paymentMethod: 'POS_CASH',
    });
  });

  it('rejects card simulation by default before reading or changing an order', async () => {
    delete process.env.ALLOW_POS_CARD_SIMULATION;
    process.env.NODE_ENV = 'development';
    const database = new PosChargeDatabase();

    await expect(
      createService(database).chargeViaPosToss(ORDER_ID, 'CARD'),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: 'POS_CARD_SIMULATION_DISABLED',
        retryable: false,
      }),
    });
    expect(database.state.status).toBe('PENDING');
  });
});
