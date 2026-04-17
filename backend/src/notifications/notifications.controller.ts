import { Controller, Get, Param, Patch, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { NotificationsService } from './notifications.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-22 알림함 HTTP 엔드포인트
//
// 엔드포인트:
//   GET   /api/notifications            — 내 알림 목록 (최신순)
//   PATCH /api/notifications/:id/read   — 단건 읽음
//   PATCH /api/notifications/read-all   — 전체 읽음
//
// JWT 가드 적용 — 본인 알림만 조회/변경 가능.
// ══════════════════════════════════════════════════════════

@Controller('notifications')
@UseGuards(JwtAuthGuard)
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  // ── GET /api/notifications ────────────────────────────
  @Get()
  async getMyNotifications(@Req() req: { user: { userId: string } }) {
    const list = await this.notificationsService.getMyNotifications(
      req.user.userId,
    );
    return { success: true, data: list };
  }

  // ── PATCH /api/notifications/read-all ─────────────────
  // :id 라우트보다 먼저 선언해야 NestJS 라우터가 'read-all'을 id로 인식하지 않음
  @Patch('read-all')
  async markAllAsRead(@Req() req: { user: { userId: string } }) {
    const count = await this.notificationsService.markAllAsRead(
      req.user.userId,
    );
    return { success: true, data: { updatedCount: count } };
  }

  // ── PATCH /api/notifications/:id/read ─────────────────
  @Patch(':id/read')
  async markAsRead(
    @Req() req: { user: { userId: string } },
    @Param('id') id: string,
  ) {
    const updated = await this.notificationsService.markAsRead(
      req.user.userId,
      id,
    );
    return { success: true, data: updated };
  }
}
