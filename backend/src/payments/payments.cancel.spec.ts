import {
  BadGatewayException,
  BadRequestException,
  ConflictException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SupabaseService } from '../supabase/supabase.service';
import { PaymentsService } from './payments.service';

const ORDER_ID = '22222222-2222-4222-8222-222222222222';
const PAYMENT_KEY = 'test_payment_key_refund';

function createService(timeoutMs = '2500') {
  return new PaymentsService(
    {} as SupabaseService,
    {
      getOrThrow: jest.fn().mockReturnValue('toss-test-secret'),
      get: jest.fn((key: string) => {
        if (key === 'TOSS_API_BASE_URL') return 'https://toss.test';
        if (key === 'TOSS_API_TIMEOUT_MS') return timeoutMs;
        return undefined;
      }),
    } as unknown as ConfigService,
  );
}

function successfulRefund(overrides: Record<string, unknown> = {}) {
  return {
    paymentKey: PAYMENT_KEY,
    orderId: ORDER_ID,
    status: 'CANCELED',
    totalAmount: 12_000,
    cancels: [
      {
        cancelAmount: 12_000,
        canceledAt: '2026-08-05T16:00:00+09:00',
        cancelStatus: 'DONE',
      },
    ],
    ...overrides,
  };
}

describe('PaymentsService cancel consistency', () => {
  let originalFetch: typeof fetch;

  beforeEach(() => {
    originalFetch = global.fetch;
  });

  afterEach(() => {
    global.fetch = originalFetch;
  });

  it('uses a stable order-scoped idempotency key and validates a completed refund', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => successfulRefund(),
    }) as unknown as typeof fetch;

    const result = await createService().cancelPayment(
      PAYMENT_KEY,
      '점주 취소',
      ORDER_ID,
    );

    const [, init] = (global.fetch as jest.MockedFunction<typeof fetch>).mock
      .calls[0];
    expect((init?.headers as Record<string, string>)['Idempotency-Key']).toBe(
      `lunchsync-cancel:${ORDER_ID}`,
    );
    expect(init?.signal).toBeDefined();
    expect(result).toMatchObject({
      paymentKey: PAYMENT_KEY,
      status: 'CANCELED',
      cancelAmount: 12_000,
    });
  });

  it.each([
    ['payment key', { paymentKey: 'different-payment' }],
    ['order id', { orderId: 'different-order' }],
    ['payment status', { status: 'DONE' }],
    ['cancel status', { cancels: [{ cancelAmount: 12_000, cancelStatus: 'FAILED' }] }],
  ])('rejects a mismatched Toss %s response', async (_label, override) => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => successfulRefund(override),
    }) as unknown as typeof fetch;

    await expect(
      createService().cancelPayment(PAYMENT_KEY, '점주 취소', ORDER_ID),
    ).rejects.toBeInstanceOf(BadGatewayException);
  });

  it('returns a retryable unavailable outcome for network failures', async () => {
    global.fetch = jest
      .fn()
      .mockRejectedValue(new Error('provider connection reset')) as unknown as typeof fetch;

    let thrown: unknown;
    try {
      await createService().cancelPayment(PAYMENT_KEY, '점주 취소', ORDER_ID);
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeInstanceOf(ServiceUnavailableException);
    expect((thrown as ServiceUnavailableException).getResponse()).toMatchObject({
      code: 'TOSS_REFUND_UNAVAILABLE',
      retryable: true,
      orderId: ORDER_ID,
    });
  });

  it('maps a Toss server failure to a retryable 503 outcome', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 503,
      json: async () => ({ code: 'PROVIDER_UNAVAILABLE' }),
    }) as unknown as typeof fetch;

    let thrown: unknown;
    try {
      await createService().cancelPayment(PAYMENT_KEY, '점주 취소', ORDER_ID);
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeInstanceOf(ServiceUnavailableException);
    expect((thrown as ServiceUnavailableException).getResponse()).toMatchObject({
      code: 'TOSS_REFUND_UNAVAILABLE',
      retryable: true,
      providerCode: 'PROVIDER_UNAVAILABLE',
    });
  });

  it('preserves an idempotent refund request that is still processing', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 409,
      json: async () => ({ code: 'IDEMPOTENT_REQUEST_PROCESSING' }),
    }) as unknown as typeof fetch;

    let thrown: unknown;
    try {
      await createService().cancelPayment(PAYMENT_KEY, '점주 취소', ORDER_ID);
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeInstanceOf(ConflictException);
    expect((thrown as ConflictException).getResponse()).toMatchObject({
      code: 'IDEMPOTENT_REQUEST_PROCESSING',
      retryable: true,
    });
  });

  it('does not collapse a non-JSON Toss 5xx response into a permanent failure', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 502,
      json: async () => {
        throw new SyntaxError('not JSON');
      },
    }) as unknown as typeof fetch;

    await expect(
      createService().cancelPayment(PAYMENT_KEY, '점주 취소', ORDER_ID),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('keeps a deterministic Toss 4xx rejection as a bad request', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 400,
      json: async () => ({ code: 'NOT_CANCELABLE_AMOUNT' }),
    }) as unknown as typeof fetch;

    await expect(
      createService().cancelPayment(PAYMENT_KEY, '점주 취소', ORDER_ID),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
