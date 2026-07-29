import { INestApplication } from '@nestjs/common';
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

  constructor(
    private readonly rpcShouldFail = true,
    private readonly paymentUpdateShouldFail = false,
    private readonly paymentUpdateShouldMiss = false,
  ) {}

  readonly client = {
    from: (table: string) => this.from(table),
    rpc: async (functionName: string, parameters: Record<string, unknown>) => {
      this.lastRpcFunctionName = functionName;
      this.lastRpcParameters = parameters;
      if (this.rpcShouldFail) {
        return {
          data: null,
          error: { message: 'order_items insert failed' },
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
              data: { role: 'CUSTOMER', restaurant_id: null },
              error: null,
            }),
          }),
        }),
      };
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
  await app.init();
  return app;
}

describe('Order creation consistency (HTTP acceptance)', () => {
  let app: INestApplication;
  let database: OrderTestDatabase;

  beforeEach(async () => {
    database = new OrderTestDatabase();
    app = await createTestApplication(database);
  });

  afterEach(async () => {
    await app.close();
  });

  it('does not expose a partial order when its items cannot be persisted', async () => {
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

  it('uses the normalized payment method for persistence, payment, and response', async () => {
    await app.close();
    database = new OrderTestDatabase(false);
    app = await createTestApplication(database);

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
      status: 'PAID',
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

  it('does not report a simulated payment as paid when its status update fails', async () => {
    await app.close();
    database = new OrderTestDatabase(false, true);
    app = await createTestApplication(database);

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
