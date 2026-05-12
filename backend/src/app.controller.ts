import { Controller, Get } from '@nestjs/common';
import { AppService } from './app.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 루트 컨트롤러 + 헬스체크 엔드포인트
//
// 엔드포인트:
//   GET /api/        — 서버 동작 확인 (간단한 hello)
//   GET /api/health  — 모니터링용 헬스체크 (UptimeRobot/CloudWatch)
//                       응답: { status, uptime, memoryMB, timestamp }
//
// 인증 불필요 — 외부 모니터링 서비스가 자유롭게 호출
// ══════════════════════════════════════════════════════════

@Controller()
export class AppController {
  // 서버 부팅 시점 — uptime 계산 기준
  private readonly startedAt = Date.now();

  constructor(private readonly appService: AppService) {}

  @Get()
  getHello(): string {
    return this.appService.getHello();
  }

  // ── GET /api/health ─────────────────────────────────────
  // 모니터링 서비스가 5분~1분 간격으로 호출.
  // 200 응답이면 정상, 그 외엔 알림 트리거.
  @Get('health')
  health() {
    const mem = process.memoryUsage();
    return {
      status: 'ok',
      uptimeSeconds: Math.floor((Date.now() - this.startedAt) / 1000),
      memoryMB: {
        rss: Math.round(mem.rss / 1024 / 1024),
        heapUsed: Math.round(mem.heapUsed / 1024 / 1024),
      },
      timestamp: new Date().toISOString(),
      nodeVersion: process.version,
    };
  }
}
