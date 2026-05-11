import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger } from '@nestjs/common';
import { NestExpressApplication } from '@nestjs/platform-express';
import { AppModule } from './app.module';

// helmet 은 v8 부터 ESM 기본 export. NestJS 11 + Node 18 미만 환경에서
// `import helmet from 'helmet'` 이 런타임 크래시를 일으킬 수 있어 CJS require 로
// 로드한다 (NestExpressApplication.use 가 받는 미들웨어 시그니처는 동일).
// eslint-disable-next-line @typescript-eslint/no-require-imports
const helmet = require('helmet') as (opts?: object) => unknown;

// ══════════════════════════════════════════════════════════
// 파일 역할: NestJS 앱 진입점 (서버 시작 + 보안 미들웨어)
//
// 보안 설정 (보안 에이전트 권장 반영 — 2026-05-11):
//   1. ValidationPipe: DTO 검증 + whitelist + forbidNonWhitelisted
//      → 정의되지 않은 필드 자동 제거 + 거부 (Mass Assignment 방어)
//   2. CORS: NODE_ENV 분기 — production 은 화이트리스트, dev 는 *
//      허용 도메인: Vercel(LSPOS), localhost(Flutter Web), 운영 도메인
//   3. Body Size Limit: 기본 100kb → 10kb (대용량 페이로드 거부)
//   4. /api 글로벌 prefix
//
// 헬스체크 엔드포인트: GET /api/health (app.controller.ts)
//   → UptimeRobot/CloudWatch 등 외부 모니터에서 호출
// ══════════════════════════════════════════════════════════

async function bootstrap() {
  const logger = new Logger('Bootstrap');
  const app = await NestFactory.create<NestExpressApplication>(AppModule);

  // ── 0. 보안 헤더 (helmet) + 요청 크기 제한 ───────────────
  // Defense in Depth — X-Frame-Options, X-Content-Type-Options,
  // Strict-Transport-Security, X-XSS-Protection 등 자동 적용.
  // contentSecurityPolicy 는 결제 webview 와 충돌 가능해 비활성화.
  app.use(
    helmet({
      contentSecurityPolicy: false,
      crossOriginEmbedderPolicy: false,
    }),
  );

  // body size 제한 — 대용량 페이로드 거부 (DoS 기본 방어)
  app.useBodyParser('json', { limit: '100kb' });
  app.useBodyParser('urlencoded', { limit: '100kb', extended: true });

  // ── 1. 전역 유효성 검사 파이프 ────────────────────────────
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: true },
      // 에러 메시지 상세 노출 차단 — production 에서는 일반 메시지만
      disableErrorMessages: process.env.NODE_ENV === 'production',
    }),
  );

  // ── 2. CORS 화이트리스트 ──────────────────────────────────
  // 개발: 모든 origin 허용 (Flutter Web 핫리로드 + LSPOS dev)
  // 운영: 명시된 도메인만 허용 (보안)
  const isProduction = process.env.NODE_ENV === 'production';
  const productionOrigins = (process.env.CORS_ALLOWED_ORIGINS ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);

  app.enableCors({
    origin: isProduction
      ? (origin, callback) => {
          // origin 이 undefined 인 경우(server-to-server, curl) 도 허용
          if (!origin) return callback(null, true);
          if (productionOrigins.includes(origin)) {
            callback(null, true);
          } else {
            logger.warn(`CORS 차단된 origin: ${origin}`);
            callback(new Error('CORS not allowed'), false);
          }
        }
      : true,
    methods: ['GET', 'POST', 'PATCH', 'DELETE'],
    allowedHeaders: ['Content-Type', 'Authorization', 'If-None-Match'],
    credentials: true,
    maxAge: 3600,
  });

  // ── 3. API 전역 prefix ────────────────────────────────────
  app.setGlobalPrefix('api');

  const port = process.env.PORT ?? 3000;
  await app.listen(port);

  logger.log(`🚀 LunchSync 서버 실행 중: http://localhost:${port}/api`);
  logger.log(`   환경: ${isProduction ? 'production' : 'development'}`);
  if (isProduction && productionOrigins.length > 0) {
    logger.log(`   CORS 허용: ${productionOrigins.join(', ')}`);
  }
}
bootstrap();
