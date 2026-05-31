import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import {
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  MaxLength,
  Min,
  ValidateIf,
} from 'class-validator';
// 2026-05-13 SkipThrottle: POS 단말이 주문 목록/통계를 폴링하면서 글로벌
//   throttler(분당 100) 한도를 빠르게 소모해 429 유발. 폴링성 GET 만 제외하고
//   상태 변경(PATCH)·취소(POST)는 보안 유지 위해 throttle 적용 그대로 둠.
import { SkipThrottle } from '@nestjs/throttler';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { assertPosAccessTo } from '../auth/pos-ownership.util';
import type { AuthedRequestUser } from '../auth/jwt.strategy';
import { PosService } from './pos.service';

// 2026-05-12 추가: req.user 타입 보강 — passport 가 주입한 사용자 객체.
type AuthedRequest = { user: AuthedRequestUser };

// 2026-05-31 WOW2: multer 의 Express.Multer.File 타입을 우리 서비스 시그니처에 맞게
//   재선언. @types/multer 미설치 환경에서도 빌드 통과시키기 위한 안전 타입.
interface UploadedPhotoFile {
  buffer: Buffer;
  mimetype: string;
  originalname: string;
  size: number;
}

// ══════════════════════════════════════════════════════════
// 파일 역할: 점주앱/POS HTTP 엔드포인트
//
// 엔드포인트 (정식 + 별칭):
//   GET   /api/pos/restaurants/:id/orders   — 식당별 주문 목록 (OW-10) [정식]
//   GET   /api/pos/orders/:restaurantId     — 위와 동일 (LSPOS 명세 호환 별칭)
//   GET   /api/pos/restaurants/:id/stats    — 결제 상태 통계 (POS-08) [정식]
//   GET   /api/pos/orders/:restaurantId/stats — 위와 동일 (LSPOS 명세 호환 별칭)
//   PATCH /api/pos/orders/:id/status        — 주문 상태 변경
//   POST  /api/pos/orders/:id/cancel        — 취소/환불 (POS-09)
//
// 별칭 라우트 추가 배경 (2026-05-12):
//   LSPOS POS_BUILD_GUIDE 명세는 `/pos/orders/:restaurantId` 형식이지만
//   본 백엔드는 RESTful 한 `/pos/restaurants/:id/orders` 로 먼저 구현됨.
//   기존 사장 홈(우리 owner_home_screen) 과 LSPOS 둘 다 깨지지 않게 둘 다 동작하도록.
// ══════════════════════════════════════════════════════════

// 2026-05-13 보안 패치: status 는 정해진 ENUM 값만 허용, reason 길이 제한
// 2026-05-15 자율 E2E 회귀 fix: 사장님 결정 ENUM 5단계 (PAID/ACCEPTED/PREPARING/READY/COMPLETED)
//   기존 매트릭스는 ACCEPTED 가 누락되어 PAID → ACCEPTED 전이 시 400 발생.
//   POS DTO 에 ACCEPTED 추가 (CANCELLED 는 별도 cancel 엔드포인트가 담당하므로 제외).
class UpdatePosOrderStatusDto {
  @IsIn(['ACCEPTED', 'PREPARING', 'READY', 'COMPLETED'])
  status: string;
}

class CancelOrderDto {
  @IsOptional() @IsString() @MaxLength(500) reason?: string;
}

// 2026-05-31 WOW#1: 사장님 "오늘의 한 줄" 입력 DTO.
//
// note 값:
//   · string (≤200자): 노출할 문구 (예: "비 오니까 얼큰순두부 강추 🌧")
//   · null            : 명시적 초기화 — 노출 중지
//
// 검증 규칙:
//   · null 허용을 위해 @ValidateIf 로 null 일 때 IsString/MaxLength 를 건너뜀.
//   · 200자 제한은 UI 와 동일 — 추천 카드 노란 띠가 두 줄 이상 늘어나면 가독성 저하.
class UpdateTodaysNoteDto {
  @ValidateIf((_o, v) => v !== null)
  @IsString({ message: 'note 는 문자열 또는 null 이어야 합니다.' })
  @MaxLength(200, { message: 'note 는 200자 이내여야 합니다.' })
  note!: string | null;
}

