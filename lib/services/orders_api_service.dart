import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../core/api/api_auth_hooks.dart';
import '../core/api/api_retry.dart';
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
  const CreateOrderItem({required this.menuItemId, required this.quantity});

  final String menuItemId; // Supabase menu_items.id (UUID)
  final int quantity; // 수량 (1 이상)

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
  final String
  status; // PENDING | PAID | PREPARING | READY | COMPLETED | CANCELLED
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

  final String id; // 생성된 주문 UUID — 토스 orderId 로 사용
  final String sessionId;
  final String status; // PENDING | PAID | ...
  final int totalPrice; // 총 금액 (KRW)
  final String paymentMethod;
  final String? paymentKey; // SIMULATE 모드에서만 값이 있음

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

/// 주문 생성 시 화면에서 별도로 안내할 수 있는 백엔드 거절 사유.
///
/// 이 목록에 없는 서버 오류는 기존 계약대로 [OrdersApiService.createOrder]가
/// `null`을 반환한다. 응답 본문이나 임의의 서버 메시지를 UI까지 전달하지 않는다.
enum CreateOrderFailureCode {
  sessionNotFound('ORDER_SESSION_NOT_FOUND'),
  sessionNotReady('ORDER_SESSION_NOT_READY'),
  sessionRestaurantMismatch('ORDER_SESSION_RESTAURANT_MISMATCH');

  const CreateOrderFailureCode(this.backendCode);

  final String backendCode;

  static CreateOrderFailureCode? fromBackendCode(Object? value) {
    for (final code in values) {
      if (value == code.backendCode) return code;
    }
    return null;
  }
}

/// 사용자가 바로 수정할 수 있는 주문 세션 문제만 나타내는 통제된 예외.
class CreateOrderException implements Exception {
  const CreateOrderException(this.code);

