import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';

// ══════════════════════════════════════════════════════════
// 파일 역할: NestJS 앱 진입점 (서버 시작)
//
// 설정 항목:
//   1. ValidationPipe — DTO의 class-validator 데코레이터를
//      자동으로 적용해서 잘못된 요청을 400으로 차단
//      whitelist: true → DTO에 없는 필드는 자동 제거 (보안)
//
//   2. CORS — Flutter 앱(모바일)과 POS 웹(Next.js)에서
//      API 요청이 가능하도록 허용
//      개발 중에는 origin: '*' 허용, 배포 시 도메인 제한 필요
//
//   3. PORT — .env의 PORT 값 사용, 없으면 기본 3000
// ══════════════════════════════════════════════════════════

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // ── 전역 유효성 검사 파이프 ──────────────────────────────
  // 모든 엔드포인트에서 DTO 유효성 검사를 자동 실행
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,       // DTO에 정의되지 않은 필드 자동 제거
      forbidNonWhitelisted: true, // 정의되지 않은 필드가 오면 400 에러
      transform: true,       // 요청 데이터를 DTO 타입으로 자동 변환 (string → number 등)
    }),
  );

  // ── CORS 설정 ────────────────────────────────────────────
  // Flutter 모바일 앱은 CORS 무관하지만,
  // POS 웹(Next.js)에서 API 호출 시 필요
  // TODO: 배포 시 origin을 실제 POS 웹 도메인으로 제한
  app.enableCors({
    origin: '*',
    methods: ['GET', 'POST', 'PATCH', 'DELETE'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  });

  // ── API 전역 prefix ──────────────────────────────────────
  // 모든 엔드포인트 앞에 /api 붙임
  // 예: GET /api/users/me, POST /api/sessions
  app.setGlobalPrefix('api');

  const port = process.env.PORT ?? 3000;
  await app.listen(port);

  console.log(`🚀 LunchSync 서버 실행 중: http://localhost:${port}/api`);
}
bootstrap();
