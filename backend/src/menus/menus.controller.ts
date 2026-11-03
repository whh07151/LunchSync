import {
  Controller,
  ForbiddenException,
  Get,
  Param,
  Req,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import type { AuthedRequestUser } from '../auth/jwt.strategy';
import {
  CheckAllergensResult,
  MenusService,
} from './menus.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: CORE-09 메뉴 알레르기 충돌 검증 HTTP 컨트롤러
//
// 엔드포인트:
//   GET /api/menus/restaurant/:restaurantId/check-allergens?userId=
//     - 사용자가 등록한 알레르기와 식당 메뉴들의 알레르기 교집합 조회.
//     - 응답:
//         { success: true,
//           data: {
//             conflicts: [
//               { menuId, name, matchedAllergens: ['nuts', 'egg'] },
//               ...
//             ]
//           } }
//     - 사용자 알레르기가 비어있으면 conflicts: [] 즉시 반환.
//     - 식당이 존재하지 않으면 404.
//
// 인증:
//   JwtAuthGuard — 로그인된 사용자만 호출 가능.
//   userId 는 쿼리스트링으로 받지만, 추후 확장에서 JWT payload 의 userId 와
//   대조해 본인 외 다른 사용자 알레르기 조회를 차단하는 가드 추가 여지.
//
// 별도 모듈로 분리한 이유:
//   - 기존 RestaurantsModule 은 식당 카드/상세/메뉴 목록 등 다수의 책임을
//     이미 짊어지고 있음. 알레르기 검증은 사용자(users) 컬럼까지 참조해야
//     하므로 책임이 다름 → 신규 MenusModule 로 분리.
//   - 추후 메뉴 추천/상세 등 menus 도메인 엔드포인트가 더 늘어날 때
//     자연스러운 확장 지점이 된다.
// ══════════════════════════════════════════════════════════

@Controller('menus')
@UseGuards(JwtAuthGuard)
export class MenusController {
  constructor(private readonly menusService: MenusService) {}

  // ── GET /api/menus/restaurant/:restaurantId/check-allergens ──
  // 사용자 알레르기 ∩ 메뉴 알레르기 교집합 조회.
  //
  // [입력 검증]
  //   - restaurantId : URL path 필수.
  //   - userId       : 쿼리스트링 필수. 누락/빈 문자열 시 400.
  //
  // [정상 응답]
  //   { success: true, data: { conflicts: [...] } }
  //
  // [에러]
  //   - 400 : userId 누락
  //   - 401 : JWT 누락/만료
  //   - 404 : 식당이 존재하지 않음 (서비스에서 NotFoundException)
  //   - 500 : DB 조회 실패 시 일반 에러
  @Get('restaurant/:restaurantId/check-allergens')
  async checkAllergens(
    @Req() req: { user: AuthedRequestUser },
    @Param('restaurantId') restaurantId: string,
  ): Promise<{ success: true; data: CheckAllergensResult }> {
    if (req.user.type !== 'USER' || !req.user.userId) {
      throw new ForbiddenException('사용자 계정으로만 조회할 수 있습니다.');
    }
    const result = await this.menusService.checkAllergens(
      restaurantId,
      req.user.userId,
    );
    return { success: true, data: result };
  }
}
