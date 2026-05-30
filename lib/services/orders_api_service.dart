import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../core/api/api_auth_hooks.dart';
import '../core/api/http_headers_helper.dart';

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

/// 주문 목록 항목 (GET /orders/today 응답)
///
/// 목록에서는 item 정보를 반환하지 않음 → 상세는 getOrderById로.
class OrderSummaryDto {
  const OrderSummaryDto({
    required this.id,
    required this.sessionId,
    required this.status,
    required this.totalPrice,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final String status;    // PENDING | PAID | PREPARING | READY | COMPLETED | CANCELLED
  final int totalPrice;
  final String createdAt; // ISO 8601 문자열

  factory OrderSummaryDto.fromJson(Map<String, dynamic> json) {
    return OrderSummaryDto(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      status: json['status'] as String,
      totalPrice: (json['totalPrice'] as num).toInt(),
      createdAt: json['createdAt'] as String? ?? '',
    );
  }
}

/// 주문 상세 항목 (order_items[] 한 줄)
class OrderItemDetailDto {
  const OrderItemDetailDto({
    required this.id,
    required this.menuItemId,
    required this.menuName,
    required this.quantity,
    required this.price,
  });

  final String id;
  final String menuItemId;
  final String? menuName;
  final int quantity;
  final int price;

  factory OrderItemDetailDto.fromJson(Map<String, dynamic> json) {
    return OrderItemDetailDto(
      id: json['id'] as String,
      menuItemId: json['menuItemId'] as String,
      menuName: json['menuName'] as String?,
      quantity: (json['quantity'] as num).toInt(),
      price: (json['price'] as num).toInt(),
    );
  }
}

/// 주문 상세 (GET /orders/:id 응답)
///
/// [별점/리뷰 필드 — 2026-05-15 추가]
///   백엔드 OrdersService.getOrderById 가 review_score / review_text / review_at /
///   restaurant_id 도 함께 select 해서 내려주므로 클라이언트 측 DTO 도 동기화한다.
///   reviewScore 가 null = 아직 리뷰 미작성 → 손님 어플 "별점 남기기" 카드 노출.
///   reviewScore != null = 이미 작성 → 카드 숨김 (배민 패턴, 1주문 1리뷰).
///   restaurantId 는 사장 리뷰 화면 진입 등에 활용 가능 (현재는 표시 용).
class OrderDetailDto {
  const OrderDetailDto({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.status,
    required this.totalPrice,
    required this.items,
    this.paymentKey,
    this.createdAt,
    this.updatedAt,
    this.restaurantId,
    this.reviewScore,
    this.reviewText,
    this.reviewAt,
    this.estimatedReadyAt,
    this.completionPhotoUrl,
  });

  final String id;
  final String sessionId;
  final String userId;
  final String status;
  final int totalPrice;
  final String? paymentKey;
  final String? createdAt;
  final String? updatedAt;
  final List<OrderItemDetailDto> items;

  /// 주문이 속한 식당 ID (별점 카드 컨텍스트 표시 등 보조 용도).
  final String? restaurantId;

  /// 별점 (1~5). null = 아직 미작성.
  final int? reviewScore;

  /// 리뷰 본문. null 또는 빈 문자열 = 작성 안 함.
  final String? reviewText;

  /// 리뷰 작성 시각 (ISO 8601). null = 미작성.
  final String? reviewAt;

  /// 2026-05-16 배민 패턴 — 예상 픽업 시각 (ISO 8601).
  /// PAID/ACCEPTED/PREPARING 일 때만 채워짐. 그 외는 null.
  final String? estimatedReadyAt;

  /// 2026-05-31 WOW#2 — 사장이 POS 에서 보낸 조리 완료 사진 URL.
  /// null = 아직 사진 미첨부. 손님 추적 화면이 hero 이미지로 페이드인 표시.
  final String? completionPhotoUrl;

  factory OrderDetailDto.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'] as List<dynamic>? ?? [];
    return OrderDetailDto(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      userId: json['userId'] as String,
      status: json['status'] as String,
      totalPrice: (json['totalPrice'] as num).toInt(),
      paymentKey: json['paymentKey'] as String?,
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
      restaurantId: json['restaurantId'] as String?,
      reviewScore: (json['reviewScore'] as num?)?.toInt(),
      reviewText: json['reviewText'] as String?,
      reviewAt: json['reviewAt'] as String?,
      estimatedReadyAt: json['estimatedReadyAt'] as String?,
      completionPhotoUrl: json['completionPhotoUrl'] as String?,
      items: itemsRaw
          .map((e) => OrderItemDetailDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
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

  // 2026-05-30 헤더 빌더 통합: 공통 헬퍼 apiHeaders() 로 이관
  //   (lib/core/api/http_headers_helper.dart). 9개 서비스 중복 제거.

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

      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/orders'),
            headers: apiHeaders(accessToken),
            body: body,
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return CreateOrderResult.fromJson(
          json['data'] as Map<String, dynamic>,
        );
      }

      debugPrint(
        '[OrdersApiService] createOrder 실패: '
        '${response.statusCode} ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[OrdersApiService] createOrder 에러: $e');
      return null;
    }
  }

  // ── GET /api/orders/today — 오늘 내 주문 목록 ─────────
  Future<List<OrderSummaryDto>> getTodayOrders({
    required String accessToken,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.backendBaseUrl}/orders/today'),
            headers: apiHeaders(accessToken),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final list = json['data'] as List<dynamic>;
        return list
            .map((e) => OrderSummaryDto.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[OrdersApiService] getTodayOrders 에러: $e');
      return [];
    }
  }

  // ── GET /api/orders/:id — 주문 상세 (폴링 대상) ──────
  // 주문 추적 화면에서 3초 간격 폴링으로 상태 변화를 감지하는 데 사용.
  Future<OrderDetailDto?> getOrderById({
    required String accessToken,
    required String orderId,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.backendBaseUrl}/orders/$orderId'),
            headers: apiHeaders(accessToken),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return OrderDetailDto.fromJson(json['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[OrdersApiService] getOrderById 에러: $e');
      return null;
    }
  }
}
