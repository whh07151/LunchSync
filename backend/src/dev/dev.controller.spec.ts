import { ForbiddenException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { SupabaseService } from '../supabase/supabase.service';
import { DevController } from './dev.controller';

describe('DevController production gate', () => {
  const originalNodeEnv = process.env.NODE_ENV;
  const originalDevPromote = process.env.DEV_PROMOTE_ENABLED;

  afterEach(() => {
    if (originalNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = originalNodeEnv;
    if (originalDevPromote === undefined) delete process.env.DEV_PROMOTE_ENABLED;
    else process.env.DEV_PROMOTE_ENABLED = originalDevPromote;
  });

  it('denies seed JWT issuance in production even when the feature flag is true', async () => {
    process.env.NODE_ENV = 'production';
    process.env.DEV_PROMOTE_ENABLED = 'true';
    const controller = new DevController(
      { client: {} } as SupabaseService,
      {} as JwtService,
    );

    await expect(
      controller.loginAsSeed({ seedKey: 'minjun_customer' }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });
});
