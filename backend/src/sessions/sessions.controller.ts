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
import { ChemistryService } from './chemistry.service';

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
//   DELETE /api/sessions/:id          — 세션 삭제 (호스트, WAITING/DONE 만)
//   GET    /api/sessions/:id/members  — 세션 멤버 목록
//   POST   /api/sessions/:id/members  — 멤버 추가
//   DELETE /api/sessions/:id/members/:userId — 멤버 제거
//   GET    /api/sessions/:id/chemistry — WOW#3 점심 케미 매트릭스
//   GET    /api/sessions/:id/invite    — WOW#8 친구 초대 통합 페이로드
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
  constructor(
    private readonly sessionsService: SessionsService,
    private readonly chemistryService: ChemistryService,
  ) {}

  // ── GET /api/sessions/:id/chemistry ───────────────────
  // WOW 포인트 #3 — "점심 케미 매트릭스"
  //
  // 세션 멤버 전원의 최근 30일 카테고리 빈도 + 투표 결과 식당 카테고리를 합산해
  // Gemini AI 가 한 줄 요약 라벨 + 0~100 점수를 생성한다.
  //
  // 응답 정책:
  //   - 정상 응답: { success: true, data: { score, label, tone, topCategories } }
  //   - Gemini 실패 / 데이터 없음 / 멤버 0명: { success: true, data: null }
  //     → Flutter 측이 null 이면 카드 자체를 미노출 (화면 깨짐 0).
  //
  // SkipThrottle 적용 — 추천 리스트가 진입 직후 1회 호출(이후 30분 캐시) 하므로
  // 폴링은 아니지만, 멤버 N명이 동시 진입할 때 글로벌 throttler 부담을 덜기 위해
  // 안전망으로 함께 둔다.
  @SkipThrottle({ default: true })
  @Get(':id/chemistry')
  async getChemistry(@Param('id') id: string) {
    const result = await this.chemistryService.getChemistry(id);
    return { success: true, data: result };
  }

  // ── GET /api/sessions/:id/invite ──────────────────────
  // WOW 포인트 #8 — "친구 초대 시스템"
  //
  // 손님 페르소나가 세션 로비에서 친구 한 명을 카톡으로 초대하는 흐름.
  // 응답 페이로드:
  //   {
  //     inviteCode: '8자리 hex',
  //     deepLink:   'lunchsync://join?code=XXXXXXXX',
  //     shortLink:  'https://lunchsync.duckdns.org/j/XXXXXXXX',
  //     expiresAt:  ISO8601 (기본 +6h)
  //   }
  //
  // Flutter 측은 이 응답을 받아 share_plus 의 Share.share() 로 OS 공유 시트를
  // 호출, 카카오톡·문자·메신저 등에 한 줄 메시지를 전달한다.
  //
  // 권한 정책:
  //   호스트 검증 없음 — 일반 멤버도 친구를 추가 초대할 수 있어야 자연스러움.
  //   (코드 자체가 권한 토큰)
  //
  // SkipThrottle: 손님이 공유 시트를 열고 닫는 행동을 빠르게 반복할 수 있어
  //   글로벌 throttler 한도(분당 100) 부담을 줄이기 위해 적용.
  @SkipThrottle({ default: true })
  @Get(':id/invite')
  async getInviteInfo(@Param('id') id: string) {
    const result = await this.sessionsService.getInviteInfo(id);
    return { success: true, data: result };
  }

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

  @SkipThrottle({ default: true, auth: true, signup: true })
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

  // ── DELETE /api/sessions/:id ──────────────────────────
  // 사장님 시연 피드백(2026-05-13) 반영: 잘못 만든 세션 삭제 기능.
  // 권한: 호스트만 (assertHost) / 상태: WAITING|DONE 만 허용.
  // 트랜잭션: delete_session_cascade RPC 로 5개 테이블 일괄 정리.
  @Delete(':id')
  async deleteSession(
    @Req() req: AuthedRequest,
    @Param('id') id: string,
  ) {
    const result = await this.sessionsService.deleteSession(
      id,
      req.user.userId,
    );
    return { success: true, data: result };
  }

  @SkipThrottle({ default: true, auth: true, signup: true })
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
