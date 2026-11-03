import { InternalServerErrorException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { UsersService } from './users.service';

const USER_ID = '11111111-1111-4111-8111-111111111111';

function queryResult(data: unknown, error: unknown = null) {
  const builder = {
    select: jest.fn(),
    eq: jest.fn(),
    single: jest.fn(),
    maybeSingle: jest.fn(),
  };
  builder.select.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.single.mockResolvedValue({ data, error });
  builder.maybeSingle.mockResolvedValue({ data, error });
  return builder;
}

function user(overrides: Record<string, unknown> = {}) {
  return {
    id: USER_ID,
    name: '점주',
    role: 'OWNER',
    status: 'APPROVED',
    restaurant_id: null,
    ...overrides,
  };
}

describe('UsersService owner restaurant mapping', () => {
  it('returns the canonical restaurant ownership mapping to the Flutter client', async () => {
    const userQuery = queryResult(
      user({ restaurant_id: 'stale-legacy-restaurant' }),
    );
    const restaurantQuery = queryResult({ id: 'canonical-restaurant' });
    const from = jest
      .fn()
      .mockReturnValueOnce(userQuery)
      .mockReturnValueOnce(restaurantQuery);
    const service = new UsersService({
      client: { from },
    } as unknown as SupabaseService);

    await expect(service.getMe(USER_ID)).resolves.toMatchObject({
      id: USER_ID,
      restaurantId: 'canonical-restaurant',
    });
    expect(restaurantQuery.eq).toHaveBeenCalledWith('owner_user_id', USER_ID);
  });

  it('keeps the legacy mapping when no canonical owner mapping exists', async () => {
    const from = jest
      .fn()
      .mockReturnValueOnce(queryResult(user({ restaurant_id: 'legacy' })))
      .mockReturnValueOnce(queryResult(null));
    const service = new UsersService({
      client: { from },
    } as unknown as SupabaseService);

    await expect(service.getMe(USER_ID)).resolves.toMatchObject({
      restaurantId: 'legacy',
    });
  });

  it('does not return a potentially stale mapping after a canonical lookup error', async () => {
    const from = jest
      .fn()
      .mockReturnValueOnce(queryResult(user({ restaurant_id: 'legacy' })))
      .mockReturnValueOnce(queryResult(null, { message: 'database down' }));
    const service = new UsersService({
      client: { from },
    } as unknown as SupabaseService);

    await expect(service.getMe(USER_ID)).rejects.toBeInstanceOf(
      InternalServerErrorException,
    );
  });
});
