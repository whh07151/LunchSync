import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PaymentsController } from './payments.controller';
import { PaymentsService } from './payments.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 토스페이먼츠 결제 모듈
//
// - PaymentsController: POST /api/payments/confirm
// - PaymentsService: 토스 API 호출 + 주문 상태 업데이트
//
// AuthModule을 imports에 넣어 JwtAuthGuard를 사용할 수 있게 함
// ══════════════════════════════════════════════════════════

@Module({
  imports: [AuthModule],
  controllers: [PaymentsController],
  providers: [PaymentsService],
  exports: [PaymentsService],
})
export class PaymentsModule {}
