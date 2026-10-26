import { SupabaseService } from '../supabase/supabase.service';
import { RestaurantsService } from './restaurants.service';

type Row = {
  id: string;
  name: string;
  lat: number;
  lng: number;
  created_at: string;
  image_url: string | null;
  price_range: number;
};

class FakeRestaurantQuery {
  private filtered: Row[];

  constructor(rows: Row[]) {
    this.filtered = [...rows];
  }

  select() { return this; }
  gte(key: keyof Row, value: number) {
    this.filtered = this.filtered.filter((row) => Number(row[key]) >= value);
    return this;
  }
  lte(key: keyof Row, value: number) {
    this.filtered = this.filtered.filter((row) => Number(row[key]) <= value);
    return this;
  }
  order(key: keyof Row) {
    this.filtered.sort((a, b) => String(a[key]).localeCompare(String(b[key])));
    return this;
  }
  async range(start: number, end: number) {
    return { data: this.filtered.slice(start, end + 1), error: null };
  }
}

describe('RestaurantsService nearby listing', () => {
  const center = { lat: 37.5665, lng: 126.978 };

  it('sorts 1202 synthetic candidates by actual distance before applying limit', async () => {
    const rows: Row[] = Array.from({ length: 1200 }, (_, i) => ({
      id: `far-${String(i).padStart(4, '0')}`,
      name: `가상 식당 ${i}`,
      lat: center.lat + 0.006,
      lng: center.lng,
      created_at: '2026-09-28T00:00:00Z',
      image_url: null,
      price_range: 9,
    }));
    rows.push({
      id: 'nearest', name: '가상 가까운 식당', lat: center.lat + 0.0001,
      lng: center.lng, created_at: '2026-01-01T00:00:00Z',
      image_url: 'https://source.unsplash.com/400x300/?food', price_range: 8,
    });
    rows.push({
      id: 'outside', name: '가상 반경 밖 식당', lat: center.lat + 0.03,
      lng: center.lng, created_at: '2026-09-28T00:00:00Z',
      image_url: null, price_range: 8,
    });
    const from = jest.fn(() => new FakeRestaurantQuery(rows));
    const service = new RestaurantsService({ client: { from } } as unknown as SupabaseService);

    const result = await service.getRestaurants({ ...center, radius: 1000, limit: 3 });

    expect(result).toHaveLength(3);
    expect(result[0]).toMatchObject({ id: 'nearest', imageUrl: null });
    expect(result.some((row) => row.id === 'outside')).toBe(false);
    expect(from).toHaveBeenCalledTimes(2); // 1000행 기본 제한을 넘겨도 조회
  });

  it('rejects incomplete or invalid location rather than showing unrelated listings', async () => {
    const service = new RestaurantsService({} as SupabaseService);
    await expect(service.getRestaurants({ lat: center.lat })).rejects.toThrow();
    await expect(service.getRestaurants({ ...center, radius: -1 })).rejects.toThrow();
    await expect(service.getRestaurants({ ...center, limit: 0 })).rejects.toThrow();
    await expect(service.getRestaurants({ ...center, offset: 1001 })).rejects.toThrow();
  });

  it('stops a dense-area lookup before unbounded database reads', async () => {
    const rows: Row[] = Array.from({ length: 5001 }, (_, i) => ({
      id: `dense-${i}`, name: `가상 식당 ${i}`, lat: center.lat,
      lng: center.lng, created_at: '2026-09-28T00:00:00Z',
      image_url: null, price_range: 8,
    }));
    const from = jest.fn(() => new FakeRestaurantQuery(rows));
    const service = new RestaurantsService({ client: { from } } as unknown as SupabaseService);
    await expect(service.getRestaurants({ ...center, radius: 1000, limit: 10 }))
      .rejects.toThrow(/범위를 좁혀야/);
    expect(from).toHaveBeenCalledTimes(6);
  });
});

describe('RestaurantsService menu catalog', () => {
  it('handles 600 synthetic menu states without showing sold-out items or search images as photos', async () => {
    const menuRows = Array.from({ length: 600 }, (_, index) => ({
      id: `menu-${index}`,
      restaurant_id: 'synthetic-restaurant',
      name: `가상 메뉴 ${index}`,
      price: 5000 + index,
      category: '밥류',
      description: '',
      image_url: index === 0 ? 'https://example.com/merchant-photo.jpg' : 'https://source.unsplash.com/400x300/?food',
      source: index % 2 === 0 ? 'MANUAL' : 'AI_GEMINI',
      is_available: index < 300,
    }));
    const query = {
      rows: menuRows,
      select() { return this; },
      eq(key: string, value: unknown) {
        this.rows = this.rows.filter((row) => (row as Record<string, unknown>)[key] === value);
        return this;
      },
      order() {
        return this;
      },
      then(resolve: (value: { data: typeof menuRows; error: null }) => unknown) {
        return Promise.resolve({ data: this.rows, error: null }).then(resolve);
      },
    };
    const service = new RestaurantsService({
      client: { from: () => query },
    } as unknown as SupabaseService);

    const result = await service.getMenusByRestaurant('synthetic-restaurant');

    expect(result.menus).toHaveLength(300);
    expect(result.menus[0]).toMatchObject({
      source: 'MANUAL', imageUrl: 'https://example.com/merchant-photo.jpg',
    });
    expect(result.menus[1]).toMatchObject({ source: 'AI_GEMINI', imageUrl: null });
    expect(result.menus[2].imageUrl).toBeNull();
    expect(result.menus[0].priceVerifiedAt).toBeNull();
  });
});
