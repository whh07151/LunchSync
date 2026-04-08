import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { ConfigService } from '@nestjs/config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './jwt.strategy';
import { JwtAuthGuard } from './jwt-auth.guard';

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
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy, JwtAuthGuard],
  exports: [JwtAuthGuard],
})
export class AuthModule {}