  final CreateOrderFailureCode code;
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
        return CreateOrderResult.fromJson(json['data'] as Map<String, dynamic>);
      }

      final failureCode = _createOrderFailureCode(response.body);
      if (failureCode != null) {
        throw CreateOrderException(failureCode);
      }

      debugPrint('[OrdersApiService] CREATE_ORDER_HTTP_${response.statusCode}');
      return null;
    } on CreateOrderException {
      rethrow;
    } catch (e) {
      debugPrint('[OrdersApiService] CREATE_ORDER_FAILED');
      return null;
    }
  }

  CreateOrderFailureCode? _createOrderFailureCode(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) return null;
      return CreateOrderFailureCode.fromBackendCode(decoded['code']);
    } on FormatException {
      return null;
    }
  }

  // ── GET /api/orders/today — 오늘 내 주문 목록 ─────────
  Future<List<OrderSummaryDto>> getTodayOrders({
    required String accessToken,
  }) async {
    try {
      final response = await ApiRetry.get(
        Uri.parse('${AppConfig.backendBaseUrl}/orders/today'),
        headers: apiHeaders(accessToken),
        timeout: AppConfig.apiTimeout,
      );
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
      debugPrint('[OrdersApiService] GET_TODAY_ORDERS_FAILED');
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
      final response = await ApiRetry.get(
        Uri.parse('${AppConfig.backendBaseUrl}/orders/$orderId'),
        headers: apiHeaders(accessToken),
        timeout: AppConfig.apiTimeout,
      );
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return OrderDetailDto.fromJson(json['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[OrdersApiService] GET_ORDER_FAILED');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════
  // Wrapped(월간 리포트) — 2026-05-31 통합 (WOW#4)
  //
  // 백엔드 전용 엔드포인트가 아직 없을 수 있으므로 폴백 단계:
  //   ① GET /orders/wrapped?year=&month=                   — 200 → 그대로 사용
  //   ② GET /orders?year=&month= 로 받은 목록을 클라 집계
  //   ③ /orders/today 결과로 1일치 집계 (최후)
  //   ④ 전부 실패 → WrappedStats.demo() (시연용 시드)
  // ══════════════════════════════════════════════════════════
  Future<WrappedStats> getWrappedStats({
    required String accessToken,
    required int year,
    required int month,
  }) async {
    // ── ① 전용 엔드포인트 시도 ──────────────────────────
    try {
      final uri = Uri.parse(
        '${AppConfig.backendBaseUrl}/orders/wrapped?year=$year&month=$month',
      );
      final response = await ApiRetry.get(
        uri,
        headers: apiHeaders(accessToken),
        timeout: AppConfig.apiTimeout,
      );
      ApiAuthHooks.check(response.statusCode);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>?;
        if (data != null) {
          return _wrappedFromJson(data, year, month);
        }
      }
    } catch (e) {
      debugPrint('[OrdersApiService] GET_WRAPPED_FAILED');
    }

    // ── ② 월 단위 주문 목록 → 클라 집계 ────────────────
    try {
      final uri = Uri.parse(
        '${AppConfig.backendBaseUrl}/orders?year=$year&month=$month',
      );
      final response = await ApiRetry.get(
        uri,
        headers: apiHeaders(accessToken),
        timeout: AppConfig.apiTimeout,
      );
      ApiAuthHooks.check(response.statusCode);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (body['data'] as List<dynamic>?) ?? const [];
        if (list.isNotEmpty) {
          final orders = list
              .map((e) => _WrappedOrderDto.fromJson(e as Map<String, dynamic>))
              .toList();
          return _aggregate(orders, year, month);
        }
      }
    } catch (e) {
      debugPrint('[OrdersApiService] GET_MONTHLY_ORDERS_FAILED');
    }

    // ── ③ 오늘 주문이라도 있으면 집계 ───────────────────
    try {
      final todays = await getTodayOrders(accessToken: accessToken);
      if (todays.isNotEmpty) {
        final wrapped = todays
            .map(
              (o) => _WrappedOrderDto(
                id: o.id,
                totalAmount: o.totalPrice,
                createdAt: DateTime.tryParse(o.createdAt),
              ),
            )
            .toList();
        return _aggregate(wrapped, year, month);
      }
    } catch (_) {
      // 무시 후 다음 폴백
    }

    // ── ④ 데모 시드 ─────────────────────────────────────
    return WrappedStats.demo(year, month);
  }

  // ── 백엔드 응답 → WrappedStats 변환 ────────────────────
  WrappedStats _wrappedFromJson(
    Map<String, dynamic> data,
    int year,
    int month,
  ) {
    final ratioRaw =
        (data['categoryRatio'] as Map<String, dynamic>?) ??
        (data['category_ratio'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final ratio = <String, double>{};
    ratioRaw.forEach((k, v) {
      if (v is num) ratio[k] = v.toDouble();
    });

    return WrappedStats(
      year: year,
      month: month,
      totalCount: (data['totalCount'] ?? data['total_count'] ?? 0) as int,
      averagePrice: (data['averagePrice'] ?? data['average_price'] ?? 0) as int,
      topRestaurantName:
          (data['topRestaurantName'] ??
                  data['top_restaurant_name'] ??
                  '단골 식당 없음')
              as String,
      topRestaurantCategory:
          (data['topRestaurantCategory'] ??
                  data['top_restaurant_category'] ??
                  '')
              as String,
      topVisitCount:
          (data['topVisitCount'] ?? data['top_visit_count'] ?? 0) as int,
      categoryRatio: ratio,
    );
  }

  // ── 클라 집계 ──────────────────────────────────────────
  WrappedStats _aggregate(List<_WrappedOrderDto> orders, int year, int month) {
    if (orders.isEmpty) return WrappedStats.empty(year, month);
    final totalCount = orders.length;
    final priced = orders.where(
      (o) => o.totalAmount != null && o.totalAmount! > 0,
    );
    final sumPrice = priced.fold<int>(0, (acc, o) => acc + o.totalAmount!);
    final averagePrice = priced.isEmpty ? 0 : (sumPrice ~/ priced.length);

    final restaurantCount = <String, int>{};
    final restaurantName = <String, String>{};
    final restaurantCategory = <String, String>{};
    for (final o in orders) {
      final key = o.restaurantId ?? o.restaurantName ?? '미상';
      restaurantCount[key] = (restaurantCount[key] ?? 0) + 1;
      restaurantName[key] = o.restaurantName ?? '이름 없는 식당';
      if ((o.category ?? '').isNotEmpty) {
        restaurantCategory[key] = o.category!;
      }
    }
    final topKey = restaurantCount.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    final topName = restaurantName[topKey] ?? '이름 없는 식당';
    final topCategory = restaurantCategory[topKey] ?? '';
    final topVisit = restaurantCount[topKey] ?? 0;

    final categoryCount = <String, int>{};
    for (final o in orders) {
      final c = (o.category ?? '').isNotEmpty ? o.category! : '기타';
      categoryCount[c] = (categoryCount[c] ?? 0) + 1;
    }
    final total = categoryCount.values.fold<int>(0, (a, b) => a + b);
    final categoryRatio = <String, double>{};
    categoryCount.forEach((k, v) {
      categoryRatio[k] = total == 0 ? 0.0 : v / total;
    });

    return WrappedStats(
      year: year,
      month: month,
      totalCount: totalCount,
      averagePrice: averagePrice,
      topRestaurantName: topName,
      topRestaurantCategory: topCategory,
      topVisitCount: topVisit,
      categoryRatio: categoryRatio,
    );
  }
}

// ═════════════════════════════════════════════════════════
// Wrapped 월간 통계 DTO (2026-05-31 통합)
// ═════════════════════════════════════════════════════════

class WrappedStats {
  const WrappedStats({
    required this.year,
    required this.month,
    required this.totalCount,
    required this.averagePrice,
    required this.topRestaurantName,
    required this.topRestaurantCategory,
    required this.topVisitCount,
    required this.categoryRatio,
  });

  final int year;
  final int month;
  final int totalCount;
  final int averagePrice;
  final String topRestaurantName;
  final String topRestaurantCategory;
  final int topVisitCount;
  final Map<String, double> categoryRatio;

  factory WrappedStats.empty(int year, int month) => WrappedStats(
    year: year,
    month: month,
    totalCount: 0,
    averagePrice: 0,
    topRestaurantName: '아직 기록이 없어요',
    topRestaurantCategory: '',
    topVisitCount: 0,
    categoryRatio: const {},
  );

  factory WrappedStats.demo(int year, int month) => WrappedStats(
    year: year,
    month: month,
    totalCount: 5,
    averagePrice: 9200,
    topRestaurantName: '백채김치찌개',
    topRestaurantCategory: '한식',
    topVisitCount: 2,
    categoryRatio: const {
      '한식': 0.45,
      '일식': 0.22,
      '양식': 0.18,
      '중식': 0.10,
      '카페': 0.05,
    },
  );
}

// 내부 집계용 — 백엔드 응답 매핑 방어 (snake_case/camelCase 혼재 대응)
class _WrappedOrderDto {
  const _WrappedOrderDto({
    required this.id,
    this.restaurantId,
    this.restaurantName,
    this.category,
    this.totalAmount,
    this.createdAt,
  });

  final String id;
  final String? restaurantId;
  final String? restaurantName;
  final String? category;
  final int? totalAmount;
  final DateTime? createdAt;

  factory _WrappedOrderDto.fromJson(Map<String, dynamic> json) {
    final restaurant = json['restaurant'] as Map<String, dynamic>?;
    return _WrappedOrderDto(
      id: (json['id'] ?? json['order_id'] ?? '').toString(),
      restaurantId:
          (json['restaurantId'] ?? json['restaurant_id'] ?? restaurant?['id'])
              ?.toString(),
      restaurantName:
          (json['restaurantName'] ??
                  json['restaurant_name'] ??
                  restaurant?['name'])
              as String?,
      category: (json['category'] ?? restaurant?['category']) as String?,
      totalAmount:
          (json['totalAmount'] ??
                  json['total_amount'] ??
                  json['totalPrice'] ??
                  json['amount'])
              as int?,
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
