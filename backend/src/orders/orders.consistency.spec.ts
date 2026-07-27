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

class OrderItemsFailureDatabase {
  readonly orders: StoredOrder[] = [];

  readonly client = {
    from: (table: string) => this.from(table),
    rpc: async () => ({
      data: null,
      error: { message: 'order_items insert failed' },
    }),
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
        update: (payload: Partial<StoredOrder>) => ({
          eq: async (_column: string, orderId: string) => {
            const order = this.orders.find(({ id }) => id === orderId);
            if (order) Object.assign(order, payload);
            return { data: null, error: null };
          },
        }),
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

describe('Order creation consistency (HTTP acceptance)', () => {
  let app: INestApplication;
  let database: OrderItemsFailureDatabase;

  beforeEach(async () => {
    database = new OrderItemsFailureDatabase();
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

    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api');
    await app.init();
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
      visibleOrders: todayResponse.body.data,
    }).toEqual({
      createStatus: 500,
      visibleOrders: [],
    });
  });
});
