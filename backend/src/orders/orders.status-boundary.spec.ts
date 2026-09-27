import {
  BadRequestException,
  ConflictException,
  INestApplication,
  ValidationPipe,
} from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SupabaseService } from '../supabase/supabase.service';
import { OrdersController } from './orders.controller';
import { OrdersService } from './orders.service';

const USER_ID = '11111111-1111-4111-8111-111111111111';
const ORDER_ID = '22222222-2222-4222-8222-222222222222';

function pendingOrderQuery() {
  const builder = {
    select: jest.fn(),
    eq: jest.fn(),
    single: jest.fn(),
  };
  builder.select.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.single.mockResolvedValue({
    data: { id: ORDER_ID, user_id: USER_ID, status: 'PENDING' },
    error: null,
  });
  return builder;
}

function conditionalUpdateQuery(result: {
  data: { id: string; status: string; updated_at: string } | null;
  error: { message: string } | null;
}) {
  const builder = {
    update: jest.fn(),
    eq: jest.fn(),
    select: jest.fn(),
    maybeSingle: jest.fn(),
  };
  builder.update.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.select.mockReturnValue(builder);
  builder.maybeSingle.mockResolvedValue(result);
  return builder;
}

describe('customer order status boundary', () => {
  it('rejects a direct PENDING to PAID service transition before any update', async () => {
    const from = jest.fn().mockReturnValue(pendingOrderQuery());
    const service = new OrdersService({
      client: { from },
    } as unknown as SupabaseService);

    await expect(
      service.updateOrderStatus(ORDER_ID, USER_ID, { status: 'PAID' }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(from).toHaveBeenCalledTimes(1);
  });

  it('does not overwrite a payment transition that won the cancellation race', async () => {
    const updateQuery = conditionalUpdateQuery({ data: null, error: null });
    const from = jest
      .fn()
      .mockReturnValueOnce(pendingOrderQuery())
      .mockReturnValueOnce(updateQuery);
    const service = new OrdersService({
      client: { from },
    } as unknown as SupabaseService);

    await expect(
      service.updateOrderStatus(ORDER_ID, USER_ID, { status: 'CANCELLED' }),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(updateQuery.eq).toHaveBeenCalledWith('id', ORDER_ID);
    expect(updateQuery.eq).toHaveBeenCalledWith('status', 'PENDING');
  });

  describe('HTTP DTO', () => {
    let app: INestApplication;
    const ordersService = { updateOrderStatus: jest.fn() };

    beforeAll(async () => {
      const moduleRef = await Test.createTestingModule({
        controllers: [OrdersController],
        providers: [{ provide: OrdersService, useValue: ordersService }],
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
        new ValidationPipe({
          whitelist: true,
          forbidNonWhitelisted: true,
          transform: true,
        }),
      );
      await app.init();
    });

    afterAll(async () => {
      await app.close();
    });

    beforeEach(() => {
      jest.clearAllMocks();
    });

    it('rejects PAID at the HTTP boundary without invoking the service', async () => {
      const response = await request(app.getHttpServer())
        .patch(`/api/orders/${ORDER_ID}/status`)
        .send({ status: 'PAID' });

      expect(response.status).toBe(400);
      expect(ordersService.updateOrderStatus).not.toHaveBeenCalled();
    });
  });
});
