import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { promisify } from 'node:util';
import { Pool } from 'pg';

const execFileAsync = promisify(execFile);
const POSTGRES_IMAGE = 'postgres:16-alpine';
const POSTGRES_PASSWORD = 'lunchsync_test_password';
const POSTGRES_DATABASE = 'lunchsync_test';
const DOCKER_COMMAND_TIMEOUT_MS = 8_000;
const POSTGRES_START_TIMEOUT_MS = 60_000;
const POSTGRES_READY_TIMEOUT_MS = 30_000;
const POSTGRES_QUERY_TIMEOUT_MS = 4_000;
const POSTGRES_POOL_CLOSE_TIMEOUT_MS = 4_000;
const RETRY_DELAY_MS = 250;

const MINIMAL_ORDER_SCHEMA = `
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;

CREATE TYPE public.payment_method_type AS ENUM (
  'TOSS',
  'CARD',
  'CASH',
  'SIMULATE'
);

CREATE TABLE public.restaurants (
  id UUID PRIMARY KEY
);

CREATE TABLE public.users (
  id UUID PRIMARY KEY,
  role TEXT NOT NULL,
  restaurant_id UUID REFERENCES public.restaurants(id)
);

CREATE TABLE public.sessions (
  id UUID PRIMARY KEY
);

CREATE TABLE public.menu_items (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  price INT NOT NULL,
  restaurant_id UUID NOT NULL REFERENCES public.restaurants(id)
);

CREATE TABLE public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.sessions(id),
  user_id UUID NOT NULL REFERENCES public.users(id),
  restaurant_id UUID NOT NULL REFERENCES public.restaurants(id),
  total_price INT NOT NULL,
  payment_method public.payment_method_type NOT NULL,
  payment_key TEXT,
  status TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id),
  menu_item_id UUID NOT NULL REFERENCES public.menu_items(id),
  quantity INT NOT NULL CHECK (quantity BETWEEN 1 AND 10),
  price INT NOT NULL
);

-- Seed the obsolete production signature so the acceptance test proves that
-- the migration removes it instead of only proving that a clean database
-- happens not to contain it.
CREATE FUNCTION public.create_order_with_items(
  p_session_id UUID,
  p_user_id UUID,
  p_total_price INT,
  p_payment_method TEXT,
  p_items JSON
) RETURNS JSON
LANGUAGE SQL
AS $$
  SELECT '{}'::JSON
$$;

-- Supabase's service role executes SECURITY INVOKER RPCs with the underlying
-- database privileges needed by the backend. Keep the disposable database
-- faithful to that contract so a successful SET ROLE call exercises the
-- function body rather than PostgreSQL superuser privileges.
GRANT USAGE ON SCHEMA public TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA public
TO service_role;
GRANT USAGE, SELECT
ON ALL SEQUENCES IN SCHEMA public
TO service_role;
`;

