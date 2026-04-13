import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 토스페이먼츠 결제 승인/조회 비즈니스 로직
//
// 티켓: CORE-10(결제 시스템 연동), CU-19(결제 호출/완료)
//
// ⚠️ 토스페이먼츠 v2 SDK 기준으로 작성.
//   - 결제창/결제위젯에서 받은 paymentKey를 이 서버에서
//     /v1/payments/confirm 으로 승인 요청해야 실제 결제가 완료됨
//   - 프론트만으로는 "결제 요청" 상태까지만 진행되고,
//     반드시 백엔드에서 시크릿 키로 최종 승인해야 함 (보안)
//
// 문서: https://docs.tosspayments.com/guides/v2/payment-widget/integration
// ══════════════════════════════════════════════════════════

export interface ConfirmPaymentDto {
  paymentKey: string; // 토스가 발급한 결제 고유 키
  orderId: string;    // 우리 서버가 발급한 주문 UUID (위젯에 넘긴 값과 동일)
  amount: number;     // 결제 금액 (위변조 검증용)
}

@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    private readonly supabase: SupabaseService,
    private readonly configService: ConfigService,
  ) {}

  // ── POST /api/payments/confirm — 결제 승인 ──────────────
  // 프론트가 결제위젯으로 결제를 "요청"한 뒤 리다이렉트되면
  // 쿼리스트링으로 paymentKey/orderId/amount를 받고,
  // 이 엔드포인트로 넘기면 우리 서버가 토스에 최종 승인을 요청한다.
  async confirmPayment(dto: ConfirmPaymentDto) {
    // ── 1. 주문 존재 확인 + 금액 위변조 검증 ──────────────
    // 프론트에서 amount를 조작해도 DB의 total_price와 다르면 거부
    const { data: order, error: orderError } = await this.supabase.client
      .from('orders')
      .select('id, status, total_price, session_id, user_id')
      .eq('id', dto.orderId)
      .single();

    if (orderError || !order) {
      throw new NotFoundException('주문을 찾을 수 없습니다.');
    }

    if (Number(order.total_price) !== Number(dto.amount)) {
      this.logger.warn(
        `결제 금액 불일치: order=${order.total_price}, req=${dto.amount}`,
      );
      throw new BadRequestException('결제 금액이 주문 금액과 다릅니다.');
    }

    if (order.status === 'PAID') {
      // 이미 승인된 주문 — 중복 호출은 조용히 성공 처리
      return {
        alreadyPaid: true,
        orderId: order.id,
        status: 'PAID',
      };
    }

    // ── 2. 토스 결제 승인 API 호출 ─────────────────────────
    const secretKey = this.configService.getOrThrow<string>('TOSS_SECRET_KEY');
    const apiBase =
      this.configService.get<string>('TOSS_API_BASE_URL') ??
      'https://api.tosspayments.com';

    // 토스 Basic Auth: base64(secretKey + ":")
    // 콜론 뒤에 암호가 없지만 콜론 자체는 반드시 포함해야 함
    const authHeader =
      'Basic ' + Buffer.from(secretKey + ':').toString('base64');

    let tossResponse: any;
    try {
      const res = await fetch(`${apiBase}/v1/payments/confirm`, {
        method: 'POST',
        headers: {
          Authorization: authHeader,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          paymentKey: dto.paymentKey,
          orderId: dto.orderId,
          amount: dto.amount,
        }),
      });

      tossResponse = await res.json();

      if (!res.ok) {
        // 토스가 에러를 반환한 경우 — message/code를 그대로 올려보냄
        this.logger.error(
          `토스 승인 실패: ${JSON.stringify(tossResponse)}`,
        );
        throw new BadRequestException(
          tossResponse?.message ?? '토스 결제 승인에 실패했습니다.',
        );
      }
    } catch (err: any) {
      if (err instanceof BadRequestException) throw err;
      this.logger.error(`토스 API 호출 오류: ${err?.message}`);
      throw new BadRequestException('토스 결제 서버와 통신에 실패했습니다.');
    }

    // ── 3. 주문 상태를 PAID로 변경 + paymentKey 저장 ──────
    const { error: updateError } = await this.supabase.client
      .from('orders')
      .update({
        status: 'PAID',
        payment_key: dto.paymentKey,
      })
      .eq('id', dto.orderId);

    if (updateError) {
      // 토스 승인은 성공했는데 DB 업데이트 실패 — 로그 남기고 경고
      this.logger.error(`주문 상태 업데이트 실패: ${updateError.message}`);
    }

    return {
      alreadyPaid: false,
      orderId: dto.orderId,
      status: 'PAID',
      paymentKey: dto.paymentKey,
      method: tossResponse?.method,
      approvedAt: tossResponse?.approvedAt,
      totalAmount: tossResponse?.totalAmount,
    };
  }
}
