// ══════════════════════════════════════════════════════════
// 파일 역할: dev 전용 우회 라우트 모듈
//
// 라우트:
//   POST /api/dev/promote-to-owner
//
// 활성 조건:
//   process.env.DEV_PROMOTE_ENABLED === 'true' (라우트 안에서 게이트)
//
// app.module.ts imports 배열에 항상 추가 — 모듈 자체는 가벼움.
// 라우트 차단은 컨트롤러 내부 가드가 담당.
// ══════════════════════════════════════════════════════════

import { Module } from '@nestjs/common';
import { SupabaseModule } from '../supabase/supabase.module';
import { AuthModule } from '../auth/auth.module';
import { DevController } from './dev.controller';

@Module({
  // AuthModule 을 import 해서 JwtService 주입 (login-as-seed 시드 JWT 발급용)
  imports: [SupabaseModule, AuthModule],
  controllers: [DevController],
})
export class DevModule {}
