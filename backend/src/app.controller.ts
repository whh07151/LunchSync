import { Controller, Get, HttpException, HttpStatus } from '@nestjs/common';
// 2026-05-15 자율 E2E 회귀 발견: /api/health 가 글로벌 throttle 에 걸려 429 반환.
// 모니터링 엔드포인트는 throttle 적용 대상이 아님 → @SkipThrottle 적용.
import { SkipThrottle } from '@nestjs/throttler';
import { AppService } from './app.service';
import { SchemaHealthcheckService } from './supabase/schema-healthcheck.service';

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
  constructor(
    private readonly appService: AppService,
    private readonly schemaHealthcheck: SchemaHealthcheckService,
  ) {}

  @Get()
  getHello(): string {
    return this.appService.getHello();
  }

  // ── GET /api/health ─────────────────────────────────────
  // 모니터링 서비스가 5분~1분 간격으로 호출.
  // 200 응답이면 정상, 그 외엔 알림 트리거.
  // 2026-05-15 SkipThrottle: 글로벌 ThrottlerGuard 가 health 도 막아서 UptimeRobot 이 false alarm 을 받음.
  // 모니터링 엔드포인트는 IP당 호출수 제한 없음.
  @SkipThrottle({ default: true, auth: true, signup: true })
  @Get('health')
  health() {
    return {
      status: 'ok',
      timestamp: new Date().toISOString(),
    };
  }

  @SkipThrottle({ default: true, auth: true, signup: true })
  @Get('ready')
  ready() {
    const schema = this.schemaHealthcheck.getReadinessStatus();
    const response = {
      status: schema.ready ? 'ok' : 'not_ready',
      checks: { schema },
      timestamp: new Date().toISOString(),
    };

    if (!schema.ready) {
      throw new HttpException(response, HttpStatus.SERVICE_UNAVAILABLE);
    }

    return response;
  }
}
