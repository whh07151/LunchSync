import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SupabaseService } from '../supabase/supabase.service';
import { OrdersController } from './orders.controller';
import { OrdersService } from './orders.service';

const USER_ID = '11111111-1111-4111-8111-111111111111';
const SESSION_ID = '22222222-2222-4222-8222-222222222222';
const RESTAURANT_ID = '33333333-3333-4333-8333-333333333333';
const MENU_ITEM_ID = '44444444-4444-4444-8444-444444444444';

type StoredOrder = {
  id: string;
  session_id: string;
  user_id: string;
  restaurant_id: string;
  total_price: number;
  status: string;
  payment_method: string;
  payment_key?: string;
  created_at: string;
};

class OrderTestDatabase {
  readonly orders: StoredOrder[] = [];
  lastRpcFunctionName: string | null = null;
  lastRpcParameters: Record<string, unknown> | null = null;
  sessionMember = true;
  sessionStatus = 'ORDERED';
  sessionWinnerRestaurantId: string | null = RESTAURANT_ID;
  rpcFailureMessage = 'order_items insert failed';
  menuSource = 'MANUAL';
  menuAvailable = true;

  constructor(
    private readonly rpcShouldFail = true,
    private readonly paymentUpdateShouldFail = false,
    private readonly paymentUpdateShouldMiss = false,
    private readonly orderingUser: {
      role: string;
      restaurant_id: string | null;
    } = { role: 'CUSTOMER', restaurant_id: null },
    private readonly canonicalOwner = false,
  ) {}

  readonly client = {
    from: (table: string) => this.from(table),
    rpc: async (functionName: string, parameters: Record<string, unknown>) => {
      this.lastRpcFunctionName = functionName;
      this.lastRpcParameters = parameters;
      if (this.rpcShouldFail) {
        return {
          data: null,
          error: { message: this.rpcFailureMessage },
        };
      }
      if (
        functionName !== 'create_order_with_items' ||
        Object.keys(parameters).sort().join(',') !==
          [
            'p_items',
            'p_payment_method',
            'p_restaurant_id',
            'p_session_id',
            'p_total_price',
            'p_user_id',
          ]
            .sort()
            .join(',')
      ) {
        return {
          data: null,
          error: { message: 'unexpected order RPC contract' },
        };
      }

      const order: StoredOrder = {
        id: '55555555-5555-4555-8555-555555555555',
        session_id: parameters.p_session_id as string,
        user_id: parameters.p_user_id as string,
        restaurant_id: parameters.p_restaurant_id as string,
        total_price: parameters.p_total_price as number,
        status: 'PENDING',
        payment_method: parameters.p_payment_method as string,
        created_at: new Date().toISOString(),
      };
      this.orders.push(order);
      return {
        data: { id: order.id, createdAt: order.created_at },
        error: null,
      };
    },
  };

