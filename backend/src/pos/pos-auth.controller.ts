import { Body, Controller, Param, Post } from '@nestjs/common';
import { IsOptional, IsString } from 'class-validator';
import { PosAuthService } from './pos-auth.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: POS 단말 로그인 HTTP 엔드포인트 (LSPOS 연동용)
//
// 엔드포인트:
//   POST /api/pos/login/:restaurantId  — 식당 고유번호로 POS JWT 발급
//
// 인증:
//   본 엔드포인트는 인증 없이 호출됨 (단말 로그인 시점 자체이므로).
//   전체 글로벌 가드를 쓰지 않으므로 JwtAuthGuard 적용 불필요.
// ══════════════════════════════════════════════════════════

class PosLoginDto {
  /// 단말 식별 라벨 (예: "카운터1", "주방POS") — 선택. 운영 로그용
  @IsOptional() @IsString() terminalName?: string;
}

@Controller('pos')
export class PosAuthController {
  constructor(private readonly posAuthService: PosAuthService) {}

  // ── POS 단말 로그인 ────────────────────────────────────
  // restaurantId 가 유효하면 type=POS JWT 발급. LSPOS 의 useAuth 가
  // localStorage 에 accessToken 저장 → client.ts 가 Bearer 헤더 자동 주입.
  @Post('login/:restaurantId')
  async login(
    @Param('restaurantId') restaurantId: string,
    @Body() dto: PosLoginDto,
  ) {
    const result = await this.posAuthService.login(
      restaurantId,
      dto.terminalName,
    );
    return { success: true, data: result };
  }
}
