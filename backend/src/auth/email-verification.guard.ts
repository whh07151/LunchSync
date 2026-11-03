import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';

export interface EmailVerificationPrincipal {
  userId: string;
  email: string;
}

export type EmailVerificationRequest = {
  headers: { authorization?: string };
  emailVerification?: EmailVerificationPrincipal;
};

@Injectable()
export class EmailVerificationGuard implements CanActivate {
  constructor(private readonly jwtService: JwtService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<EmailVerificationRequest>();
    const authorization = request.headers.authorization;
    const [scheme, token] = authorization?.split(' ') ?? [];

    if (scheme !== 'Bearer' || !token) {
      throw this.invalidToken();
    }

    try {
      const payload = await this.jwtService.verifyAsync<{
        sub?: unknown;
        email?: unknown;
        purpose?: unknown;
      }>(token);
      if (
        payload.purpose !== 'EMAIL_VERIFICATION' ||
        typeof payload.sub !== 'string' ||
        typeof payload.email !== 'string'
      ) {
        throw this.invalidToken();
      }

      request.emailVerification = {
        userId: payload.sub,
        email: payload.email,
      };
      return true;
    } catch (error) {
      if (error instanceof UnauthorizedException) throw error;
      throw this.invalidToken();
    }
  }

  private invalidToken(): UnauthorizedException {
    return new UnauthorizedException({
      statusCode: 401,
      code: 'EMAIL_VERIFICATION_TOKEN_INVALID',
      message: '이메일 인증 세션이 만료됐습니다. 비밀번호로 다시 로그인해주세요.',
      retryable: false,
    });
  }
}
