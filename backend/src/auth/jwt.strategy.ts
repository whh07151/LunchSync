import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { ConfigService } from '@nestjs/config';

// ══════════════════════════════════════════════════════════
// 파일 역할: JWT 검증 전략 (Passport)
//
// 동작 방식:
//   Authorization: Bearer {token} 헤더에서 JWT를 추출해서
//   서명 검증 후 payload를 req.user에 주입
//
// payload 구조:
//   { sub: userId }  ← AuthService.kakaoLogin()에서 발급 시 설정
//
// 사용되는 곳:
//   JwtAuthGuard → 보호된 엔드포인트에서 자동 실행
// ══════════════════════════════════════════════════════════

// req.user에 주입되는 타입
export interface JwtPayload {
  sub: string; // users.id (UUID)
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(configService: ConfigService) {
    super({
      // Authorization: Bearer {token} 헤더에서 JWT 추출
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: configService.getOrThrow<string>('JWT_SECRET'),
    });
  }

  // JWT 검증 성공 후 호출됨 → 반환값이 req.user에 주입됨
  validate(payload: JwtPayload) {
    return { userId: payload.sub };
  }
}
