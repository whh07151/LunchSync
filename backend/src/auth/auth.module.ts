import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { ConfigService } from '@nestjs/config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './jwt.strategy';
import { JwtAuthGuard } from './jwt-auth.guard';
import { EmailOtpController } from './email-otp.controller';
import { EmailOtpService } from './email-otp.service';
import { FirebaseService } from './firebase.service';
import { SessionAccessService } from './session-access.service';
import { EmailVerificationGuard } from './email-verification.guard';

// ══════════════════════════════════════════════════════════
// 파일 역할: 인증 모듈
//
// JwtModule.registerAsync: ConfigModule이 먼저 로드된 후
// .env의 JWT_SECRET, JWT_EXPIRES_IN 값을 읽어서 JWT 설정
// ══════════════════════════════════════════════════════════

@Module({
  imports: [
    PassportModule,
    JwtModule.registerAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        // .env 의 JWT_EXPIRES_IN 우선 (미설정 시 기본 48h).
        // 캡스톤 시연 기준 48h — 이틀에 한 번 로그인. 운영 환경은 1~2h 권장.
        const expiresIn = (config.get<string>('JWT_EXPIRES_IN') ?? '48h') as
          | '1h'
          | '2h'
          | '12h'
          | '24h'
          | '48h'
          | '1d'
          | '2d'
          | '7d';
        return {
          secret: config.getOrThrow<string>('JWT_SECRET'),
          signOptions: { expiresIn },
        };
      },
    }),
  ],
  controllers: [AuthController, EmailOtpController],
  providers: [
    AuthService,
    JwtStrategy,
    JwtAuthGuard,
    EmailOtpService,
    FirebaseService,
    SessionAccessService,
    EmailVerificationGuard,
  ],
  // JwtModule도 export — PosModule 의 PosAuthService 가 JwtService 를 주입받기 위함
  // FirebaseService 도 export — NotificationsModule 이 FCM 푸시 송신용으로 주입
  exports: [JwtAuthGuard, JwtModule, FirebaseService, SessionAccessService],
})
export class AuthModule {}