// 2026-05-31 POS-13: Toss POS 시뮬 결제 DTO.
//
// method:
//   · CARD — POS 단말 토스 카드 결제 (시뮬)
//   · CASH — POS 현금 수납 (사장이 현장에서 받은 금액)
//
// receivedAmount:
//   · CASH 일 때만 의미. 사장이 받은 금액(원). LSPOS 가 거스름돈 = 받은 금액 - 총액
//     으로 사용자에게 즉시 표시. DB 에는 저장 X (시연 임팩트 작음).
//   · 음수 방어 위해 Min(0). 옵션.
class TossPosChargeDto {
  @IsIn(['CARD', 'CASH'], {
    message: "method 는 'CARD' 또는 'CASH' 이어야 합니다.",
  })
  method!: 'CARD' | 'CASH';

  @IsOptional()
  @IsNumber({}, { message: 'receivedAmount 는 숫자여야 합니다.' })
  @Min(0, { message: 'receivedAmount 는 0 이상이어야 합니다.' })
  receivedAmount?: number;
}

@Controller('pos')
@UseGuards(JwtAuthGuard)
export class PosController {
  constructor(private readonly posService: PosService) {}

  // ── OW-10: 식당별 주문 목록 (정식 경로) ───────────────
  // 권한: POS 토큰의 매장 ID 와 path 매장 ID 일치 필수 (2026-05-12 박검토A)
  // 폴링 엔드포인트 → 모든 throttler 제외 (default/auth/signup 전부)
  @SkipThrottle({ default: true, auth: true, signup: true })
  @Get('restaurants/:id/orders')
  async getOrders(
    @Req() req: AuthedRequest,
    @Param('id') restaurantId: string,
    @Query('status') status?: string,
  ) {
    assertPosAccessTo(req.user, restaurantId);
    const result = await this.posService.getOrdersByRestaurant(
      restaurantId,
      status,
    );
    return { success: true, data: result };
  }

  // ── 별칭: LSPOS POS_BUILD_GUIDE 명세 호환 ─────────────
  @SkipThrottle({ default: true, auth: true, signup: true })
  @Get('orders/:restaurantId')
  async getOrdersAlias(
    @Req() req: AuthedRequest,
    @Param('restaurantId') restaurantId: string,
    @Query('status') status?: string,
  ) {
    return this.getOrders(req, restaurantId, status);
  }

  // ── POS-08: 결제 상태 통계 (정식 경로) ────────────────
  @SkipThrottle({ default: true, auth: true, signup: true })
  @Get('restaurants/:id/stats')
  async getStats(
    @Req() req: AuthedRequest,
    @Param('id') restaurantId: string,
  ) {
    assertPosAccessTo(req.user, restaurantId);
    const result = await this.posService.getPaymentStats(restaurantId);
    return { success: true, data: result };
  }

  // ── 별칭: LSPOS POS_BUILD_GUIDE 명세 호환 ─────────────
  @SkipThrottle({ default: true, auth: true, signup: true })
  @Get('orders/:restaurantId/stats')
  async getStatsAlias(
    @Req() req: AuthedRequest,
    @Param('restaurantId') restaurantId: string,
  ) {
    return this.getStats(req, restaurantId);
  }

  // ══════════════════════════════════════════════════════════
  // ── OW-10: 결제 내역 조회 (2026-05-31) ──
  //
  // 라우트:
  //   GET /api/pos/restaurants/:id/payment-history?dateFrom=...&dateTo=...
  //
  // 쿼리:
  //   · dateFrom — ISO 8601 (예: 2026-05-31T00:00:00.000Z). 옵션. 미지정=무제한.
  //   · dateTo   — ISO 8601. 옵션.
  //   ※ "오늘/어제/주간/월간" 분기는 클라이언트(Flutter) 가 칩별로 변환해 전달.
  //
  // 권한:
  //   JwtAuthGuard 통과 후 assertPosAccessTo — 토큰의 매장 ID 일치 필수.
  //
  // 폴링성 GET → SkipThrottle 적용 (사장 화면 진입 시 dateFilter 변경마다 호출).
  // ══════════════════════════════════════════════════════════
  @SkipThrottle({ default: true, auth: true, signup: true })
  @Get('restaurants/:id/payment-history')
  async getPaymentHistory(
    @Req() req: AuthedRequest,
    @Param('id') restaurantId: string,
    @Query('dateFrom') dateFrom?: string,
    @Query('dateTo') dateTo?: string,
  ) {
    assertPosAccessTo(req.user, restaurantId);
    const result = await this.posService.getPaymentHistory(
      restaurantId,
      dateFrom,
      dateTo,
    );
    return { success: true, data: result };
  }

