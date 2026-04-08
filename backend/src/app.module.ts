import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { SupabaseModule } from './supabase/supabase.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';

// ══════════════════════════════════════════════════════════
// 파일 역할: NestJS 루트 모듈
//
// 모듈 등록 순서 및 역할:
//   1. ConfigModule — .env 파일을 전역에서 읽을 수 있게 함
//      isGlobal: true → 모든 모듈에서 ConfigService 주입 가능
//
//   2. SupabaseModule — Supabase 클라이언트 전역 제공
//      @Global() 설정되어 있어 별도 import 불필요
//
//   이후 추가될 모듈들:
//     UsersModule, SessionsModule, RestaurantsModule,
//     VotesModule, CartModule, OrdersModule, NotificationsModule
// ══════════════════════════════════════════════════════════

@Module({
  imports: [
    // .env 파일을 자동으로 로드하고 전역에서 ConfigService로 접근 가능
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: '.env',
    }),

    // Supabase 클라이언트 전역 제공
    SupabaseModule,

    // 카카오 로그인 / JWT 발급
    AuthModule,

    // 유저 프로필 조회/수정
    UsersModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
