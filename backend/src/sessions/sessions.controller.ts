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
import {
  IsString,
  IsOptional,
  IsNotEmpty,
  IsInt,
  IsNumber,
  Min,
  Max,
  MaxLength,
} from 'class-validator';
// 2026-05-13 SkipThrottle 도입:
//   손님 앱이 멤버 목록을 3초 간격으로 폴링하고 홈 화면이 today 세션을
//   주기적으로 가져오는 탓에 글로벌 throttler(분당 100) 한도를 빠르게 소모.
//   읽기 전용 + 본인 데이터만 노출하는 폴링 엔드포인트는 SkipThrottle 적용해
//   429 오류로 인한 정상 동작 차단을 방지한다.
import { SkipThrottle } from '@nestjs/throttler';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import type { AuthedRequestUser } from '../auth/jwt.strategy';
import { SessionsService } from './sessions.service';

// 2026-05-13 타입 추출 (코드 리뷰 M2):
//   pos.controller 패턴 따라 인라인 5회 반복 → 단일 AuthedRequest 로 통일.
//   AuthedRequestUser 는 jwt.strategy 에서 정의(USER/POS 토큰 공용).
type AuthedRequest = { user: AuthedRequestUser };

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
  @MaxLength(100, { message: '세션 이름은 100자 이하여야 해요.' })
  name: string;

  @IsOptional()
  @IsString()
  scheduledAt?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(10000, { message: '반경은 10km 이하여야 해요.' })
  radius?: number; // 식당 검색 반경 (미터)

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(100000, { message: '예산은 10만원 이하여야 해요.' })
  budget?: number; // 1인당 예산 상한 (원)

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(240, { message: '복귀 시간은 4시간 이하여야 해요.' })
  returnMinutes?: number; // 복귀 여유 시간 (분)

  @IsOptional()
  @IsString()
  @MaxLength(500, { message: '메모는 500자 이하여야 해요.' })
  memo?: string; // 자유 메모

  // ── 세션 기준 좌표 ────────────────────────────────────
  // 호스트가 세션을 생성한 시점의 GPS 좌표.
  // 추천 엔진이 이 값을 중심으로 radius 미터 내의 식당만 후보로 채택한다.
  // 선택 항목 — 전달되지 않으면 추천 서비스가 반경 필터 없이 폴백.
  @IsOptional()
  @IsNumber()
  @Min(-90)
  @Max(90)
  lat?: number; // 위도 (-90 ~ 90)

  @IsOptional()
  @IsNumber()
  @Min(-180)
  @Max(180)
  lng?: number; // 경도 (-180 ~ 180)
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
    @Req() req: AuthedRequest,
    @Body() dto: CreateSessionDto,
  ) {
    const result = await this.sessionsService.createSession(
      req.user.userId,
      dto,
    );
    return { success: true, data: result };
  }

  // ── GET /api/sessions/today ───────────────────────────
  // 홈 화면이 주기적으로 호출 → throttler 제외 (2026-05-13)
  @SkipThrottle()
  @Get('today')
  async getTodaySessions(@Req() req: AuthedRequest) {
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
  // 보안 패치: 호스트 검증 + 상태 전이 매트릭스 검증
  @Patch(':id/status')
  async updateSessionStatus(
    @Req() req: AuthedRequest,
    @Param('id') id: string,
    @Body() dto: UpdateSessionStatusDto,
  ) {
    const result = await this.sessionsService.updateSessionStatus(
      id,
      req.user.userId,
      dto,
    );
    return { success: true, data: result };
  }

  // ── GET /api/sessions/:id/members ─────────────────────
  // 손님 앱이 3초 간격 폴링 → throttler 제외 (2026-05-13)
  @SkipThrottle()
  @Get(':id/members')
  async getSessionMembers(@Param('id') id: string) {
    const result = await this.sessionsService.getSessionMembers(id);
    return { success: true, data: result };
  }

  // ── POST /api/sessions/:id/members ────────────────────
  // 보안 패치: 호스트만 가능
  @Post(':id/members')
  async addMember(
    @Req() req: AuthedRequest,
    @Param('id') id: string,
    @Body() dto: AddMemberDto,
  ) {
    const result = await this.sessionsService.addMember(
      id,
      req.user.userId,
      dto,
    );
    return { success: true, data: result };
  }

  // ── DELETE /api/sessions/:id/members/:userId ──────────
  // 보안 패치: 본인이 자기 자신 제거는 허용, 타인 제거는 호스트만
  @Delete(':id/members/:userId')
  async removeMember(
    @Req() req: AuthedRequest,
    @Param('id') id: string,
    @Param('userId') userId: string,
  ) {
    const result = await this.sessionsService.removeMember(
      id,
      req.user.userId,
      userId,
    );
    return { success: true, data: result };
  }
}
