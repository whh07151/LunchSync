import { ForbiddenException } from '@nestjs/common';
import type { AuthedRequestUser } from '../auth/jwt.strategy';
import { PosAccessService } from '../auth/pos-ownership.util';
import { PosController } from './pos.controller';
import { PosService } from './pos.service';

describe('PosController access ordering', () => {
  it('does not start cancellation when asynchronous restaurant access is denied', async () => {
    const posService = {
      getRestaurantIdByOrderId: jest.fn().mockResolvedValue('restaurant-a'),
      cancelOrder: jest.fn(),
    };
    const posAccess = {
      assertAccessTo: jest
        .fn()
        .mockRejectedValue(new ForbiddenException('denied')),
    };
    const controller = new PosController(
      posService as unknown as PosService,
      posAccess as unknown as PosAccessService,
    );
    const user: AuthedRequestUser = { type: 'USER', userId: 'customer' };

    await expect(
      controller.cancelOrder({ user }, '22222222-2222-4222-8222-222222222222', {
        reason: 'test',
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(posAccess.assertAccessTo).toHaveBeenCalledWith(user, 'restaurant-a');
    expect(posService.cancelOrder).not.toHaveBeenCalled();
  });
});
