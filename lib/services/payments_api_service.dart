import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../core/api/api_auth_hooks.dart';
import '../core/api/http_headers_helper.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 토스페이먼츠 결제 승인 API 호출 서비스
//
// 담당 엔드포인트:
//   POST /api/payments/confirm — 결제 승인 (CU-19)
//
// 호출 시점:
//   - 토스 결제위젯 v2 가 결제를 성공적으로 처리한 뒤
//     successUrl 로 paymentKey/orderId/amount 를 넘기면
//     이 서비스로 백엔드에 최종 승인 요청을 보낸다.
//   - 백엔드가 시크릿 키로 /v1/payments/confirm 을 호출하고,
//     성공 시 orders.status = PAID 로 업데이트.
//
// 왜 프론트가 바로 토스 API 를 호출하지 않는가?
//   토스 시크릿 키(test_sk_..., live_sk_...)는 절대
//   프론트에 노출되면 안 되기 때문. 승인은 반드시 백엔드에서만.
// ══════════════════════════════════════════════════════════

/// /api/payments/confirm 응답 데이터
class ConfirmPaymentResult {
  const ConfirmPaymentResult({
    required this.orderId,
    required this.status,
    this.paymentKey,
    this.method,
    this.approvedAt,
    this.totalAmount,
    this.alreadyPaid = false,
  });

  final String orderId;        // 주문 UUID
  final String status;         // 'PAID'
  final String? paymentKey;    // 토스가 발급한 결제 키
  final String? method;        // 카드 / 간편결제 / 계좌이체 등
  final String? approvedAt;    // 토스 승인 완료 시각 (ISO8601)
  final int? totalAmount;      // 토스가 승인한 총 금액
  final bool alreadyPaid;      // 이미 승인된 주문이었는지 (중복 호출 플래그)

  factory ConfirmPaymentResult.fromJson(Map<String, dynamic> json) {
    return ConfirmPaymentResult(
      orderId: json['orderId'] as String,
      status: json['status'] as String,
      paymentKey: json['paymentKey'] as String?,
      method: json['method'] as String?,
      approvedAt: json['approvedAt'] as String?,
      totalAmount: (json['totalAmount'] as num?)?.toInt(),
      alreadyPaid: (json['alreadyPaid'] as bool?) ?? false,
    );
  }
}

class PaymentsApiService {
  const PaymentsApiService();

  // 2026-05-30 헤더 빌더 통합: 공통 헬퍼 apiHeaders() 로 이관
  //   (lib/core/api/http_headers_helper.dart). 9개 서비스 중복 제거.

  // ── POST /api/payments/confirm ────────────────────────
  // 결제 성공 화면(PaymentSuccessScreen)에서 호출.
  //
  // 성공 시: 서버가 토스에 최종 승인 요청 + orders 상태 PAID 업데이트 →
  //         ConfirmPaymentResult 반환
  // 실패 시: null 반환 (에러 원인은 stdout 로그 참고)
  Future<ConfirmPaymentResult?> confirmPayment({
    required String accessToken,
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/payments/confirm'),
            headers: apiHeaders(accessToken),
            body: jsonEncode({
              'paymentKey': paymentKey,
              'orderId': orderId,
              'amount': amount,
            }),
          )
          // 결제 승인은 길어질 수 있으므로 기본보다 길게 (15s)
          .timeout(const Duration(seconds: 15));
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        // 2026-05-30 P2 fix: 백엔드 응답 포맷 변경(top-level order) 또는
        // PostgREST silent failure 로 'data' 키 누락 시 캐스팅 예외 → 앱
        // 크래시. 결제 금액만 소비되고 결과 화면 진입 실패하는 회귀 차단.
        final data = json['data'] as Map<String, dynamic>?;
        if (data == null) {
          debugPrint(
            '[PaymentsApiService] confirmPayment 응답에 data 필드 누락: '
            '${response.body}',
          );
          return null;
        }
        return ConfirmPaymentResult.fromJson(data);
      }

      debugPrint(
        '[PaymentsApiService] confirmPayment 실패: '
        '${response.statusCode} ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[PaymentsApiService] confirmPayment 에러: $e');
      return null;
    }
  }
}