async function withTimeout<T>(
  operation: Promise<T>,
  timeoutMs: number,
  description: string,
): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () => reject(new Error(`${description} timed out after ${timeoutMs}ms`)),
      timeoutMs,
    );
  });

  try {
    return await Promise.race([operation, timeout]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

function remainingStartupTime(
  deadline: number,
  maximumMs: number,
  description: string,
): number {
  const remainingMs = deadline - Date.now();
  if (remainingMs <= 0) {
    throw new Error(
      `PostgreSQL startup timed out after ${POSTGRES_START_TIMEOUT_MS}ms ` +
        `before ${description}`,
    );
  }
  return Math.min(maximumMs, remainingMs);
}

async function runDocker(
  args: string[],
  timeoutMs = DOCKER_COMMAND_TIMEOUT_MS,
): Promise<string> {
  const { stdout } = await execFileAsync('docker', args, {
    encoding: 'utf8',
    timeout: timeoutMs,
    windowsHide: true,
  });
  return stdout.trim();
}

async function waitBeforeRetry(deadline: number): Promise<void> {
  const delayMs = Math.min(RETRY_DELAY_MS, deadline - Date.now());
  if (delayMs > 0) {
    await new Promise((resolve) => setTimeout(resolve, delayMs));
  }
}

async function resolvePublishedPort(
  containerName: string,
  startupDeadline: number,
): Promise<number> {
  const deadline = Math.min(
    startupDeadline,
    Date.now() + POSTGRES_READY_TIMEOUT_MS,
  );
  while (Date.now() < deadline) {
    try {
      const address = await runDocker(
        ['port', containerName, '5432/tcp'],
        remainingStartupTime(deadline, 2_000, 'Docker port discovery'),
      );
      const match = address.match(/:(\d+)\s*$/);
      if (match) return Number(match[1]);
    } catch {
      // Docker can take a moment to publish the port after `run` returns.
    }
    await waitBeforeRetry(deadline);
  }
  throw new Error(`PostgreSQL port was not published for ${containerName}`);
}

async function waitUntilReady(
  pool: Pool,
  startupDeadline: number,
): Promise<void> {
  const deadline = Math.min(
    startupDeadline,
    Date.now() + POSTGRES_READY_TIMEOUT_MS,
  );
  let lastError: unknown;
  while (Date.now() < deadline) {
    try {
      await pool.query('SELECT 1');
      return;
    } catch (error) {
      lastError = error;
      await waitBeforeRetry(deadline);
    }
  }
  throw new Error(`PostgreSQL did not become ready: ${String(lastError)}`);
}

async function closePool(pool: Pool): Promise<void> {
  await withTimeout(
    pool.end(),
    POSTGRES_POOL_CLOSE_TIMEOUT_MS,
    'PostgreSQL pool shutdown',
  );
}

export class DisposablePostgres {
  private stopped = false;

  private constructor(
    readonly pool: Pool,
    private readonly containerName: string,
  ) {}

  static async start(migrationPath: string): Promise<DisposablePostgres> {
    const containerName =
      `lunchsync-order-acceptance-${process.pid}-${randomUUID()}`.toLowerCase();
    const startupDeadline = Date.now() + POSTGRES_START_TIMEOUT_MS;
    let pool: Pool | undefined;

    try {
      await runDocker(
        [
          'run',
          '--detach',
          '--rm',
          '--name',
          containerName,
          '--env',
          `POSTGRES_PASSWORD=${POSTGRES_PASSWORD}`,
          '--env',
          `POSTGRES_DB=${POSTGRES_DATABASE}`,
          '--publish',
          '127.0.0.1::5432',
          POSTGRES_IMAGE,
        ],
        remainingStartupTime(
          startupDeadline,
          DOCKER_COMMAND_TIMEOUT_MS,
          'Docker container creation',
        ),
      );

      const port = await resolvePublishedPort(containerName, startupDeadline);
      pool = new Pool({
        host: '127.0.0.1',
        port,
        database: POSTGRES_DATABASE,
        user: 'postgres',
        password: POSTGRES_PASSWORD,
        max: 4,
        connectionTimeoutMillis: 1_000,
        query_timeout: POSTGRES_QUERY_TIMEOUT_MS,
        statement_timeout: POSTGRES_QUERY_TIMEOUT_MS,
      });
      await waitUntilReady(pool, startupDeadline);
      remainingStartupTime(
        startupDeadline,
        POSTGRES_QUERY_TIMEOUT_MS,
        'minimal schema creation',
      );
      await pool.query(MINIMAL_ORDER_SCHEMA);
      remainingStartupTime(
        startupDeadline,
        POSTGRES_QUERY_TIMEOUT_MS,
        'order migration',
      );
      await pool.query(await readFile(migrationPath, 'utf8'));

      return new DisposablePostgres(pool, containerName);
    } catch (error) {
      // Startup is already failing, so cleanup is deliberately best-effort and
      // must not hide the original failure.
      await Promise.allSettled([
        ...(pool ? [closePool(pool)] : []),
        runDocker(['rm', '--force', containerName]),
      ]);
      throw error;
    }
  }

  async stop(): Promise<void> {
    if (this.stopped) return;
    this.stopped = true;

    const results = await Promise.allSettled([
      closePool(this.pool),
      runDocker(['rm', '--force', this.containerName]),
    ]);
    const errors = results
      .filter(
        (result): result is PromiseRejectedResult =>
          result.status === 'rejected',
      )
      .map(({ reason }) => reason);

    if (errors.length === 1) throw errors[0];
    if (errors.length > 1) {
      throw new AggregateError(errors, 'Disposable PostgreSQL cleanup failed');
    }
  }
}

type QueryError = { message: string };
type SupabaseResult<T> = { data: T | null; error: QueryError | null };
type EqualityFilter = { column: string; value: unknown };
type OrderPaymentRow = {
  id: string;
  payment_key: string | null;
  status: string;
};
type OrderUpdateChain = {
  eq(column: string, value: unknown): OrderUpdateChain;
  select(columns: string): {
    single(): Promise<SupabaseResult<OrderPaymentRow>>;
  };
};

const ORDER_RPC_PARAMETERS = [
  'p_session_id',
  'p_user_id',
  'p_restaurant_id',
  'p_total_price',
  'p_payment_method',
  'p_items',
] as const;

export class PostgresSupabaseClient {
  constructor(private readonly pool: Pool) {}

  readonly rpc = async (
    functionName: string,
    parameters: Record<string, unknown>,
  ): Promise<SupabaseResult<unknown>> => {
    if (functionName !== 'create_order_with_items') {
      return {
        data: null,
        error: { message: `Unexpected RPC: ${functionName}` },
      };
    }

    const parameterNames = Object.keys(parameters).sort();
    const expectedParameterNames = [...ORDER_RPC_PARAMETERS].sort();
    if (
      parameterNames.length !== expectedParameterNames.length ||
      !parameterNames.every(
        (parameterName, index) =>
          parameterName === expectedParameterNames[index],
      ) ||
      ORDER_RPC_PARAMETERS.some(
        (parameterName) => parameters[parameterName] === undefined,
      )
    ) {
      return {
        data: null,
        error: {
          message:
            'Unexpected create_order_with_items parameter contract: ' +
            parameterNames.join(', '),
        },
      };
    }

    try {
      const result = await this.pool.query<{ data: unknown }>(
        `
          SELECT public.create_order_with_items(
            p_session_id => $1::UUID,
            p_user_id => $2::UUID,
            p_restaurant_id => $3::UUID,
            p_total_price => $4::INT,
            p_payment_method => $5::TEXT,
            p_items => $6::JSON
          ) AS data
        `,
        [
          parameters.p_session_id,
          parameters.p_user_id,
          parameters.p_restaurant_id,
          parameters.p_total_price,
          parameters.p_payment_method,
          JSON.stringify(parameters.p_items),
        ],
      );
      return { data: result.rows[0].data, error: null };
    } catch (error) {
      return {
        data: null,
        error: {
          message: error instanceof Error ? error.message : String(error),
        },
      };
    }
  };

  from(table: string): any {
    if (table === 'menu_items') {
      return {
        select: () => ({
          in: async (_column: string, ids: string[]) => {
            try {
              const result = await this.pool.query(
                `
                  SELECT id, name, price, restaurant_id
                  FROM public.menu_items
                  WHERE id = ANY($1::UUID[])
                `,
                [ids],
              );
              return { data: result.rows, error: null };
            } catch (error) {
              return this.failure(error);
            }
          },
        }),
      };
    }

    if (table === 'users') {
      return {
        select: () => ({
          eq: (_column: string, userId: string) => ({
            maybeSingle: async () => {
              try {
                const result = await this.pool.query(
                  `
                    SELECT role, restaurant_id
                    FROM public.users
                    WHERE id = $1::UUID
                  `,
                  [userId],
                );
                return { data: result.rows[0] ?? null, error: null };
              } catch (error) {
                return this.failure(error);
              }
            },
          }),
        }),
      };
    }

    if (table === 'orders') {
      return {
        update: (payload: Record<string, unknown>) => this.orderUpdate(payload),
        select: () => ({
          eq: (_column: string, userId: string) => ({
            gte: (_createdAt: string, earliest: string) => ({
              order: async () => {
                try {
                  const result = await this.pool.query(
                    `
                      SELECT id, session_id, status, total_price, created_at
                      FROM public.orders
                      WHERE user_id = $1::UUID
                        AND created_at >= $2::TIMESTAMPTZ
                      ORDER BY created_at DESC
                    `,
                    [userId, earliest],
                  );
                  return { data: result.rows, error: null };
                } catch (error) {
                  return this.failure(error);
                }
              },
            }),
          }),
        }),
      };
    }

    throw new Error(`Unexpected table in PostgreSQL acceptance test: ${table}`);
  }

  private orderUpdate(payload: Record<string, unknown>): OrderUpdateChain {
    const filters: EqualityFilter[] = [];
    const chain: OrderUpdateChain = {
      eq: (column: string, value: unknown) => {
        filters.push({ column, value });
        return chain;
      },
      select: (columns: string) => ({
        single: () => this.updateSingleOrder(payload, filters, columns),
      }),
    };
    return chain;
  }

  private async updateSingleOrder(
    payload: Record<string, unknown>,
    filters: EqualityFilter[],
    columns: string,
  ): Promise<SupabaseResult<OrderPaymentRow>> {
    const payloadColumns = Object.keys(payload).sort();
    const selectedColumns = columns
      .split(',')
      .map((column) => column.trim())
      .sort();
    const idFilters = filters.filter(({ column }) => column === 'id');
    const statusFilters = filters.filter(({ column }) => column === 'status');
    const hasExactPaymentUpdateContract =
      payloadColumns.join(',') === 'payment_key,status' &&
      selectedColumns.join(',') === 'id,payment_key,status' &&
      filters.length === 2 &&
      idFilters.length === 1 &&
      statusFilters.length === 1 &&
      typeof idFilters[0].value === 'string' &&
      typeof statusFilters[0].value === 'string' &&
      typeof payload.status === 'string' &&
      typeof payload.payment_key === 'string';

    if (!hasExactPaymentUpdateContract) {
      return {
        data: null,
        error: {
          message:
            'Unexpected orders payment update contract: expected ' +
            "update(status, payment_key).eq('id').eq('status')." +
            'select(id, status, payment_key).single()',
        },
      };
    }

    const orderId = idFilters[0].value as string;
    const expectedCurrentStatus = statusFilters[0].value as string;
    const expectedPaidStatus = payload.status as string;
    const expectedPaymentKey = payload.payment_key as string;

    try {
      const result = await this.pool.query<OrderPaymentRow>(
        `
          UPDATE public.orders
          SET status = $3::TEXT,
              payment_key = $4::TEXT
          WHERE id = $1::UUID
            AND status = $2::TEXT
          RETURNING id, status, payment_key
        `,
        [
          orderId,
          expectedCurrentStatus,
          expectedPaidStatus,
          expectedPaymentKey,
        ],
      );

      if (result.rows.length !== 1) {
        return {
          data: null,
          error: {
            message:
              'Expected exactly one updated order, received ' +
              result.rows.length,
          },
        };
      }

      const updatedOrder = result.rows[0];
      if (
        updatedOrder.id !== orderId ||
        updatedOrder.status !== expectedPaidStatus ||
        updatedOrder.payment_key !== expectedPaymentKey
      ) {
        return {
          data: null,
          error: {
            message: 'Updated order did not match the requested payment values',
          },
        };
      }

      return { data: updatedOrder, error: null };
    } catch (error) {
      return this.failure(error);
    }
  }

  private failure(error: unknown): SupabaseResult<never> {
    return {
      data: null,
      error: {
        message: error instanceof Error ? error.message : String(error),
      },
    };
  }
}