  private from(table: string): any {
    if (table === 'session_members') {
      const filters = new Map<string, unknown>();
      const builder = {
        eq: (column: string, value: unknown) => {
          filters.set(column, value);
          return builder;
        },
        maybeSingle: async () => ({
          data:
            this.sessionMember &&
            filters.get('session_id') === SESSION_ID &&
            filters.get('user_id') === USER_ID
              ? { user_id: USER_ID }
              : null,
          error: null,
        }),
      };
      return { select: () => builder };
    }

    if (table === 'sessions') {
      return {
        select: () => ({
          eq: (_column: string, sessionId: string) => ({
            maybeSingle: async () => ({
              data:
                sessionId === SESSION_ID
                  ? {
                      status: this.sessionStatus,
                      winner_restaurant_id: this.sessionWinnerRestaurantId,
                    }
                  : null,
              error: null,
            }),
          }),
        }),
      };
    }

    if (table === 'menu_items') {
      return {
        select: () => ({
          in: async () => ({
            data: [
              {
                id: MENU_ITEM_ID,
                name: 'Atomic lunch',
                price: 12_000,
                restaurant_id: RESTAURANT_ID,
                source: this.menuSource,
                is_available: this.menuAvailable,
              },
            ],
            error: null,
          }),
        }),
      };
    }

    if (table === 'users') {
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({
              data: this.orderingUser,
              error: null,
            }),
          }),
        }),
      };
    }

    if (table === 'restaurants') {
      const filters = new Map<string, unknown>();
      const builder = {
        eq: (column: string, value: unknown) => {
          filters.set(column, value);
          return builder;
        },
        maybeSingle: async () => ({
          data:
            this.canonicalOwner &&
            filters.get('id') === RESTAURANT_ID &&
            filters.get('owner_user_id') === USER_ID
              ? { id: RESTAURANT_ID }
              : null,
          error: null,
        }),
      };
      return { select: () => builder };
    }

    if (table === 'order_items') {
      return {
        insert: async () => ({
          data: null,
          error: { message: 'order_items insert failed' },
        }),
      };
    }

    if (table === 'orders') {
      return {
        insert: (payload: Omit<StoredOrder, 'id' | 'created_at'>) => {
          const order: StoredOrder = {
            ...payload,
            id: '55555555-5555-4555-8555-555555555555',
            created_at: new Date().toISOString(),
          };
          this.orders.push(order);
          return {
            select: () => ({
              single: async () => ({ data: order, error: null }),
            }),
          };
        },
        update: (payload: Partial<StoredOrder>) => {
          const filters = new Map<string, unknown>();
          const builder = {
            eq: (column: string, value: unknown) => {
              filters.set(column, value);
              return builder;
            },
            select: () => ({
              single: async () => {
                if (this.paymentUpdateShouldFail) {
                  return {
                    data: null,
                    error: { message: 'payment status update failed' },
                  };
                }

                const order = this.orders.find(
                  ({ id, status }) =>
                    id === filters.get('id') &&
                    (filters.get('status') === undefined ||
                      status === filters.get('status')),
                );
                if (!order || this.paymentUpdateShouldMiss) {
                  return {
                    data: null,
                    error: { message: 'payment update matched no order' },
                  };
                }

                Object.assign(order, payload);
                return { data: order, error: null };
              },
            }),
          };
          return builder;
        },
        select: () => ({
          eq: (_column: string, userId: string) => ({
            gte: () => ({
              order: async () => ({
                data: this.orders.filter(({ user_id }) => user_id === userId),
                error: null,
              }),
            }),
          }),
        }),
      };
    }

    throw new Error(`Unexpected table: ${table}`);
  }
}

