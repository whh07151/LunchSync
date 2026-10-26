import { MenusController } from './menus.controller';
import { MenusService } from './menus.service';

describe('MenusController privacy boundary', () => {
  it('uses the authenticated user for allergen checks', async () => {
    const service = {
      checkAllergens: jest.fn().mockResolvedValue({ conflicts: [] }),
    };
    const controller = new MenusController(service as unknown as MenusService);

    await controller.checkAllergens(
      { user: { type: 'USER', userId: 'authenticated-user' } },
      'restaurant-a',
    );

    expect(service.checkAllergens).toHaveBeenCalledWith(
      'restaurant-a',
      'authenticated-user',
    );
  });
});
