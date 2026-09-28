import { validateEnvironment } from './env.validation';

describe('validateEnvironment', () => {
  it.each(['https://real.supabase.co', 'http://localhost.evil.test', 'ftp://localhost', 'http://user:pw@localhost', 'http://localhost?redirect=remote'])('rejects nonlocal/ambiguous local target %s', (SUPABASE_URL) => {
    expect(() => validateEnvironment({ LUNCHSYNC_LOCAL_RUNTIME: 'true', SUPABASE_URL })).toThrow();
  });
  it('rejects local runtime in production and inherited paid/provider credentials', () => {
    const local = { LUNCHSYNC_LOCAL_RUNTIME: 'true', SUPABASE_URL: 'http://127.0.0.1:54321' };
    expect(validateEnvironment(local)).toBe(local);
    expect(() => validateEnvironment({ ...local, NODE_ENV: 'production' })).toThrow(/production/);
    for (const name of ['FIREBASE_ADMIN_KEY_PATH', 'GEMINI_API_KEY', 'TOSS_SECRET_KEY']) {
      expect(() => validateEnvironment({ ...local, [name]: 'synthetic-inherited-value' })).toThrow(/disabled/);
    }
  });
  it('allows only explicitly opted-in read-only Kakao discovery in local runtime', () => {
    const local = { LUNCHSYNC_LOCAL_RUNTIME: 'true', SUPABASE_URL: 'http://127.0.0.1:54321' };
    expect(() => validateEnvironment({ ...local, KAKAO_REST_API_KEY: 'local-test-key' })).toThrow(/opt-in/);
    expect(validateEnvironment({ ...local, KAKAO_REST_API_KEY: 'local-test-key', LUNCHSYNC_ALLOW_KAKAO_DISCOVERY: 'true' }))
      .toMatchObject({ LUNCHSYNC_ALLOW_KAKAO_DISCOVERY: 'true' });
  });
  const productionConfig = {
    NODE_ENV: 'production',
    SUPABASE_URL: 'https://project.supabase.co',
    SUPABASE_SERVICE_ROLE_KEY: 'service-role-key',
    JWT_SECRET: 'x'.repeat(32),
    CORS_ALLOWED_ORIGINS: 'https://app.example.com',
    TOSS_SECRET_KEY: 'test_sk_example',
    KAKAO_APP_ID: '1534395',
  };

  it.each([
    undefined,
    '',
    '   ',
    '0',
    '-1',
    '1.5',
    '1534395.0',
    '1e6',
    '0x1769db',
    '+1534395',
    '01534395',
    'NaN',
    'Infinity',
    '9007199254740992',
  ])('rejects missing or invalid Kakao app ID %p in production', (appId) => {
    expect(() =>
      validateEnvironment({ ...productionConfig, KAKAO_APP_ID: appId }),
    ).toThrow(/KAKAO_APP_ID/);
  });
  it.each(['1', '1534395', '9007199254740991', ' 1534395 '])(
    'accepts a positive safe decimal Kakao app ID %p',
    (appId) => {
      const config = { ...productionConfig, KAKAO_APP_ID: appId };
      expect(validateEnvironment(config)).toBe(config);
    },
  );

  it('allows development defaults', () => {
    expect(validateEnvironment({ NODE_ENV: 'development' })).toMatchObject({
      NODE_ENV: 'development',
    });
  });

  it('fails closed when production secrets and origins are missing', () => {
    expect(() => validateEnvironment({ NODE_ENV: 'production' })).toThrow(
      /SUPABASE_URL is required/,
    );
  });

  it('requires https origins in production', () => {
    expect(() =>
      validateEnvironment({
        NODE_ENV: 'production',
        SUPABASE_URL: 'https://project.supabase.co',
        SUPABASE_SERVICE_ROLE_KEY: 'service-role-key',
        JWT_SECRET: 'x'.repeat(32),
        CORS_ALLOWED_ORIGINS: 'http://localhost:3000',
        TOSS_SECRET_KEY: 'test_sk_example',
        KAKAO_APP_ID: '1534395',
      }),
    ).toThrow(/non-https origin/);
  });

  it('accepts a complete production configuration', () => {
    const config = {
      NODE_ENV: 'production',
      SUPABASE_URL: 'https://project.supabase.co',
      SUPABASE_SERVICE_ROLE_KEY: 'service-role-key',
      JWT_SECRET: 'x'.repeat(32),
      CORS_ALLOWED_ORIGINS: 'https://app.example.com',
      TOSS_SECRET_KEY: 'test_sk_example',
      KAKAO_APP_ID: '1534395',
    };

    expect(validateEnvironment(config)).toBe(config);
  });

  it('rejects an invalid trust proxy hop count', () => {
    expect(() =>
      validateEnvironment({
        NODE_ENV: 'production',
        SUPABASE_URL: 'https://project.supabase.co',
        SUPABASE_SERVICE_ROLE_KEY: 'service-role-key',
        JWT_SECRET: 'x'.repeat(32),
        CORS_ALLOWED_ORIGINS: 'https://app.example.com',
        TOSS_SECRET_KEY: 'test_sk_example',
        KAKAO_APP_ID: '1534395',
        TRUST_PROXY_HOPS: '0',
      }),
    ).toThrow(/TRUST_PROXY_HOPS/);
  });
});
