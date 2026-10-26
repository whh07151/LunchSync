import { OrdersService } from '../orders/orders.service';
import { RestaurantsController } from './restaurants.controller';
import { RestaurantsService } from './restaurants.service';

describe('RestaurantsController loyalty privacy boundary', () => {
  it('uses the authenticated user for loyalty lookup', async () => {
    const restaurants = {
      getLoyalty: jest.fn().mockResolvedValue({ visitCount: 0 }),
    };
    const controller = new RestaurantsController(
      restaurants as unknown as RestaurantsService,
      {} as OrdersService,
    );

    await controller.getLoyalty(
      { user: { type: 'USER', userId: 'authenticated-user' } },
      'restaurant-a',
    );

    expect(restaurants.getLoyalty).toHaveBeenCalledWith(
      'restaurant-a',
      'authenticated-user',
    );
  });
});
