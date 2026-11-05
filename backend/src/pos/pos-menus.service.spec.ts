import { SupabaseService } from '../supabase/supabase.service';
import { PosMenusService } from './pos-menus.service';

describe('PosMenusService', () => {
  const restaurantId = '11111111-1111-4111-8111-111111111111';
  const menuId = '22222222-2222-4222-8222-222222222222';

  function createServiceWithMock(handlers: {
    rows?: any[];
    inserted?: any;
    updated?: any;
  }) {
    let lastInsertPayload: Record<string, unknown> | null = null;
    let lastUpdatePayload: Record<string, unknown> | null = null;

    const supabase = {
      client: {
        from: (table: string) => {
          expect(table).toBe('menu_items');
          return {
            select: () => {
              const chain: any = {
                eq: () => chain,
                order: () => chain,
                then: (resolve: any) =>
                  resolve({ data: handlers.rows ?? [], error: null }),
              };
              return chain;
            },
            insert: (payload: Record<string, unknown>) => {
              lastInsertPayload = payload;
              return {
                select: () => ({
                  single: async () => ({
                    data:
                      handlers.inserted ?? {
                        id: menuId,
                        restaurant_id: restaurantId,
                        ...payload,
                      },
                    error: null,
                  }),
                }),
              };
            },
            update: (payload: Record<string, unknown>) => {
              lastUpdatePayload = payload;
              return {
                eq: () => ({
                  select: () => ({
                    single: async () => ({
                      data:
                        handlers.updated ?? {
                          id: menuId,
                          restaurant_id: restaurantId,
                          name: '김치찌개',
                          price: 9000,
                          ...payload,
                        },
                      error: null,
                    }),
                  }),
                }),
              };
            },
          };
        },
      },
    } as unknown as SupabaseService;

    return {
      service: new PosMenusService(supabase),
      getLastInsertPayload: () => lastInsertPayload,
      getLastUpdatePayload: () => lastUpdatePayload,
    };
  }

  it('normalizes ingredients and allergens on create and maps them in response', async () => {
    const { service, getLastInsertPayload } = createServiceWithMock({});

    const created = await service.create(restaurantId, {
      name: '한돈 김치찌개',
      price: 9500,
      category: '찌개',
      prepTimeMinutes: 12,
      ingredients: [' 돼지고기 ', '김치', '두부', '돼지고기', ''],
      allergens: [' 돼지고기 ', '대두', '대두'],
    });

    expect(getLastInsertPayload()).toMatchObject({
      restaurant_id: restaurantId,
      name: '한돈 김치찌개',
      price: 9500,
      category: '찌개',
      prep_time_minutes: 12,
      ingredients: ['돼지고기', '김치', '두부'],
      allergens: ['돼지고기', '대두'],
    });
    expect(created).toMatchObject({
      id: menuId,
      restaurantId,
      name: '한돈 김치찌개',
      price: 9500,
      prepTimeMinutes: 12,
      ingredients: ['돼지고기', '김치', '두부'],
      allergens: ['돼지고기', '대두'],
    });
  });

  it('updates availability, prepTimeMinutes, and ingredients together', async () => {
    const { service, getLastUpdatePayload } = createServiceWithMock({});

    const updated = await service.update(menuId, {
      isAvailable: false,
      prepTimeMinutes: 20,
      ingredients: ['두부', ' 애호박 '],
    });

    expect(getLastUpdatePayload()).toEqual({
      is_available: false,
      prep_time_minutes: 20,
      ingredients: ['두부', '애호박'],
    });
    expect(updated.isAvailable).toBe(false);
    expect(updated.prepTimeMinutes).toBe(20);
    expect(updated.ingredients).toEqual(['두부', '애호박']);
  });
});
