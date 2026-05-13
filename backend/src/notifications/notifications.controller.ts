import { Controller, Get, Param, Patch, Req, UseGuards } from '@nestjs/common';
// 2026-05-13 코드 리뷰 후속(M4):
//   초기엔 SkipThrottle 로 단순 제외했으나 본인 알림 폴링이라도 토큰 탈취 시
//   DoS 가능성이 있어 @Throttle 로 적정 한도(분당 60)를 명시. 30초 폴링 기준
//   분당 2회 정도라 한도 60은 일반 사용엔 영향 없고 악의적 호출만 차단.
import { Throttle } from '@nestjs/throttler';
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
  // 알림함 폴링(주기 호출) — DoS 보호를 위해 throttler 적정 한도(분당 60) 명시
  // (2026-05-13: SkipThrottle → @Throttle 적정값으로 전환, 코드 리뷰 M4)
  @Throttle({ default: { limit: 60, ttl: 60000 } })
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
