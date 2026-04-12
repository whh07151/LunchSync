import { Body, Controller, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import { IsString, IsNotEmpty } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { InvitationsService } from './invitations.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 초대 링크 관련 HTTP 엔드포인트
//
// 엔드포인트:
//   POST /api/invitations           — 초대 코드 생성
//   GET  /api/invitations/:code     — 초대 정보 확인
//   POST /api/invitations/:code/accept — 초대 수락
// ══════════════════════════════════════════════════════════

class CreateInvitationDto {
  @IsString()
  @IsNotEmpty()
  sessionId: string;
}

@Controller('invitations')
@UseGuards(JwtAuthGuard)
export class InvitationsController {
  constructor(private readonly invitationsService: InvitationsService) {}

  // ── POST /api/invitations ─────────────────────────────
  @Post()
  async createInvitation(
    @Req() req: { user: { userId: string } },
    @Body() dto: CreateInvitationDto,
  ) {
    const result = await this.invitationsService.createInvitation(
      req.user.userId,
      dto,
    );
    return { success: true, data: result };
  }

  // ── GET /api/invitations/:code ────────────────────────
  @Get(':code')
  async getByCode(@Param('code') code: string) {
    const result = await this.invitationsService.getByCode(code);
    return { success: true, data: result };
  }

  // ── POST /api/invitations/:code/accept ────────────────
  @Post(':code/accept')
  async acceptInvitation(
    @Req() req: { user: { userId: string } },
    @Param('code') code: string,
  ) {
    const result = await this.invitationsService.acceptInvitation(
      code,
      req.user.userId,
    );
    return { success: true, data: result };
  }
}
