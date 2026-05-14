import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { OrdersModule } from '../orders/orders.module';
import { RestaurantsController } from './restaurants.controller';
import { RestaurantsService } from './restaurants.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 식당/메뉴 모듈
//
// 2026-05-15 의존성 추가:
//   OrdersModule import → GET /restaurants/:id/reviews 라우트에서
//   OrdersService.getReviewsByRestaurant 를 재사용하기 위함.
//   (orders 테이블 안에 review_* 컬럼이 있어 OrdersService 가 도메인 소유)
// ══════════════════════════════════════════════════════════

@Module({
  imports: [AuthModule, OrdersModule],
  controllers: [RestaurantsController],
  providers: [RestaurantsService],
  exports: [RestaurantsService],
})
export class RestaurantsModule {}
