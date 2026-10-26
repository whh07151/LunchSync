import { ConfigService } from '@nestjs/config';
import { createClient } from '@supabase/supabase-js';
import { SupabaseService } from './supabase.service';

jest.mock('@supabase/supabase-js', () => ({
  createClient: jest.fn(),
}));

describe('SupabaseService client isolation', () => {
  it('creates separate sessionless clients for DB and one-shot Auth work', () => {
    const databaseClient = { kind: 'database' };
    const authClient = { kind: 'auth' };
    const createClientMock = createClient as jest.MockedFunction<
      typeof createClient
    >;
    createClientMock
      .mockReturnValueOnce(databaseClient as never)
      .mockReturnValueOnce(authClient as never);

    const service = new SupabaseService({
      getOrThrow: jest.fn((key: string) =>
        key === 'SUPABASE_URL'
          ? 'https://lunchsync.test'
          : 'test-service-role-key',
      ),
      get: jest.fn((key: string) =>
        key === 'SUPABASE_ANON_KEY' ? 'test-anon-key' : undefined,
      ),
    } as unknown as ConfigService);

    expect(service.client).toBe(databaseClient);
    expect(service.createIsolatedAuthClient()).toBe(authClient);
    expect(createClientMock).toHaveBeenNthCalledWith(
      1,
      'https://lunchsync.test',
      'test-service-role-key',
      expect.objectContaining({
        auth: {
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUrl: false,
        },
      }),
    );
    expect(createClientMock).toHaveBeenNthCalledWith(
      2,
      'https://lunchsync.test',
      'test-anon-key',
      expect.objectContaining({
        auth: {
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUrl: false,
        },
      }),
    );
  });
});
