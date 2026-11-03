import {
  InternalServerErrorException,
  Logger,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { SupabaseService } from '../supabase/supabase.service';
import { AuthService } from './auth.service';
import { EmailOtpController } from './email-otp.controller';
import { EmailOtpService } from './email-otp.service';
import { EmailVerificationGuard } from './email-verification.guard';
import { FirebaseService } from './firebase.service';
import { JwtStrategy } from './jwt.strategy';

const EMAIL = 'owner@example.com';
const USER_ID = '11111111-1111-4111-8111-111111111111';

function chainResult(result: unknown) {
  const builder = {
    select: jest.fn(),
    eq: jest.fn(),
    ilike: jest.fn(),
    maybeSingle: jest.fn(),
    single: jest.fn(),
    insert: jest.fn(),
    update: jest.fn(),
    is: jest.fn(),
  };
  builder.select.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.ilike.mockReturnValue(builder);
  builder.insert.mockReturnValue(builder);
  builder.update.mockReturnValue(builder);
  builder.is.mockReturnValue(builder);
  builder.maybeSingle.mockResolvedValue(result);
  builder.single.mockResolvedValue(result);
  return builder;
}

function newEmailUser(overrides: Record<string, unknown> = {}) {
  return {
    id: USER_ID,
    name: '사용자',
    profile_image: null,
    password_hash: '$2b$10$placeholder',
    role: 'CUSTOMER',
    status: 'APPROVED',
    org: null,
    budget: null,
    speed: null,
    email_verified_at: null,
    ...overrides,
  };
}

describe('email authentication boundary', () => {
  it('issues only a short-lived verification-purpose token at signup', async () => {
    const existingQuery = chainResult({ data: null, error: null });
    const insertQuery = chainResult({
      data: newEmailUser(),
      error: null,
    });
    const from = jest
      .fn()
      .mockReturnValueOnce(existingQuery)
      .mockReturnValueOnce(insertQuery);
    const jwt = { sign: jest.fn().mockReturnValue('verification-token') };

    const service = new AuthService(
      { client: { from } } as unknown as SupabaseService,
      jwt as unknown as JwtService,
      {} as FirebaseService,
    );

    const result = await service.emailSignup({
      email: EMAIL,
      password: 'password123',
      name: '사용자',
      role: 'CUSTOMER',
    });

    expect(result.accessToken).toBe('verification-token');
    expect(jwt.sign).toHaveBeenCalledWith(
      { sub: USER_ID, email: EMAIL, purpose: 'EMAIL_VERIFICATION' },
      { expiresIn: '10m' },
    );
  });

  it('does not expose database details when email signup persistence fails', async () => {
    const providerMessage = `insert failed for ${EMAIL}`;
    const logger = jest.spyOn(Logger.prototype, 'error').mockImplementation();
    const from = jest
      .fn()
      .mockReturnValueOnce(chainResult({ data: null, error: null }))
      .mockReturnValueOnce(
        chainResult({ data: null, error: { message: providerMessage } }),
      );
    const service = new AuthService(
      { client: { from } } as unknown as SupabaseService,
      { sign: jest.fn() } as unknown as JwtService,
      {} as FirebaseService,
    );

    let thrown: unknown;
    try {
      await service.emailSignup({
        email: EMAIL,
        password: 'password123',
        name: '사용자',
        role: 'CUSTOMER',
      });
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeInstanceOf(InternalServerErrorException);
    expect(
      JSON.stringify((thrown as InternalServerErrorException).getResponse()),
    ).not.toContain(providerMessage);
    expect(logger).toHaveBeenCalledWith('EMAIL_SIGNUP_PERSIST_FAILED');
    expect(JSON.stringify(logger.mock.calls)).not.toContain(EMAIL);
    logger.mockRestore();
  });

  it('rejects a correct password while the email is unverified', async () => {
    const passwordHash = await bcrypt.hash('password123', 4);
    const loginQuery = chainResult({
      data: newEmailUser({ password_hash: passwordHash }),
      error: null,
    });
    const jwt = { sign: jest.fn().mockReturnValue('verification-token') };
    const service = new AuthService(
      {
        client: { from: jest.fn().mockReturnValue(loginQuery) },
      } as unknown as SupabaseService,
      jwt as unknown as JwtService,
      {} as FirebaseService,
    );

    let thrown: unknown;
    try {
      await service.emailLogin(EMAIL, 'password123');
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeInstanceOf(UnauthorizedException);
    expect((thrown as UnauthorizedException).getResponse()).toMatchObject({
      code: 'EMAIL_VERIFICATION_REQUIRED',
      verificationToken: 'verification-token',
    });
    expect(jwt.sign).toHaveBeenCalledWith(
      { sub: USER_ID, email: EMAIL, purpose: 'EMAIL_VERIFICATION' },
      { expiresIn: '10m' },
    );
  });

  it('issues a normal JWT when a verified user logs in with the correct password', async () => {
    const passwordHash = await bcrypt.hash('password123', 4);
    const loginQuery = chainResult({
      data: newEmailUser({
        password_hash: passwordHash,
        email_verified_at: '2026-08-05T16:00:00+09:00',
      }),
      error: null,
    });
    const jwt = { sign: jest.fn().mockReturnValue('full-access-token') };
    const service = new AuthService(
      {
        client: { from: jest.fn().mockReturnValue(loginQuery) },
      } as unknown as SupabaseService,
      jwt as unknown as JwtService,
      {} as FirebaseService,
    );

    await expect(
      service.emailLogin(EMAIL, 'password123'),
    ).resolves.toMatchObject({
      accessToken: 'full-access-token',
      user: { id: USER_ID },
    });
    expect(jwt.sign).toHaveBeenCalledWith({ sub: USER_ID });
  });

  it('issues a normal JWT only after the public user is marked verified', async () => {
    const verifiedQuery = chainResult({
      data: newEmailUser({
        email_verified_at: '2026-08-05T16:00:00+09:00',
      }),
      error: null,
    });
    const jwt = { sign: jest.fn().mockReturnValue('full-access-token') };
    const service = new AuthService(
      {
        client: { from: jest.fn().mockReturnValue(verifiedQuery) },
      } as unknown as SupabaseService,
      jwt as unknown as JwtService,
      {} as FirebaseService,
    );

    const result = await service.completeEmailVerification(USER_ID, EMAIL);

    expect(result.accessToken).toBe('full-access-token');
    expect(jwt.sign).toHaveBeenCalledWith({ sub: USER_ID });
  });

  it('rejects verification-purpose JWTs at the normal API guard boundary', async () => {
    const strategy = new JwtStrategy(
      {
        getOrThrow: jest.fn().mockReturnValue('test-secret'),
      } as unknown as ConfigService,
      { client: { from: jest.fn() } } as unknown as SupabaseService,
    );

    await expect(
      strategy.validate({
        sub: USER_ID,
        purpose: 'EMAIL_VERIFICATION',
      }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects a legacy access token while its email account is unverified', async () => {
    const userQuery = chainResult({
      data: {
        id: USER_ID,
        auth_provider: 'EMAIL',
        email_verified_at: null,
      },
      error: null,
    });
    const strategy = new JwtStrategy(
      {
        getOrThrow: jest.fn().mockReturnValue('test-secret'),
      } as unknown as ConfigService,
      {
        client: { from: jest.fn().mockReturnValue(userQuery) },
      } as unknown as SupabaseService,
    );

    await expect(strategy.validate({ sub: USER_ID })).rejects.toMatchObject({
      response: expect.objectContaining({
        code: 'EMAIL_VERIFICATION_REQUIRED',
      }),
    });
  });

  it('preserves a normal session during a retryable account lookup outage', async () => {
    const strategy = new JwtStrategy(
      {
        getOrThrow: jest.fn().mockReturnValue('test-secret'),
      } as unknown as ConfigService,
      {
        client: {
          from: jest
            .fn()
            .mockReturnValue(
              chainResult({ data: null, error: { message: 'database down' } }),
            ),
        },
      } as unknown as SupabaseService,
    );

    await expect(strategy.validate({ sub: USER_ID })).rejects.toMatchObject({
      status: 503,
      response: expect.objectContaining({
        code: 'SESSION_ACCOUNT_LOOKUP_FAILED',
        retryable: true,
      }),
    });
  });

  it('rejects a normal token whose account no longer exists', async () => {
    const strategy = new JwtStrategy(
      {
        getOrThrow: jest.fn().mockReturnValue('test-secret'),
      } as unknown as ConfigService,
      {
        client: {
          from: jest
            .fn()
            .mockReturnValue(chainResult({ data: null, error: null })),
        },
      } as unknown as SupabaseService,
    );

    await expect(strategy.validate({ sub: USER_ID })).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });
});

describe('email verification JWT guard', () => {
  function contextFor(request: Record<string, unknown>) {
    return {
      switchToHttp: () => ({ getRequest: () => request }),
    } as never;
  }

  it('accepts only a verification-purpose token bound to a user and email', async () => {
    const request = {
      headers: { authorization: 'Bearer verification-token' },
    };
    const guard = new EmailVerificationGuard({
      verifyAsync: jest.fn().mockResolvedValue({
        sub: USER_ID,
        email: EMAIL,
        purpose: 'EMAIL_VERIFICATION',
      }),
    } as unknown as JwtService);

    await expect(guard.canActivate(contextFor(request))).resolves.toBe(true);
    expect(request).toMatchObject({
      emailVerification: { userId: USER_ID, email: EMAIL },
    });
  });

  it('rejects a normal access token at the OTP boundary', async () => {
    const guard = new EmailVerificationGuard({
      verifyAsync: jest.fn().mockResolvedValue({ sub: USER_ID }),
    } as unknown as JwtService);

    await expect(
      guard.canActivate(
        contextFor({ headers: { authorization: 'Bearer access-token' } }),
      ),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });
});

describe('email OTP token exchange', () => {
  it('returns the normal auth result only after OTP persistence succeeds', async () => {
    const emailOtpService = {
      verifyOtp: jest.fn().mockResolvedValue({ verified: true, email: EMAIL }),
    };
    const authResult = {
      accessToken: 'full-access-token',
      isNewUser: true,
      nextStep: 'PROFILE_SETUP',
      user: { id: USER_ID },
    };
    const authService = {
      completeEmailVerification: jest.fn().mockResolvedValue(authResult),
    };
    const controller = new EmailOtpController(
      emailOtpService as unknown as EmailOtpService,
      authService as unknown as AuthService,
    );

    await expect(
      controller.verifyOtp(
        {
          headers: {},
          emailVerification: { userId: USER_ID, email: EMAIL },
        },
        { email: EMAIL, code: '123456' },
      ),
    ).resolves.toEqual({ success: true, data: authResult });
    expect(emailOtpService.verifyOtp).toHaveBeenCalledWith(
      USER_ID,
      EMAIL,
      '123456',
    );
    expect(authService.completeEmailVerification).toHaveBeenCalledWith(
      USER_ID,
      EMAIL,
    );
  });
});

describe('email OTP persistence', () => {
  function createOtpService(updateResult: unknown) {
    const userQuery = chainResult({
      data: { id: USER_ID, email_verified_at: null },
      error: null,
    });
    const updateQuery = chainResult(updateResult);
    const auth = {
      verifyOtp: jest.fn().mockResolvedValue({ error: null }),
    };
    const createIsolatedAuthClient = jest.fn().mockReturnValue({ auth });
    const service = new EmailOtpService({
      client: {
        from: jest
          .fn()
          .mockReturnValueOnce(userQuery)
          .mockReturnValueOnce(updateQuery),
      },
      createIsolatedAuthClient,
    } as unknown as SupabaseService);
    return { service, updateQuery, auth, createIsolatedAuthClient };
  }

  it('requires exactly one public user row to record verification', async () => {
    const { service, updateQuery, auth, createIsolatedAuthClient } =
      createOtpService({
        data: { id: USER_ID },
        error: null,
      });

    await expect(
      service.verifyOtp(USER_ID, EMAIL, '123456'),
    ).resolves.toMatchObject({
      verified: true,
      email: EMAIL,
    });
    expect(updateQuery.select).toHaveBeenCalledWith('id');
    expect(updateQuery.eq).toHaveBeenCalledWith('id', USER_ID);
    expect(updateQuery.ilike).toHaveBeenCalledWith('email', EMAIL);
    expect(updateQuery.is).toHaveBeenCalledWith('email_verified_at', null);
    expect(updateQuery.maybeSingle).toHaveBeenCalled();
    expect(createIsolatedAuthClient).toHaveBeenCalledTimes(1);
    expect(auth.verifyOtp).toHaveBeenCalledWith({
      email: EMAIL,
      token: '123456',
      type: 'email',
    });
  });

  it.each([
    ['database error', { data: null, error: { message: 'write failed' } }],
    ['no matching user', { data: null, error: null }],
  ])('does not report OTP success after a %s', async (_label, updateResult) => {
    const { service } = createOtpService(updateResult);

    await expect(
      service.verifyOtp(USER_ID, EMAIL, '123456'),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });
});
