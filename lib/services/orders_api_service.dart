// ══════════════════════════════════════════════════════════
// 파일 역할: 주문(orders) 관련 API 호출 + Wrapped(월간 리포트) 집계
//
// 담당 엔드포인트:
//   GET /api/orders/today           — 오늘 내가 참여한 주문 목록(이미 backend 존재 가정)
//   GET /api/orders/wrapped         — 월간 Wrapped 통계 (backend 미존재 시 폴백)
//
// 폴백 전략:
//   - 백엔드에 wrapped 엔드포인트가 아직 없을 수 있으므로
//     클라이언트가 직접 1달치 주문을 누적해 집계(N끼/평균/Top식당/카테고리 분포).
//   - 그것마저 실패하면 시연용 시드 데이터(WrappedStats.demo())를 반환.
//
// 사용처:
//   - CU-23 내정보 화면의 "이번 달 점심 Wrapped 보기" 카드 진입 시
//     WrappedScreen 이 getWrappedStats(year, month) 를 호출.
// ══════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

// ─────────────────────────────────────────────────────────
// 단일 주문 항목 DTO — /api/orders/today 응답 매핑용
// (백엔드 응답 스펙이 확정되기 전까지는 방어적으로 옵셔널 처리)
// ─────────────────────────────────────────────────────────
class OrderDto {
  const OrderDto({
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
  final String? category;       // 한식/일식/양식/중식/카페 등
  final int? totalAmount;       // 1인 결제 금액(원)
  final DateTime? createdAt;    // ISO 8601 (백엔드: created_at)

  factory OrderDto.fromJson(Map<String, dynamic> json) {
    // 백엔드 응답 키 후보를 모두 시도 (snake_case / camelCase 혼재 방어)
    final restaurant = json['restaurant'] as Map<String, dynamic>?;
    return OrderDto(
      id: (json['id'] ?? json['order_id'] ?? '').toString(),
      restaurantId: (json['restaurantId'] ??
              json['restaurant_id'] ??
              restaurant?['id'])
          ?.toString(),
      restaurantName: (json['restaurantName'] ??
              json['restaurant_name'] ??
              restaurant?['name']) as String?,
      category: (json['category'] ?? restaurant?['category']) as String?,
      totalAmount: (json['totalAmount'] ??
              json['total_amount'] ??
              json['amount']) as int?,
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}

// ─────────────────────────────────────────────────────────
// Wrapped 월간 통계 DTO
//   - totalCount   : 그 달에 먹은 끼니 수
//   - averagePrice : 1끼 평균 금액(원)
//   - topRestaurant: 가장 자주 간 식당 (이름/카테고리/방문 횟수)
//   - categoryRatio: 카테고리별 비율 (한식 0.45, 일식 0.22 ...)
// ─────────────────────────────────────────────────────────
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
  final Map<String, double> categoryRatio; // 카테고리 → 0.0~1.0

  /// 빈 데이터(끼니 0개) 표시용 — 끼니가 한 번도 없으면 이 상태로
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

  /// 시연용 시드 데이터 — 백엔드 응답도 없고 폴백 계산도 실패한 경우
  /// (시연 시나리오: orders 5건 기준)
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

// ─────────────────────────────────────────────────────────
// API 서비스 본체
// ─────────────────────────────────────────────────────────
class OrdersApiService {
  const OrdersApiService();

  Map<String, String> _headers(String accessToken) => {
        'Authorization': 'Bearer $accessToken',
      };

  // ── GET /api/orders/today ─────────────────────────────
  // 오늘 내가 참여한 주문 목록 (백엔드 미존재 시 빈 배열 반환)
  Future<List<OrderDto>> getTodayOrders(String accessToken) async {
    try {
      final uri = Uri.parse('${AppConfig.backendBaseUrl}/orders/today');
      final response = await http.get(uri, headers: _headers(accessToken));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (body['data'] as List<dynamic>?) ?? const [];
        return list
            .map((e) => OrderDto.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('[OrdersApiService] getTodayOrders 에러: $e');
      return [];
    }
  }

  // ── GET /api/orders/wrapped?year=&month= ──────────────
  // 백엔드 전용 wrapped 엔드포인트 시도 → 실패 시 폴백.
  //
  // 폴백 순서:
  //   ① /orders/wrapped 200 응답 → 그대로 사용
  //   ② /orders?year=&month= 가 있으면 그 응답을 클라가 직접 집계
  //   ③ /orders/today 만 가능하면 오늘 데이터로 집계 (사실상 1일치)
  //   ④ 위 전부 실패 → WrappedStats.demo() (시연용)
  Future<WrappedStats> getWrappedStats({
    required String accessToken,
    required int year,
    required int month,
  }) async {
    // ── ① 전용 엔드포인트 시도 ──────────────────────────
    try {
      final uri = Uri.parse(
        '${AppConfig.backendBaseUrl}/orders/wrapped'
        '?year=$year&month=$month',
      );
      final response = await http.get(uri, headers: _headers(accessToken));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>?;
        if (data != null) {
          return _wrappedFromJson(data, year, month);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[OrdersApiService] wrapped 전용 엔드포인트 실패(폴백 진행): $e');
    }

    // ── ② 월 단위 주문 목록 → 클라 집계 ────────────────
    try {
      final uri = Uri.parse(
        '${AppConfig.backendBaseUrl}/orders'
        '?year=$year&month=$month',
      );
      final response = await http.get(uri, headers: _headers(accessToken));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (body['data'] as List<dynamic>?) ?? const [];
        if (list.isNotEmpty) {
          final orders = list
              .map((e) => OrderDto.fromJson(e as Map<String, dynamic>))
              .toList();
          return _aggregate(orders, year, month);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[OrdersApiService] 월 단위 주문 폴백 실패: $e');
    }

    // ── ③ 오늘 주문이라도 있으면 집계 ───────────────────
    try {
      final todays = await getTodayOrders(accessToken);
      if (todays.isNotEmpty) {
        return _aggregate(todays, year, month);
      }
    } catch (_) {
      // 무시 후 다음 폴백
    }

    // ── ④ 데모(시드) 반환 — 시연용 ─────────────────────
    return WrappedStats.demo(year, month);
  }

  // ── 백엔드 응답 → DTO 변환 ────────────────────────────
  // 백엔드가 임의로 키를 정의해도 합리적으로 매핑.
  WrappedStats _wrappedFromJson(
    Map<String, dynamic> data,
    int year,
    int month,
  ) {
    final ratioRaw = data['categoryRatio'] as Map<String, dynamic>? ??
        data['category_ratio'] as Map<String, dynamic>? ??
        const {};
    final ratio = <String, double>{};
    ratioRaw.forEach((k, v) {
      if (v is num) ratio[k] = v.toDouble();
    });

    return WrappedStats(
      year: year,
      month: month,
      totalCount: (data['totalCount'] ?? data['total_count'] ?? 0) as int,
      averagePrice:
          (data['averagePrice'] ?? data['average_price'] ?? 0) as int,
      topRestaurantName: (data['topRestaurantName'] ??
              data['top_restaurant_name'] ??
              '단골 식당 없음') as String,
      topRestaurantCategory: (data['topRestaurantCategory'] ??
              data['top_restaurant_category'] ??
              '') as String,
      topVisitCount:
          (data['topVisitCount'] ?? data['top_visit_count'] ?? 0) as int,
      categoryRatio: ratio,
    );
  }

  // ── 주문 목록 → 통계 집계 (클라이언트 폴백 계산) ────
  // N끼/평균/Top식당/카테고리 비율을 한 번에 계산
  WrappedStats _aggregate(List<OrderDto> orders, int year, int month) {
    if (orders.isEmpty) return WrappedStats.empty(year, month);

    // 1) N끼 — 주문 개수 = 그 달 끼니 수
    final totalCount = orders.length;

    // 2) 평균 금액 — totalAmount 가 null 인 항목은 평균 계산에서 제외
    final priced =
        orders.where((o) => o.totalAmount != null && o.totalAmount! > 0);
    final sumPrice = priced.fold<int>(0, (acc, o) => acc + (o.totalAmount!));
    final averagePrice = priced.isEmpty ? 0 : (sumPrice ~/ priced.length);

    // 3) Top 식당 — 식당 ID(or 이름) 기준 카운트 후 최다 방문 1개
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

    // 4) 카테고리 비율 — 미상은 "기타"
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
