import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { SessionsModule } from '../sessions/sessions.module';
import { InvitationsController } from './invitations.controller';
import { InvitationsService } from './invitations.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 초대 링크 모듈
//
// SessionsModule import: 초대 수락 시 SessionsService.addMember() 사용
// ══════════════════════════════════════════════════════════

@Module({
  imports: [AuthModule, SessionsModule],
  controllers: [InvitationsController],
  providers: [InvitationsService],
})
export class InvitationsModule {}