  // ══════════════════════════════════════════════════════════
  // ── OW-10: 환불 시뮬레이션 (2026-05-31) ──
  //
  // 라우트:
  //   POST /api/pos/orders/:id/refund-sim
  //
  // 본문: 없음 (status 만 REFUNDED 로 변경).
  //
  // 권한:
  //   orderId → restaurant_id 사전 조회 후 assertPosAccessTo.
  //   다른 매장 주문에 환불 시뮬을 거는 우회 시도 차단.
  //
  // 실제 토스 cancel API 호출 X — 데모/시연 환경 매출 차감 시뮬용.
  // 정식 환불은 POST /api/pos/orders/:id/cancel 사용.
  // ══════════════════════════════════════════════════════════
  @Post('orders/:id/refund-sim')
  async refundSim(
    @Req() req: AuthedRequest,
    @Param('id') orderId: string,
  ) {
    const restaurantId =
      await this.posService.getRestaurantIdByOrderId(orderId);
    assertPosAccessTo(req.user, restaurantId);
    const result = await this.posService.refundSim(orderId);
    return { success: true, data: result };
  }

  // ── 주문 상태 변경 (PREPARING → READY 등) ────────────
  // 권한: orderId → restaurant_id 사전 조회 후 토큰 일치 검증 (2026-05-13 보강)
  @Patch('orders/:id/status')
  async updateStatus(
    @Req() req: AuthedRequest,
    @Param('id') orderId: string,
    @Body() dto: UpdatePosOrderStatusDto,
  ) {
    const restaurantId = await this.posService.getRestaurantIdByOrderId(orderId);
    assertPosAccessTo(req.user, restaurantId);
    const result = await this.posService.updateOrderStatus(orderId, dto.status);
    return { success: true, data: result };
  }

  // ── POS-09: 취소/환불 ────────────────────────────────
  // 권한: orderId → restaurant_id 사전 조회 후 토큰 일치 검증 (2026-05-13 보강)
  @Post('orders/:id/cancel')
  async cancelOrder(
    @Req() req: AuthedRequest,
    @Param('id') orderId: string,
    @Body() dto: CancelOrderDto,
  ) {
    const restaurantId = await this.posService.getRestaurantIdByOrderId(orderId);
    assertPosAccessTo(req.user, restaurantId);
    const result = await this.posService.cancelOrder(orderId, dto.reason);
    return { success: true, data: result };
  }

  // ══════════════════════════════════════════════════════════
  // ── 2026-05-31 WOW#2: 사장 라이브 카메라 1장 ──
  //
  // 라우트:
  //   POST /api/pos/orders/:id/completion-photo
  //
  // 본문 (multipart/form-data):
  //   - field name: "photo" (image/jpeg | png | webp, 5MB 이하)
  //
  // 권한:
  //   · JwtAuthGuard 통과 후 orderId → restaurant_id 사전 조회
  //   · assertPosAccessTo 로 POS 토큰의 매장 ID 일치 검증
  //   · 다른 매장 주문에 사진 첨부 차단
  //
  // 동작:
  //   1) Supabase Storage `order-photos` 버킷에 업로드 (service_role)
  //   2) orders.completion_photo_url 컬럼 갱신
  //   3) 손님에게 FCM data 푸시 (type=COMPLETION_PHOTO, url=publicUrl)
  //
  // 응답:
  //   { success: true, data: { id, completionPhotoUrl, updatedAt } }
  // ══════════════════════════════════════════════════════════
  @Post('orders/:id/completion-photo')
  @UseInterceptors(
    FileInterceptor('photo', {
      limits: {
        fileSize: 5 * 1024 * 1024, // 5MB hard limit (multer 단 cut)
      },
    }),
  )
  async uploadCompletionPhoto(
    @Req() req: AuthedRequest,
    @Param('id') orderId: string,
    @UploadedFile() photo: UploadedPhotoFile,
  ) {
    // 권한 검증 — 다른 매장 주문에 사진 못 붙이도록
    const restaurantId =
      await this.posService.getRestaurantIdByOrderId(orderId);
    assertPosAccessTo(req.user, restaurantId);

    const result = await this.posService.saveCompletionPhoto(orderId, photo);
    return { success: true, data: result };
  }

