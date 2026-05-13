import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ServeStaticModule } from '@nestjs/serve-static';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { APP_GUARD } from '@nestjs/core';
import { join } from 'path';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { SupabaseModule } from './supabase/supabase.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { SessionsModule } from './sessions/sessions.module';
import { InvitationsModule } from './invitations/invitations.module';
import { RestaurantsModule } from './restaurants/restaurants.module';
import { RecommendationsModule } from './recommendations/recommendations.module';
import { VotesModule } from './votes/votes.module';
import { OrdersModule } from './orders/orders.module';
import { PaymentsModule } from './payments/payments.module';
import { PosModule } from './pos/pos.module';
import { CrawlModule } from './crawl/crawl.module';
import { NotificationsModule } from './notifications/notifications.module';

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

    // Rate Limiting — 박검토 후 강화 (2026-05-12) → 라이브 테스트 후 보정 (2026-05-13):
    //   default: 모든 엔드포인트 기본 — 분당 200 요청 (100 → 200 완화)
    //     이유: 손님 앱 3초 폴링 + 동시 화면 다수(홈/투표/주문추적) + LSPOS 좌석 시드 일괄 호출이
    //     겹치면 분당 100 한도를 빠르게 초과해 정상 동작이 429로 차단됨.
    //     폴링 전용 GET 은 컨트롤러에서 @SkipThrottle() 로 추가 제외하고,
    //     글로벌 한도는 두 배로 올려 안전 마진 확보. (캡스톤 라이브 시연 대응)
    //   auth:    로그인/이메일 OTP — 분당 5회 (부르트포스 방어, login/email-otp 컨트롤러에서 @Throttle 로 지정)
    //   signup:  가입 — 시간당 10회 (대량 가입 폭주로 Supabase quota 소진 방어)
    ThrottlerModule.forRoot([
      { name: 'default', ttl: 60_000, limit: 200 },
      { name: 'auth', ttl: 60_000, limit: 5 },
      { name: 'signup', ttl: 3_600_000, limit: 10 },
    ]),

    // 정적 파일 서빙 (toss-checkout.html 등)
    // 모바일 앱에서 인앱 WebView로 결제 페이지 접근 시 사용
    // __dirname = dist/ → '../public' = backend/public
    ServeStaticModule.forRoot({
      rootPath: join(__dirname, '..', '..', 'public'),
      serveRoot: '/',
      exclude: ['/api/(.*)'],
    }),

    // Supabase 클라이언트 전역 제공
    SupabaseModule,

    // 카카오 로그인 / JWT 발급
    AuthModule,

    // 유저 프로필 조회/수정
    UsersModule,

    // 점심 세션 생성/조회/멤버 관리
    SessionsModule,

    // 초대 링크 생성/수락
    InvitationsModule,

    // 식당/메뉴 조회
    RestaurantsModule,

    // CORE-07/08: 그룹 추천 엔진 + 중복 회피
    RecommendationsModule,

    // 투표 + CU-15 결과 확정
    VotesModule,

    // 주문/결제 (CORE-09/10, CU-17/18/19)
    OrdersModule,

    // 토스페이먼츠 v2 결제 승인 (CU-19)
    PaymentsModule,

    // 점주앱/POS (OW-10, POS-08/09/13)
    PosModule,

    // 식당 크롤링 (카카오 + 네이버)
    CrawlModule,

    // CU-22 알림함 (주문/투표 이벤트 기반 알림)
    NotificationsModule,
  ],
  controllers: [AppController],
  providers: [
    AppService,
    // Rate limiting 전역 적용 (모든 엔드포인트)
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
  ],
})
export class AppModule {}
