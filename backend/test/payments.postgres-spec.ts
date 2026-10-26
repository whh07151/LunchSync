import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Test } from '@nestjs/testing';
import { resolve } from 'node:path';
import type { Pool } from 'pg';
import request from 'supertest';
import { JwtAuthGuard } from '../src/auth/jwt-auth.guard';
import { PaymentsController } from '../src/payments/payments.controller';
import { PaymentsService } from '../src/payments/payments.service';
import { SupabaseService } from '../src/supabase/supabase.service';
import { DisposablePostgres } from './support/disposable-postgres';

const USER_ID = '11111111-1111-4111-8111-111111111111';
const SESSION_ID = '22222222-2222-4222-8222-222222222222';
const RESTAURANT_ID = '33333333-3333-4333-8333-333333333333';
const ORDER_ID = '55555555-5555-4555-8555-555555555555';
const PAYMENT_KEY = 'test_payment_key_postgres_reconciliation';
const AMOUNT = 12_000;

type PaymentOrderRow = {
  id: string;
  status: string;
  total_price: number;
  payment_method: string;
  session_id: string;
  user_id: string;
  payment_key: string | null;
};

type QueryError = { message: string };
type QueryResult<T> = { data: T | null; error: QueryError | null };

class PaymentPostgresClient {
  constructor(
    private readonly pool: Pool,
    private updateFailuresRemaining = 1,
  ) {}

  from(table: string) {
    if (table !== 'orders') {
      throw new Error(`Unexpected payment test table: ${table}`);
    }

    return {
      select: (_columns: string) => ({
        eq: (_column: string, orderId: string) => ({
          single: () => this.selectOrder(orderId),
        }),
      }),
      update: (payload: Record<string, unknown>) => this.updateOrder(payload),
    };
  }

  private updateOrder(payload: Record<string, unknown>) {
    const filters = new Map<string, unknown>();
    const builder = {
      eq: (column: string, value: unknown) => {
        filters.set(column, value);
        return builder;
      },
      select: (_columns: string) => ({
        maybeSingle: () => this.updateSingleOrder(payload, filters),
      }),
    };
    return builder;
  }

  private async selectOrder(
    orderId: string,
  ): Promise<QueryResult<PaymentOrderRow>> {
    try {
      const result = await this.pool.query<PaymentOrderRow>(
        `
          SELECT id, status, total_price, payment_method, session_id, user_id, payment_key
          FROM public.orders
          WHERE id = $1::UUID
        `,
        [orderId],
      );
      return { data: result.rows[0] ?? null, error: null };
    } catch (error) {
      return this.failure(error);
    }
  }

  private async updateSingleOrder(
    payload: Record<string, unknown>,
    filters: Map<string, unknown>,
  ): Promise<QueryResult<PaymentOrderRow>> {
    if (this.updateFailuresRemaining > 0) {
      this.updateFailuresRemaining -= 1;
      return {
        data: null,
        error: { message: 'synthetic database write unavailable' },
      };
    }

    try {
      const result = await this.pool.query<PaymentOrderRow>(
        `
          UPDATE public.orders
          SET status = $3::TEXT,
              payment_key = $4::TEXT
          WHERE id = $1::UUID
            AND status = $2::TEXT
          RETURNING id, status, total_price, payment_method, session_id, user_id, payment_key
        `,
        [
          filters.get('id'),
          filters.get('status'),
          payload.status,
          payload.payment_key,
        ],
      );
      return { data: result.rows[0] ?? null, error: null };
    } catch (error) {
      return this.failure(error);
    }
  }

  private failure(error: unknown): QueryResult<never> {
    return {
      data: null,
      error: {
        message: error instanceof Error ? error.message : String(error),
      },
    };
  }
}