  // ══════════════════════════════════════════════════════════
  // ── 2026-05-31 WOW#1: 사장님 "오늘의 한 줄" 업데이트 ──
  //
  // 라우트:
  //   PATCH /api/pos/restaurants/:id/todays-note
  //
  // 본문:
  //   { "note": "비 오니까 얼큰순두부 강추 🌧" }   → 200자 이하 문자열
  //   { "note": null }                              → 노출 중단 (DB NULL)
  //
  // 권한:
  //   · JwtAuthGuard 통과 후 assertPosAccessTo 로 POS 토큰의 매장 ID 와
  //     path 의 식당 ID 가 일치해야만 변경 허용.
  //   · 다른 매장 한 줄을 수정/덮어쓰는 우회 시도 차단.
  //
  // 응답:
  //   { success: true, data: { restaurantId, todaysNote } }
  // ══════════════════════════════════════════════════════════
  @Patch('restaurants/:id/todays-note')
  async updateTodaysNote(
    @Req() req: AuthedRequest,
    @Param('id') restaurantId: string,
    @Body() dto: UpdateTodaysNoteDto,
  ) {
    // 매장 권한 검증 — POS JWT 가 발급된 식당과 path 식당 ID 일치 필수.
    assertPosAccessTo(req.user, restaurantId);

    // 빈 문자열 / 공백만 입력 시 명시적으로 null 로 normalize.
    // (DB 와 손님 응답이 일관되게 "미입력" 으로 처리되어 노란 띠가 사라짐)
    const normalized =
      typeof dto.note === 'string' && dto.note.trim().length > 0
        ? dto.note.trim()
        : null;

    const result = await this.posService.updateTodaysNote(
      restaurantId,
      normalized,
    );
    return { success: true, data: result };
  }

  // ══════════════════════════════════════════════════════════
  // ── POS-13: Toss POS 시뮬 결제 (2026-05-31) ──
  //
  // 라우트:
  //   POST /api/pos/orders/:id/toss-pos-charge
  //
  // 본문:
  //   {
  //     "method": "CARD" | "CASH",
  //     "receivedAmount": 50000   // CASH 시 사장이 받은 금액 (옵션)
  //   }
  //
  // 동작:
  //   · 주문 status = 'PAID' + payment_method = 'POS_TOSS' | 'POS_CASH' 업데이트
  //   · 이미 PAID 이상이면 멱등 — 새 UPDATE 없이 현재 상태 반환
  //   · CANCELLED/REFUNDED 는 거절(500)
  //
  // 응답:
  //   { success: true, data: { orderId, status, paymentMethod, approvedAt } }
  //
  // 보안:
  //   · JwtAuthGuard 통과 후 orderId → restaurant_id 사전 조회
  //   · assertPosAccessTo 로 POS 토큰의 매장 ID 일치 검증
  //   · 다른 매장 주문에 결제 처리 시도 차단
  //
  // 단계:
  //   본 티켓은 P1 시연 시뮬 단계 — 실제 토스 POS API 미연동.
  //   서비스 메서드명(chargeViaPosToss) 그대로 두어 향후 실 API 통합 시
  //   메서드 내부 구현만 교체하면 됨 (인터페이스 호환).
  // ══════════════════════════════════════════════════════════
  @Post('orders/:id/toss-pos-charge')
  async chargeViaPosToss(
    @Req() req: AuthedRequest,
    @Param('id') orderId: string,
    @Body() dto: TossPosChargeDto,
  ) {
    // 권한 검증 — 다른 매장 주문에 결제 처리 못 하도록.
    const restaurantId =
      await this.posService.getRestaurantIdByOrderId(orderId);
    assertPosAccessTo(req.user, restaurantId);

    const result = await this.posService.chargeViaPosToss(
      orderId,
      dto.method,
      dto.receivedAmount,
    );
    return { success: true, data: result };
  }
}
