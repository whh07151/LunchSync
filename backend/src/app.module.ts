import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ServeStaticModule } from '@nestjs/serve-static';
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
  providers: [AppService],
})
export class AppModule {}
