import {
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { ConfigService } from '@nestjs/config';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: JWT 검증 전략 (Passport)
//
// 동작 방식:
//   Authorization: Bearer {token} 헤더에서 JWT를 추출해서
//   서명 검증 후 payload를 req.user에 주입
//
// payload 구조 (2026-05-11 LSPOS 통합 후):
//   USER 토큰 (카카오/이메일 로그인): { sub: userId, type?: 'USER' }
//     — type 필드가 없는 기존 토큰도 USER 로 간주 (하위 호환)
//   POS 토큰 (POS 단말 로그인):       { sub: restaurantId, type: 'POS' }
//
// req.user 결과:
//   USER 토큰 → { userId: <uuid>, type: 'USER' }
//   POS 토큰  → { restaurantId: <uuid>, type: 'POS' }
//
// 사용되는 곳:
//   JwtAuthGuard → 보호된 엔드포인트에서 자동 실행
// ══════════════════════════════════════════════════════════

/// JWT payload 타입 — 발급 시(AuthService.kakaoLogin / PosAuthService.login)
/// 이 형태로 서명함.
export interface JwtPayload {
  sub: string; // USER 토큰: users.id / POS 토큰: restaurants.id
  type?: 'USER' | 'POS'; // 토큰 종류. 미지정/USER 는 사용자, POS 는 단말
  purpose?: 'EMAIL_VERIFICATION'; // 일반 API 접근이 금지된 단기 검증 토큰
  email?: string; // 이메일 검증 토큰의 계정 바인딩
  ownerUserId?: string; // OWNER 자격으로 발급한 POS 토큰의 현재 권한 재검증용
  authMode?: 'OWNER' | 'SHARED_PIN';
}

/// req.user 타입 — 컨트롤러에서 @Req() 로 받을 때 참조용.
/// USER 토큰일 때 userId 가, POS 토큰일 때 restaurantId 가 채워짐.
export interface AuthedRequestUser {
  userId?: string;
  restaurantId?: string;
  type: 'USER' | 'POS';
  ownerUserId?: string;
  authMode?: 'OWNER' | 'SHARED_PIN';
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    configService: ConfigService,
    private readonly supabase: SupabaseService,
  ) {
    super({
      // Authorization: Bearer {token} 헤더에서 JWT 추출
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: configService.getOrThrow<string>('JWT_SECRET'),
    });
  }

  // JWT 검증 성공 후 호출됨 → 반환값이 req.user 에 주입됨
  // POS 토큰은 restaurantId 키로, 그 외(USER)는 userId 키로 노출 — 컨트롤러가 명확히 구분.
  async validate(payload: JwtPayload): Promise<AuthedRequestUser> {
    if (payload.purpose === 'EMAIL_VERIFICATION') {
      throw new UnauthorizedException('이메일 인증이 필요한 토큰입니다.');
    }
    if (payload.type === 'POS') {
      return {
        restaurantId: payload.sub,
        type: 'POS',
        ownerUserId: payload.ownerUserId,
        authMode: payload.authMode,
      };
    }

    // 과거 버전이 이메일 가입 직후 발급했던 type/purpose 없는 일반 JWT도
    // 남은 TTL 동안 보호 API를 통과하지 못하도록 현재 계정 상태를 재검증한다.
    const { data: user, error } = await this.supabase.client
      .from('users')
      .select('id, auth_provider, email_verified_at')
      .eq('id', payload.sub)
      .maybeSingle();
    if (error) {
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: 'SESSION_ACCOUNT_LOOKUP_FAILED',
        message: '계정 상태를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
        retryable: true,
      });
    }
    if (!user) {
      throw new UnauthorizedException('유효하지 않은 사용자 세션입니다.');
    }
    if (user.auth_provider === 'EMAIL' && !user.email_verified_at) {
      throw new UnauthorizedException({
        statusCode: 401,
        code: 'EMAIL_VERIFICATION_REQUIRED',
        message: '이메일 인증을 완료한 뒤 이용해주세요.',
      });
    }
    // USER 토큰 (또는 type 미지정 — 기존 카카오/이메일 발급 토큰)
    return { userId: payload.sub, type: 'USER' };
  }
}
