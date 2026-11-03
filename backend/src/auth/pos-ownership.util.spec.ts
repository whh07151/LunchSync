import { ForbiddenException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SupabaseService } from '../supabase/supabase.service';
import { PosAccessService } from './pos-ownership.util';

function queryResult(data: unknown, error: unknown = null) {
  const builder = {
    select: jest.fn(),
    eq: jest.fn(),
    neq: jest.fn(),
    limit: jest.fn(),
    maybeSingle: jest.fn(),
    update: jest.fn(),
    is: jest.fn(),
  };
  builder.select.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.neq.mockReturnValue(builder);
  builder.limit.mockReturnValue(builder);
  builder.update.mockReturnValue(builder);
  builder.is.mockReturnValue(builder);
  builder.maybeSingle.mockResolvedValue({ data, error });
  return builder;
}

describe('PosAccessService', () => {
  let from: jest.Mock;
  let service: PosAccessService;

  beforeEach(() => {
    from = jest.fn();
    service = new PosAccessService(
      { client: { from } } as unknown as SupabaseService,
      {
        get: jest.fn((key: string) =>
          key === 'NODE_ENV'
            ? 'development'
            : key === 'POS_SHARED_PIN_LOGIN_ENABLED'
              ? 'true'
              : undefined,
        ),
      } as unknown as ConfigService,
    );
  });

  it('allows an enabled nonproduction shared-PIN token only for its own restaurant', async () => {
    await expect(
      service.assertAccessTo(
        {
          type: 'POS',
          restaurantId: 'restaurant-a',
          authMode: 'SHARED_PIN',
        },
        'restaurant-a',
      ),
    ).resolves.toBeUndefined();
    expect(from).not.toHaveBeenCalled();
  });

  it('denies a POS token for another restaurant', async () => {
    await expect(
      service.assertAccessTo(
        {
          type: 'POS',
          restaurantId: 'restaurant-a',
          authMode: 'SHARED_PIN',
        },
        'restaurant-b',
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('revalidates an owner-backed POS token against current owner status and mapping', async () => {
    from
      .mockReturnValueOnce(
        queryResult({
          role: 'OWNER',
          status: 'APPROVED',
          restaurant_id: null,
        }),
      )
      .mockReturnValueOnce(
        queryResult({ id: 'restaurant-a', owner_user_id: 'owner-a' }),
      );

    await expect(
      service.assertAccessTo(
        {
          type: 'POS',
          restaurantId: 'restaurant-a',
          ownerUserId: 'owner-a',
          authMode: 'OWNER',
        },
        'restaurant-a',
      ),
    ).resolves.toBeUndefined();
  });

  it('denies a legacy POS token that cannot be revalidated', async () => {
    await expect(
      service.assertAccessTo(
        { type: 'POS', restaurantId: 'restaurant-a' },
        'restaurant-a',
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(from).not.toHaveBeenCalled();
  });

  it('denies an ordinary customer JWT', async () => {
    from.mockReturnValueOnce(
      queryResult({ role: 'CUSTOMER', status: 'APPROVED' }),
    );

    await expect(
      service.assertAccessTo(
        { type: 'USER', userId: 'customer' },
        'restaurant-a',
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('allows an approved owner only for a restaurant owned by that user', async () => {
    from
      .mockReturnValueOnce(
        queryResult({
          role: 'OWNER',
          status: 'APPROVED',
          restaurant_id: null,
        }),
      )
      .mockReturnValueOnce(
        queryResult({ id: 'restaurant-a', owner_user_id: 'owner-a' }),
      );

    await expect(
      service.assertAccessTo(
        { type: 'USER', userId: 'owner-a' },
        'restaurant-a',
      ),
    ).resolves.toBeUndefined();
  });

  it('denies an approved owner for a restaurant owned by someone else', async () => {
    from
      .mockReturnValueOnce(
        queryResult({
          role: 'OWNER',
          status: 'APPROVED',
          restaurant_id: 'restaurant-b',
        }),
      )
      .mockReturnValueOnce(
        queryResult({ id: 'restaurant-b', owner_user_id: 'owner-b' }),
      );

    await expect(
      service.assertAccessTo(
        { type: 'USER', userId: 'owner-a' },
        'restaurant-b',
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('allows a legacy user mapping only when the restaurant has no canonical owner', async () => {
    from
      .mockReturnValueOnce(
        queryResult({
          role: 'OWNER',
          status: 'APPROVED',
          restaurant_id: 'restaurant-a',
        }),
      )
      .mockReturnValueOnce(
        queryResult({ id: 'restaurant-a', owner_user_id: null }),
      )
      .mockReturnValueOnce(queryResult(null))
      .mockReturnValueOnce(queryResult(null))
      .mockReturnValueOnce(
        queryResult({ id: 'restaurant-a', owner_user_id: 'owner-a' }),
      );

    await expect(
      service.assertAccessTo(
        { type: 'USER', userId: 'owner-a' },
        'restaurant-a',
      ),
    ).resolves.toBeUndefined();
    const competingMappingQuery = from.mock.results[3].value;
    const claimQuery = from.mock.results[4].value;
    expect(competingMappingQuery.eq).toHaveBeenCalledWith(
      'restaurant_id',
      'restaurant-a',
    );
    expect(competingMappingQuery.neq).toHaveBeenCalledWith('id', 'owner-a');
    expect(competingMappingQuery.limit).toHaveBeenCalledWith(1);
    expect(claimQuery.update).toHaveBeenCalledWith({
      owner_user_id: 'owner-a',
    });
    expect(claimQuery.is).toHaveBeenCalledWith('owner_user_id', null);
  });

  it('does not combine a legacy mapping with a different canonical restaurant', async () => {
    from
      .mockReturnValueOnce(
        queryResult({
          role: 'OWNER',
          status: 'APPROVED',
          restaurant_id: 'restaurant-legacy',
        }),
      )
      .mockReturnValueOnce(
        queryResult({ id: 'restaurant-legacy', owner_user_id: null }),
      )
      .mockReturnValueOnce(queryResult({ id: 'restaurant-canonical' }));

    await expect(
      service.assertAccessTo(
        { type: 'USER', userId: 'owner-a' },
        'restaurant-legacy',
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('denies legacy access when another owner wins the canonical claim', async () => {
    from
      .mockReturnValueOnce(
        queryResult({
          role: 'OWNER',
          status: 'APPROVED',
          restaurant_id: 'restaurant-legacy',
        }),
      )
      .mockReturnValueOnce(
        queryResult({ id: 'restaurant-legacy', owner_user_id: null }),
      )
      .mockReturnValueOnce(queryResult(null))
      .mockReturnValueOnce(queryResult(null))
      .mockReturnValueOnce(queryResult(null));

    await expect(
      service.assertAccessTo(
        { type: 'USER', userId: 'owner-a' },
        'restaurant-legacy',
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('denies a legacy mapping shared by another account before claiming ownership', async () => {
    from
      .mockReturnValueOnce(
        queryResult({
          role: 'OWNER',
          status: 'APPROVED',
          restaurant_id: 'restaurant-legacy',
        }),
      )
      .mockReturnValueOnce(
        queryResult({ id: 'restaurant-legacy', owner_user_id: null }),
      )
      .mockReturnValueOnce(queryResult(null))
      .mockReturnValueOnce(queryResult({ id: 'owner-b' }));

    await expect(
      service.assertAccessTo(
        { type: 'USER', userId: 'owner-a' },
        'restaurant-legacy',
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(from).toHaveBeenCalledTimes(4);
  });

  it.each(['PENDING', 'REJECTED'])(
    'denies an owner whose approval status is %s',
    async (status) => {
      from.mockReturnValueOnce(
        queryResult({ role: 'OWNER', status, restaurant_id: 'restaurant-a' }),
      );

      await expect(
        service.assertAccessTo(
          { type: 'USER', userId: 'owner-a' },
          'restaurant-a',
        ),
      ).rejects.toBeInstanceOf(ForbiddenException);
      expect(from).toHaveBeenCalledTimes(1);
    },
  );

  it('fails closed when the owner lookup returns a database error', async () => {
    from.mockReturnValueOnce(queryResult(null, { message: 'database down' }));

    await expect(
      service.assertAccessTo(
        { type: 'USER', userId: 'owner-a' },
        'restaurant-a',
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(from).toHaveBeenCalledTimes(1);
  });
});
