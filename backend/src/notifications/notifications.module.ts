import { Module } from '@nestjs/common';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 알림(notifications) 모듈 등록
//
// 제공 엔드포인트:
//   GET   /api/notifications              — 내 알림 목록
//   PATCH /api/notifications/:id/read     — 단건 읽음 처리
//   PATCH /api/notifications/read-all     — 전체 읽음 처리
// ══════════════════════════════════════════════════════════

@Module({
  controllers: [NotificationsController],
  providers: [NotificationsService],
  exports: [NotificationsService], // 다른 모듈(orders 등)이 알림 발송용으로 주입 가능
})
export class NotificationsModule {}
