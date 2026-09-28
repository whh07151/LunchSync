import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SupabaseService } from '../supabase/supabase.service';
import { PaymentsController } from './payments.controller';
import { PaymentsService } from './payments.service';

const USER_ID = '11111111-1111-4111-8111-111111111111';
const ORDER_ID = '22222222-2222-4222-8222-222222222222';
const PAYMENT_KEY = 'test_payment_key_approved';
const OTHER_PAYMENT_KEY = 'test_payment_key_competing';
const AMOUNT = 12_000;

type StoredPaymentOrder = {
  id: string;
  status: string;
  total_price: number;
  session_id: string;
  user_id: string;
  payment_key: string | null;
  payment_method: string;
};

class PaymentTestDatabase {
  readonly order: StoredPaymentOrder = {
    id: ORDER_ID,
    status: 'PENDING',
    total_price: AMOUNT,
    session_id: '33333333-3333-4333-8333-333333333333',
    user_id: USER_ID,
    payment_key: null,
    payment_method: 'TOSS',
  };

  constructor(
    private updateFailuresRemaining = 1,
    private readonly updateShouldMiss = false,
    private readonly concurrentPaymentOnMiss = false,
    private readonly updateReturnsMismatchedRow = false,
    private readonly concurrentCancellationOnMiss = false,
  ) {}

  readonly client = {
    from: (table: string) => {
      if (table !== 'orders') {
        throw new Error(`Unexpected table: ${table}`);
      }

      return {
        select: () => ({
          eq: () => ({
            single: async () => ({
              data: { ...this.order },
              error: null,
            }),
          }),
        }),
        update: (payload: Partial<StoredPaymentOrder>) => {
          const filters = new Map<string, unknown>();
          let result:
            | Promise<{
                data: StoredPaymentOrder | null;
                error: { message: string } | null;
              }>
            | undefined;

          const applyUpdate = async () => {
            if (result) return result;

            result = Promise.resolve().then(() => {
              const matches =
                filters.get('id') === this.order.id &&
                (filters.get('status') === undefined ||
                  filters.get('status') === this.order.status);

              if (this.updateShouldMiss || !matches) {
                if (this.concurrentPaymentOnMiss) {
                  this.order.status = 'PAID';
                  this.order.payment_key = PAYMENT_KEY;
                }
                if (this.concurrentCancellationOnMiss) {
                  this.order.status = 'CANCELLED';
                  this.order.payment_key = null;
                }
                return { data: null, error: null };
              }

              if (this.updateFailuresRemaining > 0) {
                this.updateFailuresRemaining -= 1;
                return {
                  data: null,
                  error: { message: 'database write unavailable' },
                };
              }

              if (this.updateReturnsMismatchedRow) {
                return {
                  data: {
                    ...this.order,
                    status: 'PAID',
                    payment_key: OTHER_PAYMENT_KEY,
                  },
                  error: null,
                };
              }

              Object.assign(this.order, payload);
              return { data: { ...this.order }, error: null };
            });
            return result;
          };

          const builder = {
            eq: (column: string, value: unknown) => {
              filters.set(column, value);
              return builder;
            },
            select: () => ({
              maybeSingle: applyUpdate,
            }),
            then: (
              onFulfilled: (
                value: Awaited<ReturnType<typeof applyUpdate>>,
              ) => unknown,
              onRejected?: (reason: unknown) => unknown,
            ) => applyUpdate().then(onFulfilled, onRejected),
          };

          return builder;
        },
      };
    },
  };
}

async function createTestApplication(
  database: PaymentTestDatabase,
  tossTimeoutMs?: number,
): Promise<INestApplication> {
  const moduleRef = await Test.createTestingModule({
    controllers: [PaymentsController],
    providers: [
      PaymentsService,
      { provide: SupabaseService, useValue: database },
      {
        provide: ConfigService,
        useValue: {
          getOrThrow: () => 'toss-test-key-placeholder',
          get: (key: string) =>
            key === 'TOSS_API_BASE_URL'
              ? 'https://toss.test'
              : key === 'TOSS_API_TIMEOUT_MS' && tossTimeoutMs !== undefined
                ? String(tossTimeoutMs)
                : undefined,
        },
      },
    ],
  })
    .overrideGuard(JwtAuthGuard)
    .useValue({
      canActivate: (context: {
        switchToHttp(): { getRequest(): { user?: { userId: string } } };
      }) => {
        context.switchToHttp().getRequest().user = { userId: USER_ID };
        return true;
      },
    })
    .compile();

  const app = moduleRef.createNestApplication();
  app.setGlobalPrefix('api');
  await app.init();
  return app;
}

