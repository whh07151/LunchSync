import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PaymentsModule } from '../payments/payments.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PosController } from './pos.controller';
import { PosService } from './pos.service';
import { PosAuthController } from './pos-auth.controller';
import { PosAuthService } from './pos-auth.service';
import { PosMenusController } from './pos-menus.controller';
import { PosMenusService } from './pos-menus.service';
import { PosSeatsController } from './pos-seats.controller';
import { PosSeatsService } from './pos-seats.service';
import { PosReservationsController } from './pos-reservations.controller';
import { PosReservationsService } from './pos-reservations.service';
import { PosRestaurantsController } from './pos-restaurants.controller';
import { PosRestaurantsService } from './pos-restaurants.service';
import { PosAccessService } from '../auth/pos-ownership.util';

// ══════════════════════════════════════════════════════════
// 파일 역할: 점주앱/POS 모듈
//
// 컨트롤러:
//   PosController              — 인증 필요 엔드포인트 (orders/stats/status/cancel)
//   PosAuthController          — POS 단말 로그인 (인증 없이 호출)
//   PosMenusController         — 메뉴 CRUD (사장앱과 LSPOS 양쪽에서 사용)
//   PosSeatsController         — 좌석 CRUD (2026-05-14 신설)
//   PosReservationsController  — 예약/웨이팅 CRUD (2026-05-14 신설)
//
// 서비스:
//   PosService             — 주문/통계/상태변경 로직
//   PosAuthService         — POS JWT 발급 로직
//   PosMenusService        — 메뉴 CRUD 로직
//   PosSeatsService        — 좌석 CRUD 로직
//   PosReservationsService — 예약/웨이팅 CRUD 로직
//
// AuthModule 의존:
//   - JwtAuthGuard (모든 보호 컨트롤러)
//   - JwtModule    (PosAuthService 가 JwtService 주입받기 위해 export 됨)
// ══════════════════════════════════════════════════════════

@Module({
  // 2026-05-15 단계 2 — PaymentsModule import:
  //   pos.cancelOrder 가 PaymentsService.cancelPayment 호출 (자동 환불).
  // 2026-05-15 단계 3 — NotificationsModule import:
  //   pos.updateOrderStatus 가 NotificationsService.createNotification 호출
  //   → 상태 전이마다 손님 푸시 알림 송신.
  imports: [AuthModule, PaymentsModule, NotificationsModule],
  controllers: [
    PosController,
    PosAuthController,
    PosMenusController,
    PosSeatsController,
    PosReservationsController,
    PosRestaurantsController,
  ],
  providers: [
    PosService,
    PosAuthService,
    PosMenusService,
    PosSeatsService,
    PosReservationsService,
    PosRestaurantsService,
    PosAccessService,
  ],
})
export class PosModule {}
