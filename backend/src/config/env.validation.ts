interface EnvironmentInput {
  [key: string]: string | undefined;
}

const REQUIRED_IN_PRODUCTION = [
  'SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
  'JWT_SECRET',
  'CORS_ALLOWED_ORIGINS',
  'TOSS_SECRET_KEY',
  'KAKAO_APP_ID',
] as const;

function requireHttpsUrl(name: string, value: string | undefined): string[] {
  if (!value) return [];

  try {
    const parsed = new URL(value);
    return parsed.protocol === 'https:' ? [] : [`${name} must use https`];
  } catch {
    return [`${name} must be a valid URL`];
  }
}

function validateOriginList(value: string | undefined): string[] {
  if (!value) return [];

  const origins = value
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);

  if (origins.length === 0) {
    return ['CORS_ALLOWED_ORIGINS must include at least one origin'];
  }

  return origins.flatMap((origin) => {
    try {
      const parsed = new URL(origin);
      return parsed.protocol === 'https:'
        ? []
        : [`CORS_ALLOWED_ORIGINS contains non-https origin: ${origin}`];
    } catch {
      return [`CORS_ALLOWED_ORIGINS contains invalid origin: ${origin}`];
    }
  });
}

export function validateEnvironment(
  config: EnvironmentInput,
): EnvironmentInput {
  if (config.LUNCHSYNC_LOCAL_RUNTIME === 'true') {
    if (config.NODE_ENV === 'production') {
      throw new Error('Local runtime cannot be used in production');
    }
    const target = new URL(config.SUPABASE_URL ?? '');
    if (!['http:', 'https:'].includes(target.protocol) || target.username || target.password ||
        target.search || target.hash || !['127.0.0.1', 'localhost', '[::1]'].includes(target.hostname)) {
      throw new Error('Local runtime requires a loopback Supabase URL');
    }
    for (const name of ['FIREBASE_PROJECT_ID', 'FIREBASE_ADMIN_KEY_PATH', 'GOOGLE_APPLICATION_CREDENTIALS', 'GEMINI_API_KEY', 'TOSS_SECRET_KEY']) {
      if (config[name]?.trim()) throw new Error(`External ${name} is disabled in local runtime`);
    }
    if (config.KAKAO_REST_API_KEY?.trim() && config.LUNCHSYNC_ALLOW_KAKAO_DISCOVERY !== 'true') {
      throw new Error('Kakao discovery key requires explicit local opt-in');
    }
  }
  if (config.NODE_ENV !== 'production') {
    return config;
  }

  const errors: string[] = [];

  for (const name of REQUIRED_IN_PRODUCTION) {
    if (!config[name]?.trim()) {
      errors.push(`${name} is required in production`);
    }
  }

  if ((config.JWT_SECRET ?? '').trim().length < 32) {
    errors.push('JWT_SECRET must be at least 32 characters in production');
  }

  errors.push(...requireHttpsUrl('SUPABASE_URL', config.SUPABASE_URL));
  errors.push(...validateOriginList(config.CORS_ALLOWED_ORIGINS));

  const kakaoAppId = config.KAKAO_APP_ID?.trim();
  if (
    kakaoAppId &&
    (!/^[1-9]\d*$/.test(kakaoAppId) ||
      !Number.isSafeInteger(Number(kakaoAppId)))
  ) {
    errors.push(
      'KAKAO_APP_ID must be a positive safe integer in decimal notation',
    );
  }

  if (
    config.TRUST_PROXY_HOPS &&
    !/^[1-9]\d*$/.test(config.TRUST_PROXY_HOPS.trim())
  ) {
    errors.push('TRUST_PROXY_HOPS must be a positive integer when set');
  }

  if (errors.length > 0) {
    throw new Error(`Invalid production configuration: ${errors.join('; ')}`);
  }

  return config;
}
