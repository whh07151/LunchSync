import { ServiceUnavailableException } from '@nestjs/common';
import { NotificationsService } from '../notifications/notifications.service';
import { PaymentsService } from '../payments/payments.service';
import { SupabaseService } from '../supabase/supabase.service';
import { PosService } from './pos.service';

const ORDER_ID = '22222222-2222-4222-8222-222222222222';
const PAYMENT_KEY = 'test_payment_key_refund';

type UpdateResult = {
  data: { id: string; status: string } | null;
  error: { message: string } | null;
};

function createOrderQuery(overrides: Record<string, unknown> = {}) {
  const builder = {
    select: jest.fn(),
    eq: jest.fn(),
    single: jest.fn(),
  };
  builder.select.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.single.mockResolvedValue({
    data: {
      id: ORDER_ID,
      status: 'PAID',
      total_price: 12_000,
      payment_key: PAYMENT_KEY,
      ...overrides,
    },
    error: null,
  });
  return builder;
}

function createReconciliationQuery(
  result: UpdateResult = {
    data: { id: ORDER_ID, status: 'PAID' },
    error: null,
  },
) {
  const builder = {
    select: jest.fn(),
    eq: jest.fn(),
    maybeSingle: jest.fn(),
  };
  builder.select.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.maybeSingle.mockResolvedValue(result);
  return builder;
}

function createCancelUpdateQuery(result: UpdateResult) {
  const builder = {
    update: jest.fn(),
    eq: jest.fn(),
    is: jest.fn(),
    select: jest.fn(),
    maybeSingle: jest.fn(),
  };
  builder.update.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.is.mockReturnValue(builder);
  builder.select.mockReturnValue(builder);
  builder.maybeSingle.mockResolvedValue(result);
  return builder;
}

function createService(
  updateResult: UpdateResult,
  reconciliationResult?: UpdateResult,
  orderOverrides: Record<string, unknown> = {},
) {
  const orderQuery = createOrderQuery(orderOverrides);
  const updateQuery = createCancelUpdateQuery(updateResult);
  const reconciliationQuery = createReconciliationQuery(reconciliationResult);
  const from = jest
    .fn()
    .mockReturnValueOnce(orderQuery)
    .mockReturnValueOnce(updateQuery)
    .mockReturnValueOnce(reconciliationQuery)
    // External-refund failures perform a bounded follow-up reconciliation.
    // Reuse the latest-order query so the test reaches the intended 503 path
    // instead of failing because the Supabase test double ran out of builders.
    .mockReturnValue(reconciliationQuery);
  const payments = {
    cancelPayment: jest.fn().mockResolvedValue({
      paymentKey: PAYMENT_KEY,
      status: 'CANCELED',
      canceledAt: '2026-08-05T16:00:00+09:00',
      cancelAmount: 12_000,
    }),
  };

  const service = new PosService(
    { client: { from } } as unknown as SupabaseService,
    payments as unknown as PaymentsService,
    {} as NotificationsService,
  );

  return { service, payments, updateQuery, reconciliationQuery };
}

