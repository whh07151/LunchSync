import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import type { QueryResultRow } from 'pg';
import request from 'supertest';
import { JwtAuthGuard } from '../src/auth/jwt-auth.guard';
import { OrdersController } from '../src/orders/orders.controller';
import { OrdersService } from '../src/orders/orders.service';
import { SupabaseService } from '../src/supabase/supabase.service';
import {
  DisposablePostgres,
  PostgresSupabaseClient,
} from './support/disposable-postgres';

const USER_ID = '11111111-1111-4111-8111-111111111111';
const SESSION_ID = '22222222-2222-4222-8222-222222222222';
const RESTAURANT_ID = '33333333-3333-4333-8333-333333333333';
const MENU_ITEM_ID = '44444444-4444-4444-8444-444444444444';

type DatabaseRole = 'anon' | 'authenticated' | 'service_role';

async function queryAsRole<T extends QueryResultRow>(
  database: DisposablePostgres,
  role: DatabaseRole,
  text: string,
  values: unknown[] = [],
): Promise<T[]> {
  const client = await database.pool.connect();
  try {
    await client.query(`SET ROLE ${role}`);
    return (await client.query<T>(text, values)).rows;
  } finally {
    try {
      await client.query('RESET ROLE');
    } finally {
      client.release();
    }
  }
}

