import {
  Logger,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { SupabaseService } from '../supabase/supabase.service';
import { FirebaseService } from './firebase.service';
import { AuthService } from './auth.service';

const APP_ID = 1534395;
const ID = '11111111-1111-4111-8111-111111111111';
const tokenInfo = { app_id: APP_ID, id: 123456, expires_in: 3600 };
const profile = {
  id: 123456,
  kakao_account: { profile: { nickname: '가상 사용자' } },
};
const row = {
  id: ID,
  name: '가상 사용자',
  profile_image: null,
  role: 'CUSTOMER',
  status: 'APPROVED',
  org: null,
  budget: null,
  speed: null,
};

function query(result: unknown) {
  const builder = {
    select: jest.fn(),
    eq: jest.fn(),
    insert: jest.fn(),
    maybeSingle: jest.fn(),
    single: jest.fn(),
  };
  builder.select.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.insert.mockReturnValue(builder);
  builder.maybeSingle.mockResolvedValue(result);
  builder.single.mockResolvedValue(result);
  return builder;
}

describe('Kakao authentication boundary with synthetic identities', () => {
  let fetchMock: jest.SpiedFunction<typeof fetch>;
  let jwt: { sign: jest.Mock };
  let logger: jest.SpyInstance;
  const config = new ConfigService({
    KAKAO_APP_ID: String(APP_ID),
    KAKAO_API_TIMEOUT_MS: '5000',
  });

  const service = (from: jest.Mock, suppliedConfig = config) =>
    new AuthService(
      { client: { from } } as unknown as SupabaseService,
      jwt as unknown as JwtService,
      {} as FirebaseService,
      suppliedConfig,
    );
  const response = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), { status });

  beforeEach(() => {
    jwt = { sign: jest.fn().mockReturnValue('synthetic-jwt') };
    logger = jest.spyOn(Logger.prototype, 'error').mockImplementation();
    fetchMock = jest
      .spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(response(tokenInfo))
      .mockResolvedValueOnce(response(profile));
  });
  afterEach(() => {
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('creates a new customer only after app and user identity validation', async () => {
    const insert = query({ data: row, error: null });
    const from = jest
      .fn()
      .mockReturnValueOnce(query({ data: null, error: null }))
      .mockReturnValueOnce(insert);
    const result = await service(from).kakaoLogin('synthetic-token');
    expect(result).toMatchObject({
      isNewUser: true,
      nextStep: 'PROFILE_SETUP',
      user: { id: ID, role: 'CUSTOMER' },
    });
    expect(insert.insert).toHaveBeenCalledWith(
      expect.objectContaining({ kakao_id: '123456', auth_provider: 'KAKAO' }),
    );
    expect(jwt.sign).toHaveBeenCalledWith({ sub: ID });
    expect(fetchMock).toHaveBeenNthCalledWith(
      1,
      'https://kapi.kakao.com/v1/user/access_token_info',
      expect.objectContaining({ signal: expect.any(AbortSignal) }),
    );
  });

  it.each([
    [{ org: '가상팀', budget: 12000, speed: 'NORMAL' }, 'HOME'],
    [{ org: '가상팀' }, 'CONDITION_SETUP'],
    [{ role: 'OWNER', status: 'PENDING' }, 'OWNER_PENDING'],
    [{ role: 'OWNER', status: 'APPROVED' }, 'OWNER_HOME'],
  ])(
    'preserves existing onboarding/role state %p',
    async (override, nextStep) => {
      const from = jest
        .fn()
        .mockReturnValue(
          query({
            data: { ...row, ...override, profile_image: 'saved-profile' },
            error: null,
          }),
        );
      const result = await service(from).kakaoLogin('synthetic-token');
      expect(result).toMatchObject({
        isNewUser: false,
        nextStep,
        user: { profileImage: 'saved-profile' },
      });
      expect(from).toHaveBeenCalledTimes(1);
    },
  );

  it('stops on a failed database lookup without inserting or issuing a JWT', async () => {
    const from = jest
      .fn()
      .mockReturnValue(
        query({ data: null, error: { message: 'private account details' } }),
      );
    await expect(
      service(from).kakaoLogin('synthetic-token'),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(from).toHaveBeenCalledTimes(1);
    expect(jwt.sign).not.toHaveBeenCalled();
    expect(JSON.stringify(logger.mock.calls)).not.toContain(
      'private account details',
    );
  });

  it('recovers only the same Kakao identity after a concurrent unique violation', async () => {
    const from = jest
      .fn()
      .mockReturnValueOnce(query({ data: null, error: null }))
      .mockReturnValueOnce(query({ data: null, error: { code: '23505' } }))
      .mockReturnValueOnce(
        query({
          data: { ...row, org: '가상팀', budget: 12000, speed: 'NORMAL' },
          error: null,
        }),
      );
    const result = await service(from).kakaoLogin('synthetic-token');
    expect(result).toMatchObject({
      isNewUser: false,
      nextStep: 'HOME',
      user: { id: ID },
    });
    expect(from).toHaveBeenCalledTimes(3);
  });

  it.each([
    [{ code: 'XX000' }, null],
    [{ code: '23505' }, { data: null, error: null }],
    [{ code: '23505' }, { data: null, error: { code: '08006' } }],
  ])(
    'does not issue a JWT when persistence/race recovery fails %p',
    async (error, recovery) => {
      const from = jest
        .fn()
        .mockReturnValueOnce(query({ data: null, error: null }))
        .mockReturnValueOnce(query({ data: null, error }));
      if (recovery) from.mockReturnValueOnce(query(recovery));
      await expect(
        service(from).kakaoLogin('synthetic-token'),
      ).rejects.toBeInstanceOf(ServiceUnavailableException);
      expect(jwt.sign).not.toHaveBeenCalled();
    },
  );

  it.each([
    { ...tokenInfo, app_id: 999999 },
    { ...tokenInfo, expires_in: 0 },
    { ...tokenInfo, id: undefined },
    { ...tokenInfo, id: -1 },
  ])(
    'rejects another app, expired or malformed identity before database access %p',
    async (info) => {
      fetchMock.mockReset().mockResolvedValueOnce(response(info));
      const from = jest.fn();
      await expect(
        service(from).kakaoLogin('synthetic-token'),
      ).rejects.toBeInstanceOf(UnauthorizedException);
      expect(from).not.toHaveBeenCalled();
      expect(jwt.sign).not.toHaveBeenCalled();
    },
  );

  it('rejects mismatched provider user IDs', async () => {
    fetchMock
      .mockReset()
      .mockResolvedValueOnce(response(tokenInfo))
      .mockResolvedValueOnce(response({ id: 999 }));
    const from = jest.fn();
    await expect(
      service(from).kakaoLogin('synthetic-token'),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(from).not.toHaveBeenCalled();
  });

  it.each([401, 403, 429, 500])(
    'distinguishes provider HTTP %i without issuing a JWT',
    async (status) => {
      fetchMock.mockReset().mockResolvedValueOnce(response({}, status));
      const from = jest.fn();
      await expect(
        service(from).kakaoLogin('synthetic-token'),
      ).rejects.toBeInstanceOf(
        status === 401 || status === 403
          ? UnauthorizedException
          : ServiceUnavailableException,
      );
      expect(from).not.toHaveBeenCalled();
    },
  );

  it('fails safely on a provider network error or malformed response', async () => {
    const from = jest.fn();
    fetchMock.mockReset().mockRejectedValueOnce(new Error('private token URL'));
    await expect(
      service(from).kakaoLogin('synthetic-token'),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
    fetchMock.mockResolvedValueOnce(response(null));
    await expect(
      service(from).kakaoLogin('synthetic-token'),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(from).not.toHaveBeenCalled();
  });

  it('aborts the provider request before the ten-second Flutter deadline', async () => {
    jest.useFakeTimers();
    fetchMock.mockReset().mockImplementation(
      (_url, options) =>
        new Promise((_resolve, reject) => {
          options?.signal?.addEventListener(
            'abort',
            () => reject(new Error('aborted')),
            { once: true },
          );
        }),
    );
    const from = jest.fn();
    const assertion = expect(
      service(from).kakaoLogin('synthetic-token'),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
    await jest.advanceTimersByTimeAsync(5001);
    await assertion;
    expect(from).not.toHaveBeenCalled();
  });

  it('fails closed when the expected Kakao app is not configured', async () => {
    const empty = {
      get: jest.fn().mockReturnValue(undefined),
    } as unknown as ConfigService;
    await expect(
      service(jest.fn(), empty).kakaoLogin('synthetic-token'),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
