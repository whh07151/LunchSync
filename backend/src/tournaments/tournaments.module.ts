// ══════════════════════════════════════════════════════════
// 파일 역할: 토너먼트(WOW#6 + WOW#9) NestJS 모듈 정의
//
// 구성:
//   - TournamentsController : HTTP 라우트 (JwtAuthGuard 필수)
//   - TournamentsService    : Supabase tournament_results 테이블 입출력
//
// 등록 위치:
//   app.module.ts 의 imports 배열에 TournamentsModule 추가 필요.
//
// 의존성:
//   - SupabaseModule (전역 @Global() 이지만 명시적 import 로 의도 표현)
//
// 외부에 노출되는 service:
//   - TournamentsService 는 다른 모듈에서 트렌딩 결과를 직접 호출할 수도 있어
//     exports 로 노출(추후 추천 v3 가산점 등 확장 여지).
// ══════════════════════════════════════════════════════════

import { Module } from '@nestjs/common';
import { SupabaseModule } from '../supabase/supabase.module';
import { TournamentsController } from './tournaments.controller';
import { TournamentsService } from './tournaments.service';

@Module({
  imports: [SupabaseModule],
  controllers: [TournamentsController],
  providers: [TournamentsService],
  exports: [TournamentsService],
})
export class TournamentsModule {}
