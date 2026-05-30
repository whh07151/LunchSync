import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { SessionsController } from './sessions.controller';
import { SessionsService } from './sessions.service';
import { ChemistryService } from './chemistry.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 점심 세션 모듈
//
// AuthModule import: JwtAuthGuard를 사용하기 위해 필요
// SessionsService를 export: 다른 모듈(invitations 등)에서 사용 가능
//
// 2026-05-31 추가:
//   ChemistryService — WOW 포인트 #3 점심 케미 매트릭스.
//   GET /api/sessions/:id/chemistry 라우트를 SessionsController 에서
//   사용하므로 같은 모듈 providers 에 등록한다. 외부 모듈에서 호출할 일이
//   없어 export 는 생략(컨트롤러 전용 서비스).
// ══════════════════════════════════════════════════════════

@Module({
  imports: [AuthModule],
  controllers: [SessionsController],
  providers: [SessionsService, ChemistryService],
  exports: [SessionsService],
})
export class SessionsModule {}
