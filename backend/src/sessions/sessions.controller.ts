import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { IsString, IsOptional, IsNotEmpty, IsInt, Min } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SessionsService } from './sessions.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 점심 세션 관련 HTTP 엔드포인트
//
// 엔드포인트:
//   POST   /api/sessions              — 세션 생성
//   GET    /api/sessions/today        — 오늘 내 세션 목록
//   GET    /api/sessions/:id          — 세션 상세
//   PATCH  /api/sessions/:id/status   — 세션 상태 변경
//   GET    /api/sessions/:id/members  — 세션 멤버 목록
//   POST   /api/sessions/:id/members  — 멤버 추가
//   DELETE /api/sessions/:id/members/:userId — 멤버 제거
// ══════════════════════════════════════════════════════════

class CreateSessionDto {
  @IsString()
  @IsNotEmpty()
  name: string;

  @IsOptional()
  @IsString()
  scheduledAt?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  radius?: number; // 식당 검색 반경 (미터)

  @IsOptional()
  @IsInt()
  @Min(0)
  budget?: number; // 1인당 예산 상한 (원)

  @IsOptional()
  @IsInt()
  @Min(0)
  returnMinutes?: number; // 복귀 여유 시간 (분)

  @IsOptional()
  @IsString()
  memo?: string; // 자유 메모
}

class UpdateSessionStatusDto {
  @IsString()
  @IsNotEmpty()
  status: string;
}

class AddMemberDto {
  @IsString()
  @IsNotEmpty()
  userId: string;
}

@Controller('sessions')
@UseGuards(JwtAuthGuard)
export class SessionsController {
  constructor(private readonly sessionsService: SessionsService) {}

  // ── POST /api/sessions ────────────────────────────────
  @Post()
  async createSession(
    @Req() req: { user: { userId: string } },
    @Body() dto: CreateSessionDto,
  ) {
    const result = await this.sessionsService.createSession(
      req.user.userId,
      dto,
    );
    return { success: true, data: result };
  }

  // ── GET /api/sessions/today ───────────────────────────
  @Get('today')
  async getTodaySessions(@Req() req: { user: { userId: string } }) {
    const result = await this.sessionsService.getTodaySessions(req.user.userId);
    return { success: true, data: result };
  }

  // ── GET /api/sessions/:id ─────────────────────────────
  @Get(':id')
  async getSessionById(@Param('id') id: string) {
    const result = await this.sessionsService.getSessionById(id);
    return { success: true, data: result };
  }

  // ── PATCH /api/sessions/:id/status ────────────────────
  @Patch(':id/status')
  async updateSessionStatus(
    @Param('id') id: string,
    @Body() dto: UpdateSessionStatusDto,
  ) {
    const result = await this.sessionsService.updateSessionStatus(id, dto);
    return { success: true, data: result };
  }

  // ── GET /api/sessions/:id/members ─────────────────────
  @Get(':id/members')
  async getSessionMembers(@Param('id') id: string) {
    const result = await this.sessionsService.getSessionMembers(id);
    return { success: true, data: result };
  }

  // ── POST /api/sessions/:id/members ────────────────────
  @Post(':id/members')
  async addMember(
    @Param('id') id: string,
    @Body() dto: AddMemberDto,
  ) {
    const result = await this.sessionsService.addMember(id, dto);
    return { success: true, data: result };
  }

  // ── DELETE /api/sessions/:id/members/:userId ──────────
  @Delete(':id/members/:userId')
  async removeMember(
    @Param('id') id: string,
    @Param('userId') userId: string,
  ) {
    const result = await this.sessionsService.removeMember(id, userId);
    return { success: true, data: result };
  }
}
