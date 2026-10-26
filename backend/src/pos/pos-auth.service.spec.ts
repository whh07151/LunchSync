import {
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { SupabaseService } from '../supabase/supabase.service';
import { PosAuthService } from './pos-auth.service';

const USER_ID = '11111111-1111-4111-8111-111111111111';
const RESTAURANT_ID = '33333333-3333-4333-8333-333333333333';

function queryResult(data: unknown, error: unknown = null) {
  const builder = {
    select: jest.fn(),
    eq: jest.fn(),
    ilike: jest.fn(),
    neq: jest.fn(),
    limit: jest.fn(),
    single: jest.fn(),
    maybeSingle: jest.fn(),
    update: jest.fn(),
    is: jest.fn(),
  };
  builder.select.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.ilike.mockReturnValue(builder);
  builder.neq.mockReturnValue(builder);
  builder.limit.mockReturnValue(builder);
  builder.update.mockReturnValue(builder);
  builder.is.mockReturnValue(builder);
  builder.single.mockResolvedValue({ data, error });
  builder.maybeSingle.mockResolvedValue({ data, error });
  return builder;
}

function config(values: Record<string, string | undefined>) {
  return {
    get: jest.fn((key: string) => values[key]),
  } as unknown as ConfigService;
}

describe('PosAuthService tenant and email verification boundaries', () => {
  it('disables the shared PIN login in production even when configured', async () => {
    const from = jest.fn();
    const jwt = { sign: jest.fn() };
    const service = new PosAuthService(
      { client: { from } } as unknown as SupabaseService,
      jwt as unknown as JwtService,
      config({
        NODE_ENV: 'production',
        POS_SHARED_PIN_LOGIN_ENABLED: 'true',
        POS_PIN: '1234',
      }),
    );

    await expect(
      service.login(RESTAURANT_ID, 'counter', '1234'),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'POS_SHARED_LOGIN_DISABLED' }),
    });
    expect(from).not.toHaveBeenCalled();
    expect(jwt.sign).not.toHaveBeenCalled();
  });

  it('requires explicit nonproduction enablement before checking a shared PIN', async () => {
    const service = new PosAuthService(
      { client: { from: jest.fn() } } as unknown as SupabaseService,
      { sign: jest.fn() } as unknown as JwtService,
      config({ NODE_ENV: 'development', POS_PIN: '1234' }),
    );

    await expect(
      service.login(RESTAURANT_ID, 'counter', '1234'),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('allows an explicitly enabled nonproduction demo PIN for the requested store', async () => {
    const restaurantQuery = queryResult({
      id: RESTAURANT_ID,
      name: '테스트 식당',
    });
    const jwt = { sign: jest.fn().mockReturnValue('pos-token') };
    const service = new PosAuthService(
      {
        client: { from: jest.fn().mockReturnValue(restaurantQuery) },
      } as unknown as SupabaseService,
      jwt as unknown as JwtService,
      config({
        NODE_ENV: 'development',
        POS_SHARED_PIN_LOGIN_ENABLED: 'true',
        POS_PIN: '1234',
      }),
    );

    await expect(
      service.login(RESTAURANT_ID, 'counter', '1234'),
    ).resolves.toMatchObject({
      accessToken: 'pos-token',
      restaurantId: RESTAURANT_ID,
    });
    expect(jwt.sign).toHaveBeenCalledWith(
      {
        sub: RESTAURANT_ID,
        type: 'POS',
        authMode: 'SHARED_PIN',
      },
      { expiresIn: '2h' },
    );
  });

  it('does not issue owner or POS tokens to an unverified email account', async () => {
    const passwordHash = await bcrypt.hash('password123', 4);
    const userQuery = queryResult({
      id: USER_ID,
      name: '점주',
      password_hash: passwordHash,
      role: 'OWNER',
      status: 'APPROVED',
      email_verified_at: null,
    });
    const from = jest.fn().mockReturnValue(userQuery);
    const jwt = { sign: jest.fn() };
    const service = new PosAuthService(
      { client: { from } } as unknown as SupabaseService,
      jwt as unknown as JwtService,
      config({}),
    );

    await expect(
      service.loginOwner('OWNER@EXAMPLE.COM', 'password123'),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: 'EMAIL_VERIFICATION_REQUIRED',
      }),
    });
    expect(userQuery.ilike).toHaveBeenCalledWith('email', 'OWNER@EXAMPLE.COM');
    expect(jwt.sign).not.toHaveBeenCalled();
    expect(from).toHaveBeenCalledTimes(1);
  });

  it('issues store-scoped tokens to a verified approved owner', async () => {
    const passwordHash = await bcrypt.hash('password123', 4);
    const userQuery = queryResult({
      id: USER_ID,
      name: '점주',
      password_hash: passwordHash,
      role: 'OWNER',
      status: 'APPROVED',
      email_verified_at: '2026-08-05T16:00:00+09:00',
    });
    const restaurantQuery = queryResult({
      id: RESTAURANT_ID,
      name: '점주 식당',
    });
    const from = jest
      .fn()
      .mockReturnValueOnce(userQuery)
      .mockReturnValueOnce(restaurantQuery);
    const jwt = {
      sign: jest
        .fn()
        .mockReturnValueOnce('user-token')
        .mockReturnValueOnce('pos-token'),
    };
    const service = new PosAuthService(
      { client: { from } } as unknown as SupabaseService,
      jwt as unknown as JwtService,
      config({}),
    );

    await expect(
      service.loginOwner('owner@example.com', 'password123'),
    ).resolves.toEqual({
      userToken: 'user-token',
      restaurant: {
        posToken: 'pos-token',
        restaurantId: RESTAURANT_ID,
        restaurantName: '점주 식당',
      },
    });
    expect(jwt.sign).toHaveBeenNthCalledWith(1, {
      sub: USER_ID,
      type: 'USER',
    });
    expect(jwt.sign).toHaveBeenNthCalledWith(
      2,
      {
        sub: RESTAURANT_ID,
        type: 'POS',
        ownerUserId: USER_ID,
        authMode: 'OWNER',
      },
      { expiresIn: '8h' },
    );
  });

  it('resolves a verified owner through the legacy users.restaurant_id mapping', async () => {
    const passwordHash = await bcrypt.hash('password123', 4);
    const userQuery = queryResult({
      id: USER_ID,
      name: '점주',
      password_hash: passwordHash,
      role: 'OWNER',
      status: 'APPROVED',
      email_verified_at: '2026-08-05T16:00:00+09:00',
      restaurant_id: RESTAURANT_ID,
    });
    const canonicalQuery = queryResult(null);
    const legacyQuery = queryResult({
      id: RESTAURANT_ID,
      name: '레거시 식당',
      owner_user_id: null,
    });
    const claimQuery = queryResult({
      id: RESTAURANT_ID,
      name: '레거시 식당',
      owner_user_id: USER_ID,
    });
    const from = jest
      .fn()
      .mockReturnValueOnce(userQuery)
      .mockReturnValueOnce(canonicalQuery)
      .mockReturnValueOnce(legacyQuery)
      .mockReturnValueOnce(queryResult(null))
      .mockReturnValueOnce(claimQuery);
    const jwt = { sign: jest.fn().mockReturnValue('token') };
    const service = new PosAuthService(
      { client: { from } } as unknown as SupabaseService,
      jwt as unknown as JwtService,
      config({}),
    );

    await expect(
      service.loginOwner('owner@example.com', 'password123'),
    ).resolves.toMatchObject({
      restaurant: {
        restaurantId: RESTAURANT_ID,
        restaurantName: '레거시 식당',
      },
    });
    expect(legacyQuery.eq).toHaveBeenCalledWith('id', RESTAURANT_ID);
    expect(claimQuery.update).toHaveBeenCalledWith({ owner_user_id: USER_ID });
    expect(claimQuery.is).toHaveBeenCalledWith('owner_user_id', null);
  });

  it('returns no restaurant when a stale legacy mapping points to a missing row', async () => {
    const passwordHash = await bcrypt.hash('password123', 4);
    const from = jest
      .fn()
      .mockReturnValueOnce(
        queryResult({
          id: USER_ID,
          name: '점주',
          password_hash: passwordHash,
          role: 'OWNER',
          status: 'APPROVED',
          email_verified_at: '2026-08-05T16:00:00+09:00',
          restaurant_id: RESTAURANT_ID,
        }),
      )
      .mockReturnValueOnce(queryResult(null))
      .mockReturnValueOnce(queryResult(null));
    const jwt = { sign: jest.fn().mockReturnValue('user-token') };
    const service = new PosAuthService(
      { client: { from } } as unknown as SupabaseService,
      jwt as unknown as JwtService,
      config({}),
    );

    await expect(
      service.loginOwner('owner@example.com', 'password123'),
    ).resolves.toEqual({ userToken: 'user-token', restaurant: null });
    expect(jwt.sign).toHaveBeenCalledTimes(1);
  });

  it('does not issue a POS token for an ambiguous legacy restaurant mapping', async () => {
    const passwordHash = await bcrypt.hash('password123', 4);
    const from = jest
      .fn()
      .mockReturnValueOnce(
        queryResult({
          id: USER_ID,
          name: '점주',
          password_hash: passwordHash,
          role: 'OWNER',
          status: 'APPROVED',
          email_verified_at: '2026-08-05T16:00:00+09:00',
          restaurant_id: RESTAURANT_ID,
        }),
      )
      .mockReturnValueOnce(queryResult(null))
      .mockReturnValueOnce(
        queryResult({
          id: RESTAURANT_ID,
          name: '기존 식당',
          owner_user_id: null,
        }),
      )
      .mockReturnValueOnce(queryResult({ id: 'owner-b' }));
    const jwt = { sign: jest.fn().mockReturnValue('user-token') };
    const service = new PosAuthService(
      { client: { from } } as unknown as SupabaseService,
      jwt as unknown as JwtService,
      config({}),
    );

    await expect(
      service.loginOwner('OWNER@EXAMPLE.COM', 'password123'),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: 'POS_LEGACY_OWNERSHIP_AMBIGUOUS',
      }),
    });
    expect(jwt.sign).toHaveBeenCalledTimes(1);
  });

  it('reports owner lookup outages as retryable instead of invalid credentials', async () => {
    const service = new PosAuthService(
      {
        client: {
          from: jest
            .fn()
            .mockReturnValue(queryResult(null, { message: 'database down' })),
        },
      } as unknown as SupabaseService,
      { sign: jest.fn() } as unknown as JwtService,
      config({}),
    );

    await expect(
      service.loginOwner('owner@example.com', 'password123'),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: 'POS_OWNER_LOOKUP_FAILED',
        retryable: true,
      }),
    });
  });
});
