// ══════════════════════════════════════════════════════════
// 파일 역할: CORE-09 메뉴 알레르기 검증기 NestJS 모듈 정의
//
// 구성:
//   - MenusController : HTTP 라우트 (JwtAuthGuard 필수)
//   - MenusService    : Supabase users / menu_items 알레르기 교집합 계산
//
// 등록 위치:
//   app.module.ts 의 imports 배열에 MenusModule 을 추가해야 라우트가 활성화됨.
//
// 의존성:
//   - SupabaseModule (전역 @Global() 이지만 명시적 import 로 의도 표현)
//
// exports:
//   - MenusService — 추후 추천 엔진(RecommendationsService) 에서 알레르기
//     필터링용으로 재사용할 가능성을 열어둠.
// ══════════════════════════════════════════════════════════

import { Module } from '@nestjs/common';
import { SupabaseModule } from '../supabase/supabase.module';
import { MenusController } from './menus.controller';
import { MenusService } from './menus.service';

@Module({
  imports: [SupabaseModule],
  controllers: [MenusController],
  providers: [MenusService],
  exports: [MenusService],
})
export class MenusModule {}
