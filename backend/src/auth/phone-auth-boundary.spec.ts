import {
  Logger,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { SupabaseService } from '../supabase/supabase.service';
import { AuthService } from './auth.service';
import { FirebaseService } from './firebase.service';

const USER_ID = '11111111-1111-4111-8111-111111111111';
const PHONE_NUMBER = '+821012345678';

function queryResult(data: unknown, error: unknown = null) {
  const builder = {
    select: jest.fn(),
    eq: jest.fn(),
    neq: jest.fn(),
    update: jest.fn(),
    insert: jest.fn(),
    maybeSingle: jest.fn(),
    single: jest.fn(),
  };
  builder.select.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.neq.mockReturnValue(builder);
  builder.update.mockReturnValue(builder);
  builder.insert.mockReturnValue(builder);
  builder.maybeSingle.mockResolvedValue({ data, error });
  builder.single.mockResolvedValue({ data, error });
  return builder;
}

describe('phone account attachment boundary', () => {
  it.each(['attachment', 'login'] as const)(
    'stops %s when phone lookup fails before mutation or JWT',
    async (mode) => {
      const lookup = queryResult(null, {
        message: 'synthetic database outage',
      });
      const from = jest.fn().mockReturnValue(lookup);
      const jwt = { sign: jest.fn() };
      const firebase = {
        verifyIdToken: jest
          .fn()
          .mockResolvedValue({ uid: 'qa-firebase', phoneNumber: PHONE_NUMBER }),
      };
      const service = new AuthService(
        { client: { from } } as unknown as SupabaseService,
        jwt as unknown as JwtService,
        firebase as unknown as FirebaseService,
      );
      const action =
        mode === 'attachment'
          ? service.attachVerifiedPhone('qa-token', USER_ID)
          : service.phoneVerify('qa-token');
      await expect(action).rejects.toBeInstanceOf(ServiceUnavailableException);
      expect(from).toHaveBeenCalledTimes(1);
      expect(lookup.insert).not.toHaveBeenCalled();
      expect(lookup.update).not.toHaveBeenCalled();
      expect(jwt.sign).not.toHaveBeenCalled();
    },
  );

  it('updates and signs only the user ID from the authenticated principal', async () => {
    const collisionQuery = queryResult(null);
    const updateQuery = queryResult({
      id: USER_ID,
      name: '사용자',
      profile_image: null,
      role: 'CUSTOMER',
      status: 'APPROVED',
      org: null,
      budget: null,
      speed: null,
    });
    const from = jest
      .fn()
      .mockReturnValueOnce(collisionQuery)
      .mockReturnValueOnce(updateQuery);
    const jwt = { sign: jest.fn().mockReturnValue('full-access-token') };
    const firebase = {
      verifyIdToken: jest.fn().mockResolvedValue({
        uid: 'firebase-user',
        phoneNumber: PHONE_NUMBER,
      }),
    };
    const service = new AuthService(
      { client: { from } } as unknown as SupabaseService,
      jwt as unknown as JwtService,
      firebase as unknown as FirebaseService,
    );

    await expect(
      service.attachVerifiedPhone('firebase-token', USER_ID),
    ).resolves.toMatchObject({
      accessToken: 'full-access-token',
      user: { id: USER_ID },
    });
    expect(updateQuery.eq).toHaveBeenCalledWith('id', USER_ID);
    expect(jwt.sign).toHaveBeenCalledWith({ sub: USER_ID });
  });

  it('rejects a missing principal before Firebase, database, or JWT side effects', async () => {
    const from = jest.fn();
    const jwt = { sign: jest.fn() };
    const firebase = { verifyIdToken: jest.fn() };
    const service = new AuthService(
      { client: { from } } as unknown as SupabaseService,
      jwt as unknown as JwtService,
      firebase as unknown as FirebaseService,
    );

    await expect(
      service.attachVerifiedPhone('firebase-token', undefined),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(firebase.verifyIdToken).not.toHaveBeenCalled();
    expect(from).not.toHaveBeenCalled();
    expect(jwt.sign).not.toHaveBeenCalled();
  });

  it('never logs the verified phone number or provider error after signup persistence fails', async () => {
    const providerMessage = `duplicate value ${PHONE_NUMBER}`;
    const logger = jest.spyOn(Logger.prototype, 'error').mockImplementation();
    const from = jest
      .fn()
      .mockReturnValueOnce(queryResult(null))
      .mockReturnValueOnce(queryResult(null, { message: providerMessage }));
    const service = new AuthService(
      { client: { from } } as unknown as SupabaseService,
      { sign: jest.fn() } as unknown as JwtService,
      {
        verifyIdToken: jest.fn().mockResolvedValue({
          uid: 'firebase-user',
          phoneNumber: PHONE_NUMBER,
        }),
      } as unknown as FirebaseService,
    );

    await expect(service.phoneVerify('firebase-token')).rejects.toThrow(
      '휴대폰 회원가입에 실패했어요.',
    );

    expect(logger).toHaveBeenCalledWith('PHONE_SIGNUP_PERSIST_FAILED');
    const logged = JSON.stringify(logger.mock.calls);
    expect(logged).not.toContain(PHONE_NUMBER);
    expect(logged).not.toContain(providerMessage);
    logger.mockRestore();
  });
});
