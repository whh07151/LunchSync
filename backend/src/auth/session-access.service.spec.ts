import { NotFoundException, UnauthorizedException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { SessionAccessService } from './session-access.service';

function membershipResult(data: unknown, error: unknown = null) {
  const builder = {
    select: jest.fn(),
    eq: jest.fn(),
    maybeSingle: jest.fn(),
  };
  builder.select.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.maybeSingle.mockResolvedValue({ data, error });
  return builder;
}

describe('SessionAccessService', () => {
  it('allows an authenticated session member', async () => {
    const from = jest.fn().mockReturnValue(
      membershipResult({ user_id: 'member-a' }),
    );
    const service = new SessionAccessService({
      client: { from },
    } as unknown as SupabaseService);

    await expect(
      service.assertMember('session-a', 'member-a'),
    ).resolves.toBeUndefined();
  });

  it('does not reveal whether a non-member session id exists', async () => {
    const service = new SessionAccessService({
      client: { from: jest.fn().mockReturnValue(membershipResult(null)) },
    } as unknown as SupabaseService);

    await expect(
      service.assertMember('session-a', 'outsider'),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('rejects POS or malformed principals without a user id', async () => {
    const service = new SessionAccessService({
      client: { from: jest.fn() },
    } as unknown as SupabaseService);

    await expect(
      service.assertMember('session-a', undefined),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });
});
