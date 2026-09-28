import {
  BadGatewayException,
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
  UnauthorizedException,
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
  orderId: string; // 우리 서버가 발급한 주문 UUID (위젯에 넘긴 값과 동일)
  amount: number; // 결제 금액 (위변조 검증용)
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
  //
  // 권한 (2026-05-12 박검토A 긴급):
  //   requesterUserId 인자가 들어오면 order.user_id 와 일치 검증.
  //   다른 사용자의 orderId 로 임의 승인 차단.
  async confirmPayment(dto: ConfirmPaymentDto, requesterUserId?: string) {
    // ── 1. 주문 존재 확인 + 금액 위변조 검증 + 본인 검증 ──
    // 프론트에서 amount를 조작해도 DB의 total_price와 다르면 거부
    const { data: order, error: orderError } = await this.supabase.client
      .from('orders')
      .select(
        'id, status, total_price, session_id, user_id, payment_key, payment_method',
      )
      .eq('id', dto.orderId)
      .single();

    if (orderError || !order) {
      throw new NotFoundException('주문을 찾을 수 없습니다.');
    }

    // 본인 주문만 승인 가능 — 다른 사용자 orderId 로 임의 승인 차단
    if (!requesterUserId) {
      throw new UnauthorizedException('인증 정보가 없습니다.');
    }
    if (order.user_id !== requesterUserId) {
      throw new ForbiddenException('본인의 주문만 결제 승인할 수 있습니다.');
    }

    if (Number(order.total_price) !== Number(dto.amount)) {
      this.logger.warn('PAYMENT_AMOUNT_MISMATCH');
      throw new BadRequestException('결제 금액이 주문 금액과 다릅니다.');
    }

    // 이 엔드포인트는 Toss 결제창에서 돌아온 승인 정보만 처리한다.
    // CASH/CARD 주문을 여기서 승인하면 실제 결제수단과 매출 분류가 달라진다.
    if (order.payment_method !== 'TOSS') {
      throw new ConflictException({
        statusCode: 409,
        code: 'PAYMENT_METHOD_NOT_TOSS',
        message: '토스 결제로 생성된 주문만 이 경로에서 승인할 수 있습니다.',
        retryable: false,
        orderId: order.id,
      });
    }

    if (order.status === 'PAID') {
      if (order.payment_key !== dto.paymentKey) {
        throw new ConflictException({
          statusCode: 409,
          code: 'PAYMENT_KEY_MISMATCH',
          message:
            '이미 결제된 주문의 결제 키가 요청과 일치하지 않습니다. 결제 내역을 확인해주세요.',
          retryable: false,
          orderId: order.id,
        });
      }

      // 이미 승인된 주문 — 중복 호출은 조용히 성공 처리
      return {
        alreadyPaid: true,
        reconciled: true,
        orderId: order.id,
        status: 'PAID',
        paymentKey: order.payment_key,
      };
    }

    if (order.status !== 'PENDING') {
      throw new ConflictException({
        statusCode: 409,
        code: 'ORDER_NOT_PAYABLE',
        message: '결제할 수 없는 주문 상태입니다. 주문 상태를 확인해주세요.',
        retryable: false,
        orderId: order.id,
      });
    }

    // ── 2. 토스 결제 승인 API 호출 ─────────────────────────
    const secretKey = this.configService.getOrThrow<string>('TOSS_SECRET_KEY');
    const apiBase =
      this.configService.get<string>('TOSS_API_BASE_URL') ??
      'https://api.tosspayments.com';
    const configuredTimeoutMs = Number(
      this.configService.get<string>('TOSS_API_TIMEOUT_MS'),
    );
    const timeoutMs =
      Number.isInteger(configuredTimeoutMs) &&
      configuredTimeoutMs >= 100 &&
      configuredTimeoutMs <= 60_000
        ? configuredTimeoutMs
        : 10_000;

    // 토스 Basic Auth: base64(secretKey + ":")
    // 콜론 뒤에 암호가 없지만 콜론 자체는 반드시 포함해야 함
    const authHeader =
      'Basic ' + Buffer.from(secretKey + ':').toString('base64');
    const idempotencyKey = `lunchsync-confirm:${dto.orderId}`;

    let tossResponse: any;
    try {
      const res = await fetch(`${apiBase}/v1/payments/confirm`, {
        method: 'POST',
        headers: {
          Authorization: authHeader,
          'Content-Type': 'application/json',
          'Idempotency-Key': idempotencyKey,
        },
        body: JSON.stringify({
          paymentKey: dto.paymentKey,
          orderId: dto.orderId,
          amount: dto.amount,
        }),
        signal: AbortSignal.timeout(timeoutMs),
      });

      if (!res.ok) {
        try {
          tossResponse = await res.json();
        } catch {
          tossResponse = undefined;
        }

        if (tossResponse?.code === 'IDEMPOTENT_REQUEST_PROCESSING') {
          throw new ConflictException({
            statusCode: 409,
            code: 'IDEMPOTENT_REQUEST_PROCESSING',
            message:
              '같은 결제 요청이 처리 중입니다. 잠시 후 같은 정보로 다시 시도해주세요.',
            retryable: true,
            orderId: dto.orderId,
            paymentKey: dto.paymentKey,
          });
        }

        // 결제키나 응답 본문 전체를 로그에 남기지 않는다.
        this.logger.error(`PAYMENT_PROVIDER_CONFIRM_FAILED status=${res.status}`);
        if (res.status >= 500) {
          throw new ServiceUnavailableException({
            statusCode: 503,
            code: 'TOSS_SERVICE_UNAVAILABLE',
            message:
              '결제 승인 서버가 일시적으로 응답하지 않습니다. 같은 결제 정보로 다시 시도해주세요.',
            retryable: true,
            orderId: dto.orderId,
          });
        }
        throw new BadRequestException({
          statusCode: 400,
          code: 'TOSS_CONFIRM_REJECTED',
          message: '결제사에서 결제 승인을 완료하지 못했습니다.',
          retryable: false,
          orderId: dto.orderId,
        });
      }

      tossResponse = await res.json();
    } catch (err: any) {
      if (
        err instanceof BadRequestException ||
        err instanceof ConflictException ||
        err instanceof ServiceUnavailableException
      ) {
        throw err;
      }
      this.logger.error('PAYMENT_PROVIDER_CONFIRM_UNREACHABLE');
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: 'TOSS_COMMUNICATION_FAILED',
        message:
          '결제 승인 서버와 통신하지 못했습니다. 같은 결제 정보로 다시 시도해주세요.',
        retryable: true,
        orderId: dto.orderId,
      });
    }

    const paymentKeyMatches = tossResponse?.paymentKey === dto.paymentKey;
    const orderIdMatches = tossResponse?.orderId === dto.orderId;
    const amountMatches =
      Number(tossResponse?.totalAmount) === Number(dto.amount);
    const statusIsDone = tossResponse?.status === 'DONE';
    if (
      !paymentKeyMatches ||
      !orderIdMatches ||
      !amountMatches ||
      !statusIsDone
    ) {
      this.logger.error(
        'PAYMENT_PROVIDER_CONFIRM_MISMATCH ' +
          `paymentKeyMatch=${paymentKeyMatches} ` +
          `orderIdMatch=${orderIdMatches} ` +
          `amountMatch=${amountMatches} ` +
          `completed=${statusIsDone}`,
      );
      throw new BadGatewayException({
        statusCode: 502,
        code: 'TOSS_PAYMENT_MISMATCH',
        message:
          '결제 승인 응답이 주문 정보와 일치하지 않습니다. 결제 내역을 확인해주세요.',
        retryable: false,
        orderId: dto.orderId,
      });
    }

    // ── 3. 주문 상태를 PAID로 변경 + paymentKey 저장 ──────
    const { data: updatedOrder, error: updateError } =
      await this.supabase.client
        .from('orders')
        .update({
          status: 'PAID',
          payment_key: dto.paymentKey,
        })
        .eq('id', dto.orderId)
        .eq('status', 'PENDING')
        .select('id, status, payment_key')
        .maybeSingle();

    if (
      updateError ||
      !updatedOrder ||
      updatedOrder.status !== 'PAID' ||
      updatedOrder.payment_key !== dto.paymentKey
    ) {
      const { data: reconciledOrder } = await this.supabase.client
        .from('orders')
        .select('id, status, payment_key')
        .eq('id', dto.orderId)
        .single();

      if (
        reconciledOrder?.status === 'PAID' &&
        reconciledOrder.payment_key === dto.paymentKey
      ) {
        this.logger.warn('PAYMENT_STATUS_ALREADY_RECONCILED');
        return {
          alreadyPaid: true,
          reconciled: true,
          orderId: dto.orderId,
          status: 'PAID',
          paymentKey: dto.paymentKey,
          method: tossResponse?.method,
          approvedAt: tossResponse?.approvedAt,
          totalAmount: tossResponse?.totalAmount,
        };
      }

      // Toss 승인은 끝났지만 고객 취소가 PENDING → CANCELLED 전이를 먼저
      // 선점한 경우다. 결제된 채 취소 상태로 남기지 않도록 즉시 보상 환불한다.
      if (reconciledOrder?.status === 'CANCELLED') {
        try {
          await this.cancelPayment(
            dto.paymentKey,
            '주문 취소와 결제 승인 경합 자동 환불',
            dto.orderId,
          );
        } catch (compensationError: any) {
          this.logger.error('PAYMENT_CANCEL_RACE_COMPENSATION_FAILED');
          throw new ServiceUnavailableException({
            statusCode: 503,
            code: 'PAYMENT_APPROVED_CANCEL_RECONCILIATION_REQUIRED',
            message:
              '주문 취소와 동시에 결제가 승인됐고 자동 환불 완료를 확인하지 못했습니다. 재처리가 필요합니다.',
            retryable: true,
            reconciliationRequired: true,
            orderId: dto.orderId,
          });
        }

        this.logger.warn('PAYMENT_CANCEL_RACE_COMPENSATED');
        throw new ConflictException({
          statusCode: 409,
          code: 'PAYMENT_APPROVED_AFTER_CANCELLATION_REFUNDED',
          message:
            '주문 취소와 동시에 승인된 결제를 즉시 환불했습니다. 다시 결제하지 말고 주문 상태를 확인해주세요.',
          retryable: false,
          compensated: true,
          orderId: dto.orderId,
        });
      }

      this.logger.error('PAYMENT_ORDER_STATUS_PERSIST_FAILED');
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: 'PAYMENT_APPROVED_DB_SYNC_PENDING',
        message:
          '결제는 승인됐지만 주문 상태 저장을 확인하지 못했습니다. 같은 결제 정보로 다시 시도해주세요.',
        retryable: true,
        orderId: dto.orderId,
        paymentKey: dto.paymentKey,
      });
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

  // ── 결제 취소 / 환불 ──────────────────────────────────
  // 2026-05-15 사장님 발전 결정 (plan): 사장 거절 시 자동 환불.
  // 토스 v1/payments/{paymentKey}/cancel API 호출.
  //
  // 원자성 정책:
  //   - 환불 API 가 성공해야만 호출부(pos.cancelOrder)가 status 를 CANCELLED 로 변경
  //   - 본 메서드는 실패 시 예외 throw — 호출부에서 캐치해 status 미변경 처리
  //
  // 토스 cancel API 응답:
  //   200: { paymentKey, orderId, status:'CANCELED', cancels:[{ cancelAmount, ... }] }
  //   400/404: { code, message } — message 를 그대로 BadRequest 로 올림
  async cancelPayment(
    paymentKey: string,
    cancelReason: string = '점주 취소',
    orderId: string,
  ): Promise<{
    paymentKey: string;
    status: string;
    canceledAt?: string;
    cancelAmount?: number;
  }> {
    if (!paymentKey || paymentKey.trim().length === 0) {
      throw new BadRequestException('환불할 결제 키가 없어요.');
    }
    if (!orderId || orderId.trim().length === 0) {
      throw new BadRequestException('환불할 주문 ID가 없어요.');
    }

    const secretKey = this.configService.getOrThrow<string>('TOSS_SECRET_KEY');
    const apiBase =
      this.configService.get<string>('TOSS_API_BASE_URL') ??
      'https://api.tosspayments.com';
    const configuredTimeoutMs = Number(
      this.configService.get<string>('TOSS_API_TIMEOUT_MS'),
    );
    const timeoutMs =
      Number.isInteger(configuredTimeoutMs) &&
      configuredTimeoutMs >= 100 &&
      configuredTimeoutMs <= 60_000
        ? configuredTimeoutMs
        : 10_000;

    // 기존 confirmPayment 와 동일한 Basic Auth 패턴 (line 94~95)
    const authHeader =
      'Basic ' + Buffer.from(secretKey + ':').toString('base64');

    const idempotencyKey = `lunchsync-cancel:${orderId}`;
    let response: Response;
    try {
      response = await fetch(`${apiBase}/v1/payments/${paymentKey}/cancel`, {
        method: 'POST',
        headers: {
          Authorization: authHeader,
          'Content-Type': 'application/json',
          'Idempotency-Key': idempotencyKey,
        },
        body: JSON.stringify({
          cancelReason,
        }),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (err: any) {
      this.logger.error('PAYMENT_PROVIDER_REFUND_UNREACHABLE');
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: 'TOSS_REFUND_UNAVAILABLE',
        message:
          '결제사 환불 응답을 확인하지 못했습니다. 같은 주문으로 다시 시도해주세요.',
        retryable: true,
        orderId,
      });
    }

    let tossResponse: any;
    try {
      tossResponse = await response.json();
    } catch {
      this.logger.error(
        `PAYMENT_PROVIDER_REFUND_INVALID_JSON status=${response.status}`,
      );
      if (!response.ok && response.status >= 500) {
        throw new ServiceUnavailableException({
          statusCode: 503,
          code: 'TOSS_REFUND_UNAVAILABLE',
          message: '결제사 환불 서버가 일시적으로 응답하지 않습니다.',
          retryable: true,
          orderId,
        });
      }
      throw new BadGatewayException({
        statusCode: 502,
        code: 'TOSS_REFUND_INVALID_RESPONSE',
        message: '결제사 환불 응답을 확인할 수 없습니다.',
        retryable: true,
        orderId,
      });
    }

    if (!response.ok) {
      const providerCode =
        typeof tossResponse?.code === 'string' ? tossResponse.code : undefined;
      this.logger.error(`PAYMENT_PROVIDER_REFUND_REJECTED status=${response.status}`);
      if (providerCode === 'IDEMPOTENT_REQUEST_PROCESSING') {
        throw new ConflictException({
          statusCode: 409,
          code: 'IDEMPOTENT_REQUEST_PROCESSING',
          message: '같은 환불 요청이 처리 중입니다. 잠시 후 다시 시도해주세요.',
          retryable: true,
          orderId,
          providerCode,
        });
      }
      if (response.status >= 500) {
        throw new ServiceUnavailableException({
          statusCode: 503,
          code: 'TOSS_REFUND_UNAVAILABLE',
          message: '결제사 환불 서버가 일시적으로 응답하지 않습니다.',
          retryable: true,
          orderId,
          providerCode,
        });
      }
      throw new BadRequestException({
        statusCode: 400,
        code: 'TOSS_REFUND_REJECTED',
        message: '결제사에서 환불을 완료하지 못했습니다.',
        retryable: response.status >= 500,
        orderId,
        providerCode,
      });
    }

    // 최신 cancel 정보 추출 — cancels 배열의 마지막 항목이 가장 최근 취소
    const lastCancel = Array.isArray(tossResponse?.cancels)
      ? tossResponse.cancels[tossResponse.cancels.length - 1]
      : null;
    const paymentKeyMatches = tossResponse?.paymentKey === paymentKey;
    const orderIdMatches = tossResponse?.orderId === orderId;
    const paymentCanceled = tossResponse?.status === 'CANCELED';
    const cancelCompleted = lastCancel?.cancelStatus === 'DONE';
    const cancelAmount = Number(lastCancel?.cancelAmount);
    const cancelAmountValid = Number.isFinite(cancelAmount) && cancelAmount > 0;

    if (
      !paymentKeyMatches ||
      !orderIdMatches ||
      !paymentCanceled ||
      !cancelCompleted ||
      !cancelAmountValid
    ) {
      this.logger.error(
        'PAYMENT_PROVIDER_REFUND_MISMATCH ' +
          `paymentKeyMatch=${paymentKeyMatches} orderIdMatch=${orderIdMatches} ` +
          `paymentCanceled=${paymentCanceled} cancelCompleted=${cancelCompleted} ` +
          `cancelAmountValid=${cancelAmountValid}`,
      );
      throw new BadGatewayException({
        statusCode: 502,
        code: 'TOSS_REFUND_MISMATCH',
        message: '결제사 환불 결과가 요청과 일치하지 않습니다.',
        retryable: false,
        orderId,
      });
    }

    return {
      paymentKey,
      status: tossResponse.status,
      canceledAt: lastCancel?.canceledAt ?? tossResponse?.canceledAt,
      cancelAmount,
    };
  }
}
