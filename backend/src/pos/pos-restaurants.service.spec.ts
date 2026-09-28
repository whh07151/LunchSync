import { JwtService } from '@nestjs/jwt';
import { SupabaseService } from '../supabase/supabase.service';
import { PosRestaurantsService } from './pos-restaurants.service';

const OWNER_ID = '11111111-1111-4111-8111-111111111111';
const RESTAURANT_ID = '33333333-3333-4333-8333-333333333333';

function queryResult(data: unknown, error: unknown = null) {
  const builder = {
    select: jest.fn(),
    eq: jest.fn(),
    neq: jest.fn(),
    limit: jest.fn(),
    maybeSingle: jest.fn(),
    single: jest.fn(),
    insert: jest.fn(),
    update: jest.fn(),
    is: jest.fn(),
  };
  builder.select.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.neq.mockReturnValue(builder);
  builder.limit.mockReturnValue(builder);
  builder.insert.mockReturnValue(builder);
  builder.update.mockReturnValue(builder);
  builder.is.mockReturnValue(builder);
  builder.maybeSingle.mockResolvedValue({ data, error });
  builder.single.mockResolvedValue({ data, error });
  return builder;
}

const restaurant = {
  id: RESTAURANT_ID,
  name: '점주 식당',
  category: '한식',
  address: '서울',
  lat: 37.5,
  lng: 127,
  image_url: null,
};

describe('PosRestaurantsService token boundary', () => {
  it('issues a bounded owner-backed POS token after restaurant creation', async () => {
    const from = jest
      .fn()
      .mockReturnValueOnce(queryResult(null))
      .mockReturnValueOnce(queryResult({ restaurant_id: null }))
      .mockReturnValueOnce(queryResult(restaurant));
    const jwt = { sign: jest.fn().mockReturnValue('pos-token') };
    const service = new PosRestaurantsService(
      { client: { from } } as unknown as SupabaseService,
      jwt as unknown as JwtService,
    );

    await expect(
      service.create(OWNER_ID, {
        name: restaurant.name,
        category: restaurant.category,
        address: restaurant.address,
        lat: restaurant.lat,
        lng: restaurant.lng,
      }),
    ).resolves.toMatchObject({ posToken: 'pos-token' });
    expect(jwt.sign).toHaveBeenCalledWith(
      {
        sub: RESTAURANT_ID,
        type: 'POS',
        ownerUserId: OWNER_ID,
        authMode: 'OWNER',
      },
      { expiresIn: '8h' },
    );
  });

  it('uses the same revalidatable token shape when retrieving a restaurant', async () => {
    const jwt = { sign: jest.fn().mockReturnValue('pos-token') };
    const service = new PosRestaurantsService(
      {
        client: { from: jest.fn().mockReturnValue(queryResult(restaurant)) },
      } as unknown as SupabaseService,
      jwt as unknown as JwtService,
    );

    await expect(service.getMyRestaurant(OWNER_ID)).resolves.toMatchObject({
      posToken: 'pos-token',
    });
    expect(jwt.sign).toHaveBeenCalledWith(
      expect.objectContaining({
        sub: RESTAURANT_ID,
        ownerUserId: OWNER_ID,
        authMode: 'OWNER',
      }),
      { expiresIn: '8h' },
    );
  });

  it('rejects creating a second restaurant when only the legacy mapping exists', async () => {
    const canonicalQuery = queryResult(null);
    const ownerQuery = queryResult({ restaurant_id: RESTAURANT_ID });
    const legacyQuery = queryResult({
      ...restaurant,
      owner_user_id: null,
    });
    const claimQuery = queryResult({
      ...restaurant,
      owner_user_id: OWNER_ID,
    });
    const from = jest
      .fn()
      .mockReturnValueOnce(canonicalQuery)
      .mockReturnValueOnce(ownerQuery)
      .mockReturnValueOnce(legacyQuery)
      .mockReturnValueOnce(queryResult(null))
      .mockReturnValueOnce(claimQuery);
    const service = new PosRestaurantsService(
      { client: { from } } as unknown as SupabaseService,
      { sign: jest.fn() } as unknown as JwtService,
    );

    await expect(
      service.create(OWNER_ID, {
        name: '새 식당',
        category: '한식',
        address: '서울',
        lat: 37.5,
        lng: 127,
      }),
    ).rejects.toThrow('이미 등록된 식당이 있습니다.');
    expect(legacyQuery.eq).toHaveBeenCalledWith('id', RESTAURANT_ID);
    expect(claimQuery.update).toHaveBeenCalledWith({
      owner_user_id: OWNER_ID,
    });
    expect(claimQuery.is).toHaveBeenCalledWith('owner_user_id', null);
    expect(from).toHaveBeenCalledTimes(5);
  });

  it('canonicalizes a legacy mapping before issuing its POS token', async () => {
    const claimQuery = queryResult({
      ...restaurant,
      owner_user_id: OWNER_ID,
    });
    const from = jest
      .fn()
      .mockReturnValueOnce(queryResult(null))
      .mockReturnValueOnce(queryResult({ restaurant_id: RESTAURANT_ID }))
      .mockReturnValueOnce(queryResult({ ...restaurant, owner_user_id: null }))
      .mockReturnValueOnce(queryResult(null))
      .mockReturnValueOnce(claimQuery);
    const jwt = { sign: jest.fn().mockReturnValue('pos-token') };
    const service = new PosRestaurantsService(
      { client: { from } } as unknown as SupabaseService,
      jwt as unknown as JwtService,
    );

    await expect(service.getMyRestaurant(OWNER_ID)).resolves.toMatchObject({
      id: RESTAURANT_ID,
      posToken: 'pos-token',
    });
    expect(claimQuery.eq).toHaveBeenCalledWith('id', RESTAURANT_ID);
    expect(claimQuery.is).toHaveBeenCalledWith('owner_user_id', null);
    expect(jwt.sign).toHaveBeenCalledWith(
      expect.objectContaining({
        sub: RESTAURANT_ID,
        ownerUserId: OWNER_ID,
        authMode: 'OWNER',
      }),
      { expiresIn: '8h' },
    );
  });

  it('does not claim a legacy restaurant mapped to another account', async () => {
    const competingQuery = queryResult({ id: 'owner-b' });
    const from = jest
      .fn()
      .mockReturnValueOnce(queryResult(null))
      .mockReturnValueOnce(queryResult({ restaurant_id: RESTAURANT_ID }))
      .mockReturnValueOnce(queryResult({ ...restaurant, owner_user_id: null }))
      .mockReturnValueOnce(competingQuery);
    const jwt = { sign: jest.fn() };
    const service = new PosRestaurantsService(
      { client: { from } } as unknown as SupabaseService,
      jwt as unknown as JwtService,
    );

    await expect(service.getMyRestaurant(OWNER_ID)).rejects.toMatchObject({
      status: 409,
    });
    expect(competingQuery.eq).toHaveBeenCalledWith(
      'restaurant_id',
      RESTAURANT_ID,
    );
    expect(competingQuery.neq).toHaveBeenCalledWith('id', OWNER_ID);
    expect(from).toHaveBeenCalledTimes(4);
    expect(jwt.sign).not.toHaveBeenCalled();
  });
});