describe('POS refund consistency', () => {
  it('reports reconciliation pending when Toss refunded but the DB update failed', async () => {
    const { service, payments, updateQuery } = createService({
      data: null,
      error: { message: 'database write unavailable' },
    });

    let thrown: unknown;
    try {
      await service.cancelOrder(ORDER_ID, '점주 취소');
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeInstanceOf(ServiceUnavailableException);
    expect((thrown as ServiceUnavailableException).getResponse()).toMatchObject(
      {
        code: 'REFUND_COMPLETED_DB_SYNC_PENDING',
        retryable: true,
        orderId: ORDER_ID,
      },
    );
    expect(payments.cancelPayment).toHaveBeenCalledWith(
      PAYMENT_KEY,
      '점주 취소',
      ORDER_ID,
    );
    expect(updateQuery.eq).toHaveBeenCalledWith('id', ORDER_ID);
    expect(updateQuery.eq).toHaveBeenCalledWith('status', 'PAID');
    expect(updateQuery.eq).toHaveBeenCalledWith('payment_key', PAYMENT_KEY);
  });

  it('does not report success when the update missed and the order is still paid', async () => {
    const { service } = createService(
      { data: null, error: null },
      { data: { id: ORDER_ID, status: 'PAID' }, error: null },
    );

    await expect(service.cancelOrder(ORDER_ID)).rejects.toMatchObject({
      response: expect.objectContaining({
        code: 'REFUND_COMPLETED_DB_SYNC_PENDING',
        retryable: true,
        orderId: ORDER_ID,
      }),
    });
  });

  it('treats a concurrent cancellation as idempotent after DB reconciliation', async () => {
    const { service, reconciliationQuery } = createService(
      { data: null, error: null },
      { data: { id: ORDER_ID, status: 'CANCELLED' }, error: null },
    );

    await expect(service.cancelOrder(ORDER_ID)).resolves.toMatchObject({
      id: ORDER_ID,
      status: 'CANCELLED',
      refundMethod: 'TOSS_CANCEL',
      reconciled: true,
    });
    expect(reconciliationQuery.eq).toHaveBeenCalledWith('id', ORDER_ID);
  });

  it('returns CANCELLED only after exactly one eligible order was updated', async () => {
    const { service } = createService({
      data: { id: ORDER_ID, status: 'CANCELLED' },
      error: null,
    });

    await expect(service.cancelOrder(ORDER_ID)).resolves.toMatchObject({
      id: ORDER_ID,
      status: 'CANCELLED',
      refundMethod: 'TOSS_CANCEL',
    });
  });

  it('treats a sequential retry of an already cancelled order as idempotent', async () => {
    const { service, payments } = createService(
      { data: null, error: null },
      undefined,
      { status: 'CANCELLED' },
    );

    await expect(service.cancelOrder(ORDER_ID)).resolves.toMatchObject({
      id: ORDER_ID,
      status: 'CANCELLED',
      alreadyCancelled: true,
      reconciled: true,
    });
    expect(payments.cancelPayment).not.toHaveBeenCalled();
  });
});

describe('POS cancel versus payment confirmation race', () => {
  it('does not overwrite a newly paid order with a stale no-key cancellation', async () => {
    const state = {
      id: ORDER_ID,
      status: 'PENDING',
      total_price: 12_000,
      payment_key: null as string | null,
    };
    const updateSnapshots: Array<{
      status: unknown;
      paymentKey: unknown;
      usedIsNull: boolean;
    }> = [];
    let updateCount = 0;

    const client = {
      from: jest.fn(() => ({
        select: jest.fn(() => {
          const selectBuilder = {
            eq: jest.fn(() => selectBuilder),
            single: jest.fn(async () => ({ data: { ...state }, error: null })),
            maybeSingle: jest.fn(async () => ({
              data: { ...state },
              error: null,
            })),
          };
          return selectBuilder;
        }),
        update: jest.fn((payload: { status: string }) => {
          const filters = new Map<string, unknown>();
          let usedIsNull = false;
          const updateBuilder = {
            eq: jest.fn((column: string, value: unknown) => {
              filters.set(column, value);
              return updateBuilder;
            }),
            is: jest.fn((column: string, value: unknown) => {
              filters.set(column, value);
              usedIsNull = column === 'payment_key' && value === null;
              return updateBuilder;
            }),
            select: jest.fn(() => ({
              maybeSingle: jest.fn(async () => {
                updateCount += 1;
                updateSnapshots.push({
                  status: filters.get('status'),
                  paymentKey: filters.get('payment_key'),
                  usedIsNull,
                });

                if (updateCount === 1) {
                  state.status = 'PAID';
                  state.payment_key = PAYMENT_KEY;
                  return { data: null, error: null };
                }

                const matches =
                  filters.get('status') === state.status &&
                  filters.get('payment_key') === state.payment_key;
                if (!matches) return { data: null, error: null };
                state.status = payload.status;
                return {
                  data: { id: ORDER_ID, status: state.status },
                  error: null,
                };
              }),
            })),
          };
          return updateBuilder;
        }),
      })),
    };
    const payments = {
      cancelPayment: jest.fn().mockResolvedValue({
        paymentKey: PAYMENT_KEY,
        status: 'CANCELED',
        cancelAmount: 12_000,
      }),
    };
    const service = new PosService(
      { client } as unknown as SupabaseService,
      payments as unknown as PaymentsService,
      {} as NotificationsService,
    );

    await expect(service.cancelOrder(ORDER_ID)).resolves.toMatchObject({
      status: 'CANCELLED',
      refundMethod: 'TOSS_CANCEL',
    });
    expect(updateSnapshots).toEqual([
      { status: 'PENDING', paymentKey: null, usedIsNull: true },
      { status: 'PAID', paymentKey: PAYMENT_KEY, usedIsNull: false },
    ]);
    expect(payments.cancelPayment).toHaveBeenCalledTimes(1);
    expect(payments.cancelPayment).toHaveBeenCalledWith(
      PAYMENT_KEY,
      '점주 취소',
      ORDER_ID,
    );
    expect(state.status).toBe('CANCELLED');
  });

  it('reconciles a fulfillment transition that wins after the provider refund', async () => {
    const state = {
      id: ORDER_ID,
      status: 'PAID',
      total_price: 12_000,
      payment_key: PAYMENT_KEY,
    };
    let updateCount = 0;

    const client = {
      from: jest.fn(() => ({
        select: jest.fn(() => {
          const selectBuilder = {
            eq: jest.fn(() => selectBuilder),
            single: jest.fn(async () => ({ data: { ...state }, error: null })),
            maybeSingle: jest.fn(async () => ({
              data: { ...state },
              error: null,
            })),
          };
          return selectBuilder;
        }),
        update: jest.fn((payload: { status: string }) => {
          const filters = new Map<string, unknown>();
          const updateBuilder = {
            eq: jest.fn((column: string, value: unknown) => {
              filters.set(column, value);
              return updateBuilder;
            }),
            is: jest.fn((column: string, value: unknown) => {
              filters.set(column, value);
              return updateBuilder;
            }),
            select: jest.fn(() => ({
              maybeSingle: jest.fn(async () => {
                updateCount += 1;
                if (updateCount === 1) {
                  state.status = 'PREPARING';
                  return { data: null, error: null };
                }

                const matches =
                  filters.get('status') === state.status &&
                  filters.get('payment_key') === state.payment_key;
                if (!matches) return { data: null, error: null };
                state.status = payload.status;
                return {
                  data: { id: ORDER_ID, status: state.status },
                  error: null,
                };
              }),
            })),
          };
          return updateBuilder;
        }),
      })),
    };
    const payments = {
      cancelPayment: jest.fn().mockResolvedValue({
        paymentKey: PAYMENT_KEY,
        status: 'CANCELED',
        cancelAmount: 12_000,
      }),
    };
    const service = new PosService(
      { client } as unknown as SupabaseService,
      payments as unknown as PaymentsService,
      {} as NotificationsService,
    );

    await expect(service.cancelOrder(ORDER_ID)).resolves.toMatchObject({
      status: 'CANCELLED',
      refundMethod: 'TOSS_CANCEL',
      reconciled: true,
      fulfillmentRaceReconciled: true,
    });
    expect(updateCount).toBe(2);
    expect(state.status).toBe('CANCELLED');
  });
});
