import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { SessionsController } from './sessions.controller';
import { SessionsService } from './sessions.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 점심 세션 모듈
//
// AuthModule import: JwtAuthGuard를 사용하기 위해 필요
// SessionsService를 export: 다른 모듈(invitations 등)에서 사용 가능
// ══════════════════════════════════════════════════════════

@Module({
  imports: [AuthModule],
  controllers: [SessionsController],
  providers: [SessionsService],
  exports: [SessionsService],
})
export class SessionsModule {}
