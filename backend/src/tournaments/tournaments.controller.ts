// ══════════════════════════════════════════════════════════
// 파일 역할: 토너먼트 HTTP 컨트롤러 (WOW#6 결과 적재 + WOW#9 트렌딩)
//
// 엔드포인트:
//   POST /api/tournaments
//     - 토너먼트 우승 결과 1건 기록.
//     - body: { mode, winnerRestaurantId?, winnerMenuId?, candidateCount, durationMs }
//     - 201 Created + { id }
//
//   GET /api/tournaments/trending?limit=5&days=7
//     - 최근 N일 동안 우승 빈도 TOP N 식당.
//     - 응답: [{ restaurantId, name, category, imageUrl, winCount }, ...]
//     - 데이터 0개 → 빈 배열 그대로 반환 (프론트가 섹션 자체를 숨김).
//
// 인증 정책:
//   모든 라우트 @UseGuards(JwtAuthGuard) — 익명 호출 차단.
//   POST 의 user_id 는 req.user.userId (JWT payload) 로 자동 채움.
//
// 입력 검증:
//   class-validator 데코레이터 + main.ts 의 글로벌 ValidationPipe 가
//   런타임에 자동 적용 (friends.controller 와 동일 패턴).
//
// 에러 시나리오:
//   - mode 누락/잘못된 값                       → 400
//   - mode='restaurant' 인데 winnerRestaurantId 없음 → 400
//   - mode='menu' 인데 winnerMenuId 없음        → 400
//   - JWT 누락/만료                              → 401
// ══════════════════════════════════════════════════════════

import {
  BadRequestException,
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  Min,
} from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import {
  TournamentsService,
  TrendingRestaurantDto,
} from './tournaments.service';

// JWT payload 가 주입된 Express Request 타입 (friends.controller 와 동일).
type AuthedRequest = { user: { userId: string } };

// ── POST body DTO ──────────────────────────────────────────
class CreateTournamentResultDto {
  // 'restaurant' | 'menu' 두 가지만 허용. 외 값은 400.
  @IsString()
  @IsIn(['restaurant', 'menu'])
  mode!: 'restaurant' | 'menu';

  // 식당 모드면 필수, 메뉴 모드면 메뉴의 소속 식당 ID (둘 다 채워주는 게 트렌딩 집계에 안전).
  @IsOptional()
  @IsUUID()
  winnerRestaurantId?: string;

  // 메뉴 모드일 때만 채움. 식당 모드면 undefined.
  @IsOptional()
  @IsUUID()
  winnerMenuId?: string;

  // 시작 후보 수. 비정상적으로 큰 값은 차단 (이상치 분석 노이즈 방지).
  @IsOptional()
  @IsInt()
  @Min(2)
  @Max(64)
  candidateCount?: number;

  // 우승까지 걸린 ms. 음수 차단, 1시간 초과는 분명한 비정상치(앱 백그라운드 등) → 차단.
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(60 * 60 * 1000)
  durationMs?: number;
}

@Controller('tournaments')
@UseGuards(JwtAuthGuard)
export class TournamentsController {
  constructor(private readonly tournamentsService: TournamentsService) {}

  // ── POST /api/tournaments ───────────────────────────────
  // 우승 결과 1건 INSERT. 모드별 winnerXxxId 누락 시 400.
  @Post()
  @HttpCode(HttpStatus.CREATED)
  async create(
    @Req() req: AuthedRequest,
    @Body() dto: CreateTournamentResultDto,
  ) {
    // 모드별 필수 필드 검증.
    //   - restaurant : winnerRestaurantId 필수.
    //   - menu       : winnerMenuId 필수 (winnerRestaurantId 는 권장).
    if (dto.mode === 'restaurant' && !dto.winnerRestaurantId) {
      throw new BadRequestException(
        '식당 토너먼트는 winnerRestaurantId 가 필요해요.',
      );
    }
    if (dto.mode === 'menu' && !dto.winnerMenuId) {
      throw new BadRequestException(
        '메뉴 토너먼트는 winnerMenuId 가 필요해요.',
      );
    }

    const inserted = await this.tournamentsService.createResult({
      userId: req.user.userId,
      mode: dto.mode,
      winnerRestaurantId: dto.winnerRestaurantId ?? null,
      winnerMenuId: dto.winnerMenuId ?? null,
      candidateCount: dto.candidateCount ?? null,
      durationMs: dto.durationMs ?? null,
    });
    return { success: true, data: { id: inserted.id } };
  }

  // ── GET /api/tournaments/trending ───────────────────────
  // 최근 N일 동안 우승 빈도 상위 N개 식당.
  // 쿼리스트링은 모두 옵셔널 + 안전 범위로 clamp.
  @Get('trending')
  async trending(
    @Query('limit') limit?: string,
    @Query('days') days?: string,
  ): Promise<{ success: true; data: TrendingRestaurantDto[] }> {
    // 문자열 → 숫자 변환 + 안전 clamp.
    // limit : 1~20 (기본 5). 너무 크면 홈 가로 스크롤 UX 가 망가짐.
    // days  : 1~30 (기본 7). 30일 이상은 트렌딩 의미가 옅어짐.
    const limitN = clampInt(parseInt(limit ?? '5', 10), 1, 20, 5);
    const daysN = clampInt(parseInt(days ?? '7', 10), 1, 30, 7);

    const result = await this.tournamentsService.getTrending({
      limit: limitN,
      days: daysN,
    });
    return { success: true, data: result };
  }
}

// ── 숫자 안전 변환 ────────────────────────────────────────
// parseInt 가 NaN 을 반환할 수 있어 fallback 처리 + min/max clamp.
function clampInt(
  value: number,
  min: number,
  max: number,
  fallback: number,
): number {
  if (!Number.isFinite(value)) return fallback;
  if (value < min) return min;
  if (value > max) return max;
  return Math.floor(value);
}