async function createTestApplication(
  database: OrderTestDatabase,
): Promise<INestApplication> {
  const moduleRef = await Test.createTestingModule({
    controllers: [OrdersController],
    providers: [
      OrdersService,
      { provide: SupabaseService, useValue: database },
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
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
  await app.init();
  return app;
}

describe('Order creation consistency (HTTP acceptance)', () => {
  let app: INestApplication;
  let database: OrderTestDatabase;
  const originalNodeEnv = process.env.NODE_ENV;
  const originalSimulationFlag = process.env.ALLOW_SIMULATED_PAYMENTS;

  beforeEach(async () => {
    database = new OrderTestDatabase();
    app = await createTestApplication(database);
  });

  afterEach(async () => {
    await app.close();
    if (originalNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = originalNodeEnv;
    if (originalSimulationFlag === undefined)
      delete process.env.ALLOW_SIMULATED_PAYMENTS;
    else process.env.ALLOW_SIMULATED_PAYMENTS = originalSimulationFlag;
  });

  it('does not expose a partial order when its items cannot be persisted', async () => {
    process.env.ALLOW_SIMULATED_PAYMENTS = 'true';
    const createResponse = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
        paymentMethod: 'SIMULATE',
      });

    const todayResponse = await request(app.getHttpServer()).get(
      '/api/orders/today',
    );

    expect({
      createStatus: createResponse.status,
      createMessage: createResponse.body.message,
      visibleOrders: todayResponse.body.data,
    }).toEqual({
      createStatus: 500,
      createMessage: '주문을 생성할 수 없습니다.',
      visibleOrders: [],
    });
  });

  it('rejects an AI-priced menu before creating an order', async () => {
    database.menuSource = 'AI_GEMINI';
    const response = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
        paymentMethod: 'CASH',
      });

    expect(response.status).toBe(400);
    expect(database.lastRpcFunctionName).toBeNull();
    expect(database.orders).toHaveLength(0);
  });

  it('rejects a sold-out menu before creating an order', async () => {
    database.menuAvailable = false;
    const response = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
        paymentMethod: 'CASH',
      });

    expect(response.status).toBe(400);
    expect(database.lastRpcFunctionName).toBeNull();
  });

  it('keeps a normalized cash order pending until POS confirms receipt', async () => {
    await app.close();
    database = new OrderTestDatabase(false);
    app = await createTestApplication(database);
    process.env.NODE_ENV = 'production';

    const createResponse = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
        paymentMethod: 'cash',
      });

    expect({
      createStatus: createResponse.status,
      status: createResponse.body.data.status,
      paymentMethod: createResponse.body.data.paymentMethod,
      rpcFunctionName: database.lastRpcFunctionName,
      rpcParameters: database.lastRpcParameters,
    }).toEqual({
      createStatus: 201,
      status: 'PENDING',
      paymentMethod: 'CASH',
      rpcFunctionName: 'create_order_with_items',
      rpcParameters: {
        p_session_id: SESSION_ID,
        p_user_id: USER_ID,
        p_restaurant_id: RESTAURANT_ID,
        p_total_price: 12_000,
        p_payment_method: 'CASH',
        p_items: [
          {
            menuItemId: MENU_ITEM_ID,
            quantity: 1,
            price: 12_000,
          },
        ],
      },
    });
  });

  it('hides the session from a non-member and never calls the order RPC', async () => {
    await app.close();
    database = new OrderTestDatabase(false);
    database.sessionMember = false;
    app = await createTestApplication(database);

    const createResponse = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
        paymentMethod: 'CASH',
      });

    expect({
      status: createResponse.status,
      code: createResponse.body.code,
      rpcFunctionName: database.lastRpcFunctionName,
      storedOrders: database.orders,
    }).toEqual({
      status: 404,
      code: 'ORDER_SESSION_NOT_FOUND',
      rpcFunctionName: null,
      storedOrders: [],
    });
  });

  it('rejects a malformed session id before any database lookup', async () => {
    const createResponse = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: 'not-a-uuid',
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
        paymentMethod: 'CASH',
      });

    expect({
      status: createResponse.status,
      rpcFunctionName: database.lastRpcFunctionName,
      storedOrders: database.orders,
    }).toEqual({
      status: 400,
      rpcFunctionName: null,
      storedOrders: [],
    });
  });

  it('rejects an order before the session has selected a winner', async () => {
    await app.close();
    database = new OrderTestDatabase(false);
    database.sessionStatus = 'VOTING';
    database.sessionWinnerRestaurantId = null;
    app = await createTestApplication(database);

    const createResponse = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
        paymentMethod: 'CASH',
      });

    expect({
      status: createResponse.status,
      code: createResponse.body.code,
      rpcFunctionName: database.lastRpcFunctionName,
    }).toEqual({
      status: 409,
      code: 'ORDER_SESSION_NOT_READY',
      rpcFunctionName: null,
    });
  });

  it('rejects menu items from a restaurant other than the session winner', async () => {
    await app.close();
    database = new OrderTestDatabase(false);
    database.sessionWinnerRestaurantId =
      '77777777-7777-4777-8777-777777777777';
    app = await createTestApplication(database);

    const createResponse = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
        paymentMethod: 'CASH',
      });

    expect({
      status: createResponse.status,
      code: createResponse.body.code,
      rpcFunctionName: database.lastRpcFunctionName,
    }).toEqual({
      status: 409,
      code: 'ORDER_SESSION_RESTAURANT_MISMATCH',
      rpcFunctionName: null,
    });
  });

  it.each([
    {
      marker: 'ORDER_SESSION_MEMBER_REQUIRED',
      status: 404,
      code: 'ORDER_SESSION_NOT_FOUND',
    },
    {
      marker: 'ORDER_SESSION_NOT_READY',
      status: 409,
      code: 'ORDER_SESSION_NOT_READY',
    },
    {
      marker: 'ORDER_SESSION_RESTAURANT_MISMATCH',
      status: 409,
      code: 'ORDER_SESSION_RESTAURANT_MISMATCH',
    },
  ])(
    'maps an RPC race marker after service preflight: $marker',
    async ({ marker, status, code }) => {
      database.rpcFailureMessage = marker;

      const createResponse = await request(app.getHttpServer())
        .post('/api/orders')
        .send({
          sessionId: SESSION_ID,
          items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
          paymentMethod: 'CASH',
        });

      expect({
        status: createResponse.status,
        code: createResponse.body.code,
        rpcFunctionName: database.lastRpcFunctionName,
        storedOrders: database.orders,
      }).toEqual({
        status,
        code,
        rpcFunctionName: 'create_order_with_items',
        storedOrders: [],
      });
    },
  );

  it('rejects an owner ordering from a canonically owned restaurant even without a legacy mapping', async () => {
    await app.close();
    database = new OrderTestDatabase(
      false,
      false,
      false,
      { role: 'OWNER', restaurant_id: null },
      true,
    );
    app = await createTestApplication(database);

    const createResponse = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
        paymentMethod: 'CASH',
      });

    expect(createResponse.status).toBe(400);
    expect(createResponse.body.message).toContain(
      '본인이 운영하는 매장에는 주문할 수 없어요.',
    );
    expect(database.lastRpcFunctionName).toBeNull();
    expect(database.orders).toEqual([]);
  });

  it('rejects simulated payment in production before creating an order', async () => {
    process.env.NODE_ENV = 'production';
    process.env.ALLOW_SIMULATED_PAYMENTS = 'true';

    const createResponse = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
        paymentMethod: 'SIMULATE',
      });

    expect({
      status: createResponse.status,
      code: createResponse.body.code,
      rpcFunctionName: database.lastRpcFunctionName,
      storedOrders: database.orders,
    }).toEqual({
      status: 403,
      code: 'SIMULATED_PAYMENT_DISABLED',
      rpcFunctionName: null,
      storedOrders: [],
    });
  });

  it.each([undefined, '', 'false'])(
    'rejects simulated payment unless the opt-in flag is exactly true (%s)',
    async (flag) => {
      process.env.NODE_ENV = 'development';
      if (flag === undefined) delete process.env.ALLOW_SIMULATED_PAYMENTS;
      else process.env.ALLOW_SIMULATED_PAYMENTS = flag;

      const createResponse = await request(app.getHttpServer())
        .post('/api/orders')
        .send({
          sessionId: SESSION_ID,
          items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
          paymentMethod: 'SIMULATE',
        });

      expect(createResponse.status).toBe(403);
      expect(createResponse.body.code).toBe('SIMULATED_PAYMENT_DISABLED');
      expect(database.lastRpcFunctionName).toBeNull();
    },
  );

  it('defaults an omitted payment method to a pending Toss order', async () => {
    await app.close();
    database = new OrderTestDatabase(false);
    app = await createTestApplication(database);
    process.env.NODE_ENV = 'production';

    const createResponse = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
      });

    expect(createResponse.status).toBe(201);
    expect(createResponse.body.data).toMatchObject({
      paymentMethod: 'TOSS',
      paymentKey: null,
      status: 'PENDING',
    });
  });

  it('rejects an unknown payment method instead of treating it as paid', async () => {
    const createResponse = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
        paymentMethod: 'free-money',
      });

    expect(createResponse.status).toBe(400);
    expect(database.lastRpcFunctionName).toBeNull();
    expect(database.orders).toEqual([]);
  });

  it('keeps a production Toss payment pending for provider confirmation', async () => {
    await app.close();
    database = new OrderTestDatabase(false);
    app = await createTestApplication(database);
    process.env.NODE_ENV = 'production';

    const createResponse = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
        paymentMethod: 'TOSS',
      });

    expect(createResponse.status).toBe(201);
    expect(createResponse.body.data).toMatchObject({
      paymentMethod: 'TOSS',
      paymentKey: null,
      status: 'PENDING',
    });
  });

  it('does not report a simulated payment as paid when its status update fails', async () => {
    await app.close();
    database = new OrderTestDatabase(false, true);
    app = await createTestApplication(database);
    process.env.ALLOW_SIMULATED_PAYMENTS = 'true';

    const createResponse = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
        paymentMethod: 'SIMULATE',
      });

    expect({
      createStatus: createResponse.status,
      createMessage: createResponse.body.message,
      storedStatus: database.orders[0].status,
    }).toEqual({
      createStatus: 500,
      createMessage: '결제 상태를 저장할 수 없습니다.',
      storedStatus: 'PENDING',
    });
  });

  it('does not report a simulated payment as paid when no pending order is updated', async () => {
    await app.close();
    database = new OrderTestDatabase(false, false, true);
    app = await createTestApplication(database);
    process.env.ALLOW_SIMULATED_PAYMENTS = 'true';

    const createResponse = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        sessionId: SESSION_ID,
        items: [{ menuItemId: MENU_ITEM_ID, quantity: 1 }],
        paymentMethod: 'SIMULATE',
      });

    expect({
      createStatus: createResponse.status,
      createMessage: createResponse.body.message,
      storedStatus: database.orders[0].status,
    }).toEqual({
      createStatus: 500,
      createMessage: '결제 상태를 저장할 수 없습니다.',
      storedStatus: 'PENDING',
    });
  });
});