describe('Order creation PostgreSQL acceptance', () => {
  let database: DisposablePostgres;
  let app: INestApplication;

  beforeAll(async () => {
    database = await DisposablePostgres.start(
      resolve(
        __dirname,
        '../scripts/migrations/2026-07-27-create-order-with-items-v2.sql',
      ),
    );
    await database.pool.query(
      await readFile(
        resolve(
          __dirname,
          '../scripts/migrations/2026-07-29-schema-introspection-function-signatures.sql',
        ),
        'utf8',
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
        INSERT INTO public.menu_items (id, name, price, restaurant_id)
        VALUES ($1, 'Atomic lunch', 12000, $2)
      `,
      [MENU_ITEM_ID, RESTAURANT_ID],
    );

    const postgresClient = new PostgresSupabaseClient(database.pool);
    const moduleRef = await Test.createTestingModule({
      controllers: [OrdersController],
      providers: [
        OrdersService,
        {
          provide: SupabaseService,
          useValue: { client: postgresClient },
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
    app.useGlobalPipes(
      new ValidationPipe({ transform: true, whitelist: true }),
    );
    await app.init();
  }, 60_000);

  afterAll(async () => {
    try {
      await app?.close();
    } finally {
      await database?.stop();
    }
  }, 30_000);

  it('rolls back the order header when a real line-item insert fails', async () => {
    const createResponse = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 11 }],
        paymentMethod: 'SIMULATE',
      });
    const todayResponse = await request(app.getHttpServer()).get(
      '/api/orders/today',
    );

    const persisted = await database.pool.query<{
      order_count: number;
      order_item_count: number;
    }>(
      `
        SELECT
          (SELECT COUNT(*)::INT FROM public.orders) AS order_count,
          (SELECT COUNT(*)::INT FROM public.order_items) AS order_item_count
      `,
    );

    expect({
      createStatus: createResponse.status,
      visibleOrders: todayResponse.body.data,
      persisted: persisted.rows[0],
    }).toEqual({
      createStatus: 500,
      visibleOrders: [],
      persisted: {
        order_count: 0,
        order_item_count: 0,
      },
    });
  });

  it('persists an HTTP order, its item, and the completed simulated payment', async () => {
    const createResponse = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 2 }],
        paymentMethod: 'cash',
      });

    expect(createResponse.status).toBe(201);
    expect(createResponse.body).toEqual({
      success: true,
      data: expect.objectContaining({
        id: expect.any(String),
        items: [
          {
            menuItemId: MENU_ITEM_ID,
            price: 12_000,
            quantity: 2,
          },
        ],
        paymentKey: expect.stringMatching(/^sim_.+_\d+$/),
        paymentMethod: 'CASH',
        sessionId: SESSION_ID,
        status: 'PAID',
        totalPrice: 24_000,
      }),
    });

    const orderId = createResponse.body.data.id as string;
    const paymentKey = createResponse.body.data.paymentKey as string;
    const persisted = await database.pool.query<{
      item_count: number;
      menu_item_id: string;
      payment_key: string;
      payment_method: string;
      quantity: number;
      status: string;
      total_price: number;
    }>(
      `
        SELECT
          COUNT(oi.id)::INT AS item_count,
          MAX(oi.menu_item_id::TEXT) AS menu_item_id,
          MAX(o.payment_key) AS payment_key,
          MAX(o.payment_method::TEXT) AS payment_method,
          MAX(oi.quantity)::INT AS quantity,
          MAX(o.status) AS status,
          MAX(o.total_price)::INT AS total_price
        FROM public.orders o
        JOIN public.order_items oi ON oi.order_id = o.id
        WHERE o.id = $1::UUID
        GROUP BY o.id
      `,
      [orderId],
    );

    expect(persisted.rows).toEqual([
      {
        item_count: 1,
        menu_item_id: MENU_ITEM_ID,
        payment_key: paymentKey,
        payment_method: 'CASH',
        quantity: 2,
        status: 'PAID',
        total_price: 24_000,
      },
    ]);
  });

  it('removes the obsolete overload and enforces the order RPC role boundary', async () => {
    const metadata = await database.pool.query<{
      obsolete_removed: boolean;
      overload_count: number;
      public_execute: boolean;
      anon: boolean;
      authenticated: boolean;
      service_role: boolean;
      security_invoker: boolean;
      fixed_search_path: boolean;
    }>(
      `
        SELECT
          to_regprocedure(
            'public.create_order_with_items(uuid,uuid,integer,text,json)'
          ) IS NULL AS obsolete_removed,
          (
            SELECT COUNT(*)::INT
            FROM pg_proc overload
            JOIN pg_namespace overload_namespace
              ON overload_namespace.oid = overload.pronamespace
            WHERE overload_namespace.nspname = 'public'
              AND overload.proname = 'create_order_with_items'
          ) AS overload_count,
          EXISTS (
            SELECT 1
            FROM aclexplode(
              COALESCE(p.proacl, acldefault('f', p.proowner))
            ) AS acl
            WHERE acl.grantee = 0
              AND acl.privilege_type = 'EXECUTE'
          ) AS public_execute,
          has_function_privilege('anon', p.oid, 'EXECUTE') AS anon,
          has_function_privilege(
            'authenticated',
            p.oid,
            'EXECUTE'
          ) AS authenticated,
          has_function_privilege(
            'service_role',
            p.oid,
            'EXECUTE'
          ) AS service_role,
          NOT p.prosecdef AS security_invoker,
          COALESCE(
            p.proconfig @> ARRAY['search_path=pg_catalog, pg_temp'],
            FALSE
          ) AS fixed_search_path
        FROM pg_proc p
        WHERE p.oid = to_regprocedure(
          'public.create_order_with_items(' ||
          'uuid,uuid,uuid,integer,text,json)'
        )
      `,
    );

    expect(metadata.rows).toEqual([
      {
        obsolete_removed: true,
        overload_count: 1,
        public_execute: false,
        anon: false,
        authenticated: false,
        service_role: true,
        security_invoker: true,
        fixed_search_path: true,
      },
    ]);

    const callOrderRpc = `
      SELECT public.create_order_with_items(
        $1::UUID,
        $2::UUID,
        $3::UUID,
        $4::INT,
        $5::TEXT,
        $6::JSON
      ) AS order_result
    `;
    const parameters = [
      SESSION_ID,
      USER_ID,
      RESTAURANT_ID,
      12_000,
      'SIMULATE',
      JSON.stringify([
        {
          menuItemId: MENU_ITEM_ID,
          quantity: 1,
          price: 12_000,
        },
      ]),
    ];

    for (const role of ['anon', 'authenticated'] as const) {
      await expect(
        queryAsRole(database, role, callOrderRpc, parameters),
      ).rejects.toMatchObject({
        code: '42501',
        message: expect.stringContaining(
          'permission denied for function create_order_with_items',
        ),
      });
    }

    const serviceResult = await queryAsRole<{
      order_result: {
        id: string;
        items: Array<{
          menuItemId: string;
          price: number;
          quantity: number;
        }>;
        restaurantId: string;
        sessionId: string;
        userId: string;
      };
    }>(database, 'service_role', callOrderRpc, parameters);

    expect(serviceResult).toEqual([
      {
        order_result: expect.objectContaining({
          id: expect.any(String),
          items: [
            expect.objectContaining({
              menuItemId: MENU_ITEM_ID,
              price: 12_000,
              quantity: 1,
            }),
          ],
          restaurantId: RESTAURANT_ID,
          sessionId: SESSION_ID,
          userId: USER_ID,
        }),
      },
    ]);
  });

  it('locks down the SECURITY DEFINER introspection RPC and reports the exact order signature', async () => {
    const metadata = await database.pool.query<{
      anon: boolean;
      authenticated: boolean;
      fixed_search_path: boolean;
      public_execute: boolean;
      security_definer: boolean;
      service_role: boolean;
    }>(
      `
        SELECT
          p.prosecdef AS security_definer,
          COALESCE(
            p.proconfig @> ARRAY['search_path=pg_catalog, pg_temp'],
            FALSE
          ) AS fixed_search_path,
          EXISTS (
            SELECT 1
            FROM aclexplode(
              COALESCE(p.proacl, acldefault('f', p.proowner))
            ) AS acl
            WHERE acl.grantee = 0
              AND acl.privilege_type = 'EXECUTE'
          ) AS public_execute,
          has_function_privilege('anon', p.oid, 'EXECUTE') AS anon,
          has_function_privilege(
            'authenticated',
            p.oid,
            'EXECUTE'
          ) AS authenticated,
          has_function_privilege(
            'service_role',
            p.oid,
            'EXECUTE'
          ) AS service_role
        FROM pg_proc p
        WHERE p.oid = to_regprocedure('public.check_schema_resources()')
      `,
    );

    expect(metadata.rows).toEqual([
      {
        anon: false,
        authenticated: false,
        fixed_search_path: true,
        public_execute: false,
        security_definer: true,
        service_role: true,
      },
    ]);

    for (const role of ['anon', 'authenticated'] as const) {
      await expect(
        queryAsRole(
          database,
          role,
          'SELECT public.check_schema_resources() AS schema',
        ),
      ).rejects.toMatchObject({
        code: '42501',
        message: expect.stringContaining(
          'permission denied for function check_schema_resources',
        ),
      });
    }

    const result = await queryAsRole<{
      schema: {
        functions: Array<{
          contract: {
            parameters: Array<{ name: string; type: string }>;
            returnType: string;
          } | null;
          name: string;
          parameters: Array<{ name: string; type: string }> | null;
          signature: string | null;
          present: boolean;
          returnType: string | null;
        }>;
      };
    }>(
      database,
      'service_role',
      'SELECT public.check_schema_resources() AS schema',
    );
    const orderRpc = result[0].schema.functions.find(
      ({ name }) => name === 'create_order_with_items',
    );
    const expectedParameters = [
      { name: 'p_session_id', type: 'uuid' },
      { name: 'p_user_id', type: 'uuid' },
      { name: 'p_restaurant_id', type: 'uuid' },
      { name: 'p_total_price', type: 'integer' },
      { name: 'p_payment_method', type: 'text' },
      { name: 'p_items', type: 'json' },
    ];

    expect(orderRpc).toEqual({
      contract: {
        parameters: expectedParameters,
        returnType: 'json',
      },
      name: 'create_order_with_items',
      parameters: expectedParameters,
      present: true,
      returnType: 'json',
      signature:
        'public.create_order_with_items(uuid,uuid,uuid,integer,text,json)',
    });
  });
});
