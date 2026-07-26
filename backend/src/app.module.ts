import { MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ServeStaticModule } from '@nestjs/serve-static';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { APP_GUARD } from '@nestjs/core';
import { join } from 'path';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { SupabaseModule } from './supabase/supabase.module';
import { SchemaHealthcheckService } from './supabase/schema-healthcheck.service';
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
import { FriendsModule } from './friends/friends.module';
import { TournamentsModule } from './tournaments/tournaments.module';
import { MenusModule } from './menus/menus.module';
import { DevModule } from './dev/dev.module';
import { ObservabilityModule } from './observability/observability.module';
import { RequestLoggingMiddleware } from './observability/request-logging.middleware';

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

    // Rate Limiting
    //
    // ⚠️ 2026-05-17 회귀 수정:
    //   NestJS Throttler 는 forRoot 에 등록된 "모든" 명명 throttler 를
    //   "모든" 라우트에 동시 적용한다. 기존엔 default/auth/signup 3개를
    //   전역 등록 → signup(시간당 30회)이 투표 폴링·주문·결제·리뷰 등
    //   전 API 에 적용되어, 3초 폴링 시 ~90초 만에 시간당 30회를 초과한
    //   뒤 모든 요청이 429(ThrottlerException) 로 막혔다. (결제 실패 포함)
    //
    //   해결: 전역에는 넉넉한 default 1개만 둔다. auth/signup 라우트의
    //   브루트포스 방어 강화는 해당 컨트롤러에서 @Throttle({ default: ... })
    //   로 그 라우트에만 한정 적용한다 (auth.controller / pos-auth.controller).
    //   docs/LUNCHSYNC_SPECIFICATION.md 의 3초 폴링 설계와 양립.
    ThrottlerModule.forRoot([
      { name: 'default', ttl: 60_000, limit: 1000 },
    ]),

    // 정적 파일 서빙 (toss-checkout.html 등)
    // 모바일 앱에서 인앱 WebView로 결제 페이지 접근 시 사용
    //
    // 2026-05-14 사장님 시연 발견 — 404 Cannot GET /toss-checkout.html:
    //   기존 `join(__dirname, '..', '..', 'public')` 는 NestJS 빌드 후
    //   __dirname 이 dist/src 또는 dist 가 되어 backend/public 을 못 가리킴.
    //   `process.cwd()` 는 pm2 가 backend/ 에서 start 하므로 항상 backend/.
    //   → process.cwd() + '/public' 으로 변경 (절대적 안정).
    //
    // main.ts 의 useStaticAssets 와 중복이지만 안전망으로 둘 다 유지.
    ServeStaticModule.forRoot({
      rootPath: join(process.cwd(), 'public'),
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

    // CU-08 보강 — 친구 관계 (2026-05-14 사장님 시연 피드백 반영)
    FriendsModule,

    // WOW#6/#9 — 토너먼트 결과 적재 + 주간 트렌딩 식당 (2026-05-31)
    //   POST /api/tournaments         : 우승 결과 1건 저장
    //   GET  /api/tournaments/trending: 최근 N일 우승 빈도 상위 식당
    TournamentsModule,

    // CORE-09 — 메뉴 알레르기 충돌 검증기 (2026-05-31)
    //   GET /api/menus/restaurant/:id/check-allergens?userId=
    //   사용자 알레르기 ∩ 메뉴 알레르기 교집합 계산 (정확 매칭)
    MenusModule,

    // dev 전용 — 자동 QA 우회 (DEV_PROMOTE_ENABLED=true 일 때만 동작)
    DevModule,
    ObservabilityModule,
  ],
  controllers: [AppController],
  providers: [
    AppService,
    // Rate limiting 전역 적용 (모든 엔드포인트)
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
    // 부트 시 DB 스키마 무결성 헬스체크 (2026-05-14 image_url 사고 안전망)
    //   - OnModuleInit 훅에서 information_schema 조회 RPC 1회 호출
    //   - 누락 자원이 있으면 console.warn — 부트 자체는 막지 않음
    SchemaHealthcheckService,
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer): void {
    consumer.apply(RequestLoggingMiddleware).forRoutes('*');
  }
}
