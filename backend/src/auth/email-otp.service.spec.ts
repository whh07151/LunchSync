import { UnauthorizedException } from '@nestjs/common';
import { EmailOtpService } from './email-otp.service';

describe('EmailOtpService verification-token binding', () => {
  it('rejects a token subject with no matching account before contacting the provider', async () => {
    const signInWithOtp = jest.fn();
    const maybeSingle = jest.fn().mockResolvedValue({ data: null, error: null });
    const supabase = {
      client: {
        from: jest.fn().mockReturnValue({
          select: jest.fn().mockReturnValue(
            (() => {
              const builder = {
                eq: jest.fn(() => builder),
                ilike: jest.fn(() => builder),
                maybeSingle,
              };
              return builder;
            })(),
          ),
        }),
      },
      createIsolatedAuthClient: jest.fn().mockReturnValue({
        auth: { signInWithOtp },
      }),
    };

    const service = new EmailOtpService(supabase as never);

    await expect(
      service.sendOtp(
        '11111111-1111-4111-8111-111111111111',
        'unknown@example.com',
      ),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(signInWithOtp).not.toHaveBeenCalled();
  });
});