describe('Payment confirmation consistency (HTTP acceptance)', () => {
  let app: INestApplication;
  let database: PaymentTestDatabase;
  let originalFetch: typeof fetch;

  beforeEach(async () => {
    originalFetch = global.fetch;
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        paymentKey: PAYMENT_KEY,
        orderId: ORDER_ID,
        status: 'DONE',
        totalAmount: AMOUNT,
        method: '카드',
        approvedAt: '2026-07-29T13:30:00+09:00',
      }),
    }) as unknown as typeof fetch;

    database = new PaymentTestDatabase();
    app = await createTestApplication(database);
  });

  afterEach(async () => {
    global.fetch = originalFetch;
    await app.close();
  });

  it('reports a retryable reconciliation outcome when Toss approved but the DB update failed', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({
        paymentKey: PAYMENT_KEY,
        orderId: ORDER_ID,
        amount: AMOUNT,
      });

    expect({
      httpStatus: response.status,
      code: response.body.code,
      retryable: response.body.retryable,
      orderId: response.body.orderId,
      paymentKey: response.body.paymentKey,
      storedStatus: database.order.status,
    }).toEqual({
      httpStatus: 503,
      code: 'PAYMENT_APPROVED_DB_SYNC_PENDING',
      retryable: true,
      orderId: ORDER_ID,
      paymentKey: PAYMENT_KEY,
      storedStatus: 'PENDING',
    });
  });

  it('reuses one Toss idempotency key and completes reconciliation on retry', async () => {
    const firstResponse = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({
        paymentKey: PAYMENT_KEY,
        orderId: ORDER_ID,
        amount: AMOUNT,
      });

    const retryResponse = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({
        paymentKey: PAYMENT_KEY,
        orderId: ORDER_ID,
        amount: AMOUNT,
      });

    const fetchMock = global.fetch as jest.MockedFunction<typeof fetch>;
    const idempotencyKeys = fetchMock.mock.calls.map(([, init]) => {
      const headers = init?.headers as Record<string, string>;
      return headers['Idempotency-Key'];
    });

    expect({
      firstStatus: firstResponse.status,
      retryStatus: retryResponse.status,
      retryPaymentStatus: retryResponse.body.data?.status,
      storedStatus: database.order.status,
      idempotencyKeys,
    }).toEqual({
      firstStatus: 503,
      retryStatus: 201,
      retryPaymentStatus: 'PAID',
      storedStatus: 'PAID',
      idempotencyKeys: [
        `lunchsync-confirm:${ORDER_ID}`,
        `lunchsync-confirm:${ORDER_ID}`,
      ],
    });
  });

  it('uses one order-scoped Toss idempotency key for competing payment keys', async () => {
    const firstResponse = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({
        paymentKey: PAYMENT_KEY,
        orderId: ORDER_ID,
        amount: AMOUNT,
      });

    const competingResponse = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({
        paymentKey: OTHER_PAYMENT_KEY,
        orderId: ORDER_ID,
        amount: AMOUNT,
      });

    const fetchMock = global.fetch as jest.MockedFunction<typeof fetch>;
    const idempotencyKeys = fetchMock.mock.calls.map(([, init]) => {
      const headers = init?.headers as Record<string, string>;
      return headers['Idempotency-Key'];
    });

    expect({
      firstStatus: firstResponse.status,
      competingStatus: competingResponse.status,
      competingCode: competingResponse.body.code,
      storedStatus: database.order.status,
      idempotencyKeys,
    }).toEqual({
      firstStatus: 503,
      competingStatus: 502,
      competingCode: 'TOSS_PAYMENT_MISMATCH',
      storedStatus: 'PENDING',
      idempotencyKeys: [
        `lunchsync-confirm:${ORDER_ID}`,
        `lunchsync-confirm:${ORDER_ID}`,
      ],
    });
  });

  it('does not report paid when a conditional DB update matches no pending order', async () => {
    await app.close();
    database = new PaymentTestDatabase(0, true);
    app = await createTestApplication(database);

    const response = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({
        paymentKey: PAYMENT_KEY,
        orderId: ORDER_ID,
        amount: AMOUNT,
      });

    expect({
      httpStatus: response.status,
      code: response.body.code,
      retryable: response.body.retryable,
      storedStatus: database.order.status,
    }).toEqual({
      httpStatus: 503,
      code: 'PAYMENT_APPROVED_DB_SYNC_PENDING',
      retryable: true,
      storedStatus: 'PENDING',
    });
  });

  it('recognizes a concurrent successful reconciliation instead of reporting it pending', async () => {
    await app.close();
    database = new PaymentTestDatabase(0, true, true);
    app = await createTestApplication(database);

    const response = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({
        paymentKey: PAYMENT_KEY,
        orderId: ORDER_ID,
        amount: AMOUNT,
      });

    expect({
      httpStatus: response.status,
      alreadyPaid: response.body.data?.alreadyPaid,
      reconciled: response.body.data?.reconciled,
      status: response.body.data?.status,
      paymentKey: response.body.data?.paymentKey,
      storedStatus: database.order.status,
    }).toEqual({
      httpStatus: 201,
      alreadyPaid: true,
      reconciled: true,
      status: 'PAID',
      paymentKey: PAYMENT_KEY,
      storedStatus: 'PAID',
    });
  });

  it('immediately refunds when cancellation wins after Toss approval', async () => {
    await app.close();
    database = new PaymentTestDatabase(0, true, false, false, true);
    app = await createTestApplication(database);

    global.fetch = jest
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          paymentKey: PAYMENT_KEY,
          orderId: ORDER_ID,
          status: 'DONE',
          totalAmount: AMOUNT,
          method: '카드',
          approvedAt: '2026-08-05T16:00:00+09:00',
        }),
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          paymentKey: PAYMENT_KEY,
          orderId: ORDER_ID,
          status: 'CANCELED',
          cancels: [
            {
              cancelStatus: 'DONE',
              cancelAmount: AMOUNT,
              canceledAt: '2026-08-05T16:00:01+09:00',
            },
          ],
        }),
      }) as unknown as typeof fetch;

    const response = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({ paymentKey: PAYMENT_KEY, orderId: ORDER_ID, amount: AMOUNT });

    const fetchMock = global.fetch as jest.MockedFunction<typeof fetch>;
    const [, cancelInit] = fetchMock.mock.calls[1];
    expect({
      httpStatus: response.status,
      code: response.body.code,
      compensated: response.body.compensated,
      retryable: response.body.retryable,
      storedStatus: database.order.status,
      tossCalls: fetchMock.mock.calls.length,
      cancelIdempotencyKey: (
        cancelInit?.headers as Record<string, string>
      )['Idempotency-Key'],
    }).toEqual({
      httpStatus: 409,
      code: 'PAYMENT_APPROVED_AFTER_CANCELLATION_REFUNDED',
      compensated: true,
      retryable: false,
      storedStatus: 'CANCELLED',
      tossCalls: 2,
      cancelIdempotencyKey: `lunchsync-cancel:${ORDER_ID}`,
    });
  });

  it('reports reconciliation required when the race compensation cannot be confirmed', async () => {
    await app.close();
    database = new PaymentTestDatabase(0, true, false, false, true);
    app = await createTestApplication(database);

    global.fetch = jest
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          paymentKey: PAYMENT_KEY,
          orderId: ORDER_ID,
          status: 'DONE',
          totalAmount: AMOUNT,
        }),
      })
      .mockRejectedValueOnce(
        new Error('refund provider connection reset'),
      ) as unknown as typeof fetch;

    const response = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({ paymentKey: PAYMENT_KEY, orderId: ORDER_ID, amount: AMOUNT });

    expect(response.status).toBe(503);
    expect(response.body).toMatchObject({
      code: 'PAYMENT_APPROVED_CANCEL_RECONCILIATION_REQUIRED',
      retryable: true,
      reconciliationRequired: true,
      orderId: ORDER_ID,
    });
  });

  it('does not trust an updated row whose stored values do not match the payment', async () => {
    await app.close();
    database = new PaymentTestDatabase(0, false, false, true);
    app = await createTestApplication(database);

    const response = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({
        paymentKey: PAYMENT_KEY,
        orderId: ORDER_ID,
        amount: AMOUNT,
      });

    expect({
      httpStatus: response.status,
      code: response.body.code,
      retryable: response.body.retryable,
      storedStatus: database.order.status,
      storedPaymentKey: database.order.payment_key,
    }).toEqual({
      httpStatus: 503,
      code: 'PAYMENT_APPROVED_DB_SYNC_PENDING',
      retryable: true,
      storedStatus: 'PENDING',
      storedPaymentKey: null,
    });
  });

  it('rejects a different payment key for an order that is already paid', async () => {
    database.order.status = 'PAID';
    database.order.payment_key = 'test_payment_key_already_stored';

    const response = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({
        paymentKey: PAYMENT_KEY,
        orderId: ORDER_ID,
        amount: AMOUNT,
      });

    expect({
      httpStatus: response.status,
      code: response.body.code,
      retryable: response.body.retryable,
      orderId: response.body.orderId,
      tossCalls: (global.fetch as jest.MockedFunction<typeof fetch>).mock.calls
        .length,
    }).toEqual({
      httpStatus: 409,
      code: 'PAYMENT_KEY_MISMATCH',
      retryable: false,
      orderId: ORDER_ID,
      tossCalls: 0,
    });
  });

  it('does not approve an order that is no longer pending', async () => {
    database.order.status = 'CANCELLED';

    const response = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({
        paymentKey: PAYMENT_KEY,
        orderId: ORDER_ID,
        amount: AMOUNT,
      });

    expect({
      httpStatus: response.status,
      code: response.body.code,
      retryable: response.body.retryable,
      orderId: response.body.orderId,
      tossCalls: (global.fetch as jest.MockedFunction<typeof fetch>).mock.calls
        .length,
    }).toEqual({
      httpStatus: 409,
      code: 'ORDER_NOT_PAYABLE',
      retryable: false,
      orderId: ORDER_ID,
      tossCalls: 0,
    });
  });

  it('does not approve a cash order through the Toss confirmation route', async () => {
    database.order.payment_method = 'CASH';

    const response = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({ paymentKey: PAYMENT_KEY, orderId: ORDER_ID, amount: AMOUNT });

    expect(response.status).toBe(409);
    expect(response.body).toMatchObject({
      code: 'PAYMENT_METHOD_NOT_TOSS',
      retryable: false,
      orderId: ORDER_ID,
    });
    expect(global.fetch).not.toHaveBeenCalled();
    expect(database.order.status).toBe('PENDING');
  });

  it.each([
    ['paymentKey', { paymentKey: 'test_payment_key_for_another_payment' }],
    ['orderId', { orderId: '99999999-9999-4999-8999-999999999999' }],
    ['totalAmount', { totalAmount: AMOUNT + 1 }],
    ['status', { status: 'CANCELED' }],
  ])(
    'does not persist a successful Toss response with mismatched %s',
    async (_field, overrides) => {
      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          paymentKey: PAYMENT_KEY,
          orderId: ORDER_ID,
          status: 'DONE',
          totalAmount: AMOUNT,
          method: '카드',
          approvedAt: '2026-07-29T13:30:00+09:00',
          ...overrides,
        }),
      }) as unknown as typeof fetch;

      const response = await request(app.getHttpServer())
        .post('/api/payments/confirm')
        .send({
          paymentKey: PAYMENT_KEY,
          orderId: ORDER_ID,
          amount: AMOUNT,
        });

      expect({
        httpStatus: response.status,
        code: response.body.code,
        retryable: response.body.retryable,
        orderId: response.body.orderId,
        storedStatus: database.order.status,
        storedPaymentKey: database.order.payment_key,
      }).toEqual({
        httpStatus: 502,
        code: 'TOSS_PAYMENT_MISMATCH',
        retryable: false,
        orderId: ORDER_ID,
        storedStatus: 'PENDING',
        storedPaymentKey: null,
      });
    },
  );

  it('preserves the retryable Toss idempotency-in-progress outcome', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 409,
      json: async () => ({
        code: 'IDEMPOTENT_REQUEST_PROCESSING',
        message: 'Previous idempotent request is still processing.',
      }),
    }) as unknown as typeof fetch;

    const response = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({
        paymentKey: PAYMENT_KEY,
        orderId: ORDER_ID,
        amount: AMOUNT,
      });

    expect({
      httpStatus: response.status,
      code: response.body.code,
      retryable: response.body.retryable,
      orderId: response.body.orderId,
      storedStatus: database.order.status,
    }).toEqual({
      httpStatus: 409,
      code: 'IDEMPOTENT_REQUEST_PROCESSING',
      retryable: true,
      orderId: ORDER_ID,
      storedStatus: 'PENDING',
    });
  });

  it('preserves a retryable outcome for a Toss server failure', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 503,
      json: async () => ({
        code: 'PROVIDER_UNAVAILABLE',
        message: 'Temporary provider failure.',
      }),
    }) as unknown as typeof fetch;

    const response = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({
        paymentKey: PAYMENT_KEY,
        orderId: ORDER_ID,
        amount: AMOUNT,
      });

    expect({
      httpStatus: response.status,
      code: response.body.code,
      retryable: response.body.retryable,
      storedStatus: database.order.status,
    }).toEqual({
      httpStatus: 503,
      code: 'TOSS_SERVICE_UNAVAILABLE',
      retryable: true,
      storedStatus: 'PENDING',
    });
  });

  it('classifies a Toss server failure with a non-JSON body as unavailable', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 502,
      json: async () => {
        throw new SyntaxError('Unexpected token');
      },
    }) as unknown as typeof fetch;

    const response = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({
        paymentKey: PAYMENT_KEY,
        orderId: ORDER_ID,
        amount: AMOUNT,
      });

    expect({
      httpStatus: response.status,
      code: response.body.code,
      retryable: response.body.retryable,
      storedStatus: database.order.status,
    }).toEqual({
      httpStatus: 503,
      code: 'TOSS_SERVICE_UNAVAILABLE',
      retryable: true,
      storedStatus: 'PENDING',
    });
  });

  it('preserves a retryable outcome when the Toss response is not received', async () => {
    global.fetch = jest
      .fn()
      .mockRejectedValue(new Error('connection reset')) as unknown as typeof fetch;

    const response = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({
        paymentKey: PAYMENT_KEY,
        orderId: ORDER_ID,
        amount: AMOUNT,
      });

    expect({
      httpStatus: response.status,
      code: response.body.code,
      retryable: response.body.retryable,
      storedStatus: database.order.status,
    }).toEqual({
      httpStatus: 503,
      code: 'TOSS_COMMUNICATION_FAILED',
      retryable: true,
      storedStatus: 'PENDING',
    });
  });

  it('stops waiting for a stalled Toss response at the configured timeout', async () => {
    await app.close();
    database = new PaymentTestDatabase(0);
    app = await createTestApplication(database, 100);

    global.fetch = jest.fn((_input, init) => {
      return new Promise((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => {
          reject(init.signal?.reason);
        });
      });
    }) as unknown as typeof fetch;

    const response = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send({
        paymentKey: PAYMENT_KEY,
        orderId: ORDER_ID,
        amount: AMOUNT,
      });

    expect({
      httpStatus: response.status,
      code: response.body.code,
      retryable: response.body.retryable,
      storedStatus: database.order.status,
    }).toEqual({
      httpStatus: 503,
      code: 'TOSS_COMMUNICATION_FAILED',
      retryable: true,
      storedStatus: 'PENDING',
    });
  });
});
