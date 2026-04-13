import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 주문(Orders) 관련 API 호출 서비스
//
// 담당 엔드포인트:
//   POST  /api/orders          — 주문 생성 + 결제 (CU-17/18/19)
//   GET   /api/orders/today    — 오늘 내 주문 목록
//   GET   /api/orders/:id      — 주문 상세
//   PATCH /api/orders/:id/status — 주문 상태 변경
//
// 토스 결제 흐름과의 관계:
//   1) createOrder(paymentMethod: 'TOSS') 로 주문만 생성 (PENDING 상태)
//   2) 프론트가 토스 결제위젯 v2 로 결제 요청
//   3) 결제 성공 후 PaymentsApiService.confirm() 으로 최종 승인
// ══════════════════════════════════════════════════════════

/// 주문 생성 요청에 담는 한 개 메뉴 항목
class CreateOrderItem {
  const CreateOrderItem({
    required this.menuItemId,
    required this.quantity,
  });

  final String menuItemId; // Supabase menu_items.id (UUID)
  final int quantity;      // 수량 (1 이상)

  Map<String, dynamic> toJson() => {
        'menuItemId': menuItemId,
        'quantity': quantity,
      };
}

/// 주문 생성 API 응답
class CreateOrderResult {
  const CreateOrderResult({
    required this.id,
    required this.sessionId,
    required this.status,
    required this.totalPrice,
    required this.paymentMethod,
    this.paymentKey,
  });

  final String id;           // 생성된 주문 UUID — 토스 orderId 로 사용
  final String sessionId;
  final String status;       // PENDING | PAID | ...
  final int totalPrice;      // 총 금액 (KRW)
  final String paymentMethod;
  final String? paymentKey;  // SIMULATE 모드에서만 값이 있음

  factory CreateOrderResult.fromJson(Map<String, dynamic> json) {
    return CreateOrderResult(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      status: json['status'] as String,
      totalPrice: (json['totalPrice'] as num).toInt(),
      paymentMethod: json['paymentMethod'] as String,
      paymentKey: json['paymentKey'] as String?,
    );
  }
}

class OrdersApiService {
  const OrdersApiService();

  Map<String, String> _headers(String accessToken) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

  // ── POST /api/orders — 주문 생성 ──────────────────────
  // paymentMethod:
  //   - 'TOSS'     : 토스페이먼츠 결제위젯 v2 로 결제 (PENDING 상태로 생성)
  //   - 'SIMULATE' : 가상 결제 (즉시 PAID 처리)
  //   - 'CASH'     : 현금 결제 (즉시 PAID 처리)
  Future<CreateOrderResult?> createOrder({
    required String accessToken,
    required String sessionId,
    required List<CreateOrderItem> items,
    String paymentMethod = 'TOSS',
  }) async {
    try {
      final body = jsonEncode({
        'sessionId': sessionId,
        'items': items.map((e) => e.toJson()).toList(),
        'paymentMethod': paymentMethod,
      });

      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/orders'),
        headers: _headers(accessToken),
        body: body,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return CreateOrderResult.fromJson(
          json['data'] as Map<String, dynamic>,
        );
      }

      // ignore: avoid_print
      print(
        '[OrdersApiService] createOrder 실패: '
        '${response.statusCode} ${response.body}',
      );
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[OrdersApiService] createOrder 에러: $e');
      return null;
    }
  }
}