describe('Payment reconciliation PostgreSQL acceptance', () => {
  let app: INestApplication;
  let database: DisposablePostgres;
  let originalFetch: typeof fetch;

  beforeAll(async () => {
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

    database = await DisposablePostgres.start(
      resolve(
        __dirname,
        '../scripts/migrations/2026-07-27-create-order-with-items-v2.sql',
      ),
    );
    await database.pool.query(
      'INSERT INTO public.restaurants (id) VALUES ($1)',
      [RESTAURANT_ID],
    );
    await database.pool.query(
      "INSERT INTO public.users (id, role) VALUES ($1, 'CUSTOMER')",
      [USER_ID],
    );
    await database.pool.query('INSERT INTO public.sessions (id) VALUES ($1)', [
      SESSION_ID,
    ]);
    await database.pool.query(
      `
        INSERT INTO public.orders (
          id,
          session_id,
          user_id,
          restaurant_id,
          total_price,
          payment_method,
          status
        )
        VALUES ($1, $2, $3, $4, $5, 'TOSS', 'PENDING')
      `,
      [ORDER_ID, SESSION_ID, USER_ID, RESTAURANT_ID, AMOUNT],
    );

    const moduleRef = await Test.createTestingModule({
      controllers: [PaymentsController],
      providers: [
        PaymentsService,
        {
          provide: SupabaseService,
          useValue: {
            client: new PaymentPostgresClient(database.pool),
          },
        },
        {
          provide: ConfigService,
          useValue: {
            getOrThrow: () => 'toss-test-key-placeholder',
            get: (key: string) =>
              key === 'TOSS_API_BASE_URL' ? 'https://toss.test' : undefined,
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

    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api');
    await app.init();
  }, 60_000);

  afterAll(async () => {
    global.fetch = originalFetch;
    try {
      await app?.close();
    } finally {
      await database?.stop();
    }
  }, 30_000);

  it('recovers a Toss-approved payment with one real conditional DB update', async () => {
    const paymentRequest = {
      paymentKey: PAYMENT_KEY,
      orderId: ORDER_ID,
      amount: AMOUNT,
    };

    const firstResponse = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send(paymentRequest);
    const pendingRow = await database.pool.query<PaymentOrderRow>(
      `
        SELECT id, status, total_price, payment_method, session_id, user_id, payment_key
        FROM public.orders
        WHERE id = $1::UUID
      `,
      [ORDER_ID],
    );

    const retryResponse = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send(paymentRequest);
    const alreadySyncedResponse = await request(app.getHttpServer())
      .post('/api/payments/confirm')
      .send(paymentRequest);
    const paidRow = await database.pool.query<PaymentOrderRow>(
      `
        SELECT id, status, total_price, payment_method, session_id, user_id, payment_key
        FROM public.orders
        WHERE id = $1::UUID
      `,
      [ORDER_ID],
    );

    const fetchMock = global.fetch as jest.MockedFunction<typeof fetch>;
    const idempotencyKeys = fetchMock.mock.calls.map(([, init]) => {
      const headers = init?.headers as Record<string, string>;
      return headers['Idempotency-Key'];
    });

    expect({
      firstStatus: firstResponse.status,
      firstCode: firstResponse.body.code,
      pendingStatus: pendingRow.rows[0].status,
      retryStatus: retryResponse.status,
      retryPaymentStatus: retryResponse.body.data?.status,
      alreadySyncedStatus: alreadySyncedResponse.status,
      alreadyPaid: alreadySyncedResponse.body.data?.alreadyPaid,
      paidStatus: paidRow.rows[0].status,
      storedPaymentKey: paidRow.rows[0].payment_key,
      tossCalls: fetchMock.mock.calls.length,
      idempotencyKeys,
    }).toEqual({
      firstStatus: 503,
      firstCode: 'PAYMENT_APPROVED_DB_SYNC_PENDING',
      pendingStatus: 'PENDING',
      retryStatus: 201,
      retryPaymentStatus: 'PAID',
      alreadySyncedStatus: 201,
      alreadyPaid: true,
      paidStatus: 'PAID',
      storedPaymentKey: PAYMENT_KEY,
      tossCalls: 2,
      idempotencyKeys: [
        `lunchsync-confirm:${ORDER_ID}`,
        `lunchsync-confirm:${ORDER_ID}`,
      ],
    });
  });
});
