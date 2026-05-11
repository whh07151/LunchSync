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
      useFactory: (config: ConfigService) => ({
        secret: config.getOrThrow<string>('JWT_SECRET'),
        // expiresIn 타입이 ms 라이브러리의 StringValue라 직접 지정
        signOptions: { expiresIn: '7d' as '7d' },
      }),
    }),
  ],
  controllers: [AuthController, EmailOtpController],
  providers: [AuthService, JwtStrategy, JwtAuthGuard, EmailOtpService, FirebaseService],
  // JwtModule도 export — PosModule 의 PosAuthService 가 JwtService 를 주입받기 위함
  exports: [JwtAuthGuard, JwtModule],
})
export class AuthModule {}
