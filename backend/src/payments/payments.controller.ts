import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';
import { IsInt, IsNotEmpty, IsString, Min } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import type { AuthedRequestUser } from '../auth/jwt.strategy';
import { PaymentsService } from './payments.service';

type AuthedRequest = { user: AuthedRequestUser };

// ══════════════════════════════════════════════════════════
// 파일 역할: 토스페이먼츠 결제 승인 HTTP 엔드포인트
//
// 엔드포인트:
//   POST /api/payments/confirm — 결제 승인 (CU-19)
//
// 흐름:
//   1) 프론트가 결제위젯으로 결제 요청 → 토스가 성공 URL로 리다이렉트
//   2) 성공 화면이 paymentKey/orderId/amount를 받아 이 엔드포인트 호출
//   3) 백엔드가 시크릿 키로 토스 /v1/payments/confirm 호출
//   4) 성공하면 orders.status = PAID 로 업데이트
// ══════════════════════════════════════════════════════════

class ConfirmPaymentBodyDto {
  @IsString() @IsNotEmpty() paymentKey: string;
  @IsString() @IsNotEmpty() orderId: string;
  @IsInt() @Min(0) amount: number;
}

@Controller('payments')
@UseGuards(JwtAuthGuard)
export class PaymentsController {
  constructor(private readonly paymentsService: PaymentsService) {}

  // ── CU-19: 결제 승인 ──────────────────────────────────
  // 권한: 주문 소유자 본인만 승인 호출 가능 (2026-05-12 박검토A 긴급)
  //   다른 사용자의 orderId 로 임의 승인 호출하면 BadRequest 로 차단.
  //   service 단에 requesterUserId 인자 추가 → DB 의 order.user_id 와 일치 검증.
  @Post('confirm')
  async confirm(
    @Req() req: AuthedRequest,
    @Body() dto: ConfirmPaymentBodyDto,
  ) {
    const result = await this.paymentsService.confirmPayment(
      dto,
      req.user?.userId,
    );
    return { success: true, data: result };
  }
}
