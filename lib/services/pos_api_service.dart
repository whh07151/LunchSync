import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 사장님 화면(OWNER 모드)에서 호출하는 POS API 클라이언트
//
// 담당 엔드포인트:
//   GET   /api/pos/restaurants/:id/orders  — 식당별 주문 목록 (OW-10)
//   GET   /api/pos/restaurants/:id/stats   — 결제 상태 통계 (POS-08)
//   PATCH /api/pos/orders/:id/status       — 주문 상태 변경
//   POST  /api/pos/orders/:id/cancel       — 취소/환불 (POS-09)
//
// 인증:
//   - 모든 요청에 Bearer JWT 필요 (NestJS PosController @UseGuards(JwtAuthGuard))
//   - accessToken은 호출자가 userProvider에서 꺼내 전달
//
// 에러 처리:
//   - 모든 메서드는 실패 시 null/false/빈 리스트 반환 (예외를 위로 던지지 않음)
//   - 화면은 "데이터를 불러오지 못했어요" 폴백 표시
// ══════════════════════════════════════════════════════════

/// 주문 단건 — POS 화면 카드/리스트 렌더링용
///
/// 백엔드 GET /api/pos/restaurants/:id/orders 응답의 각 항목과 매칭.
/// 백엔드 응답 스키마는 LSPOS DEV_LOG 백엔드 협의 #3에 따라 향후 보강 예정.
class PosOrder {
  const PosOrder({
    required this.id,
    required this.status,
    required this.totalAmount,
    this.orderNumber,
    this.customerName,
    this.createdAt,
    this.itemsSummary,
  });

  final String id;
  final String status;            // PENDING | PAID | PREPARING | READY | COMPLETED | CANCELLED
  final int totalAmount;          // 합계 금액 (원)
  final String? orderNumber;      // 주문번호(짧은 문자열) — 백엔드가 제공하면 표시
  final String? customerName;     // 손님 표시명 — 미연동 시 null
  final String? createdAt;        // ISO8601 타임스탬프
  final String? itemsSummary;     // "비빔밥 외 2건" 같은 짧은 요약 — 백엔드가 제공하면 표시

  factory PosOrder.fromJson(Map<String, dynamic> json) {
    return PosOrder(
      id: json['id']?.toString() ?? '',
      status: (json['status'] as String?) ?? 'PENDING',
      totalAmount: (json['totalAmount'] as num?)?.toInt() ??
          (json['total_amount'] as num?)?.toInt() ??
          0,
      orderNumber: json['orderNumber'] as String? ??
          json['order_number'] as String?,
      customerName: json['customerName'] as String? ??
          json['customer_name'] as String?,
      createdAt: json['createdAt'] as String? ??
          json['created_at'] as String?,
      itemsSummary: json['itemsSummary'] as String? ??
          json['items_summary'] as String?,
    );
  }
}

/// 식당 결제 상태 통계 — 사장 홈 요약 카드용
///
/// 백엔드 GET /api/pos/restaurants/:id/stats 응답 매핑.
/// 결제 상태별 카운트 + 합계 매출 + 결제수단별 매출(2026-05-13 추가) 제공.
class PosStats {
  const PosStats({
    required this.pendingCount,
    required this.paidCount,
    required this.preparingCount,
    required this.readyCount,
    required this.completedCount,
    required this.cancelledCount,
    required this.totalRevenue,
    this.tossRevenue = 0,
    this.cardRevenue = 0,
    this.cashRevenue = 0,
    this.simulateRevenue = 0,
  });

  final int pendingCount;
  final int paidCount;
  final int preparingCount;
  final int readyCount;
  final int completedCount;
  final int cancelledCount;
  final int totalRevenue;

  // 결제수단별 매출 (백엔드 협의 #9b 반영)
  final int tossRevenue;
  final int cardRevenue;
  final int cashRevenue;
  final int simulateRevenue;

  /// 사장 홈 "대기 중" 카드 = PENDING + PAID (결제는 됐지만 아직 조리 전)
  int get waitingCount => pendingCount + paidCount;

  /// 사장 홈 "조리 중" 카드 = PREPARING
  int get cookingCount => preparingCount;

  /// 사장 홈 "완료" 카드 = READY + COMPLETED (픽업 가능 + 픽업 완료)
  int get doneCount => readyCount + completedCount;

  factory PosStats.fromJson(Map<String, dynamic> json) {
    return PosStats(
      pendingCount: _intOf(json, 'pending', 'pendingCount'),
      paidCount: _intOf(json, 'paid', 'paidCount'),
      preparingCount: _intOf(json, 'preparing', 'preparingCount'),
      readyCount: _intOf(json, 'ready', 'readyCount'),
      completedCount: _intOf(json, 'completed', 'completedCount'),
      cancelledCount: _intOf(json, 'cancelled', 'cancelledCount'),
      totalRevenue: (json['totalRevenue'] as num?)?.toInt() ??
          (json['revenue'] as num?)?.toInt() ??
          0,
      tossRevenue: (json['tossRevenue'] as num?)?.toInt() ?? 0,
      cardRevenue: (json['cardRevenue'] as num?)?.toInt() ?? 0,
      cashRevenue: (json['cashRevenue'] as num?)?.toInt() ?? 0,
      simulateRevenue: (json['simulateRevenue'] as num?)?.toInt() ?? 0,
    );
  }

  /// 백엔드가 어느 키 이름을 쓰든 둘 중 먼저 발견되는 정수값을 반환.
  /// 응답 스펙이 확정되면 여기 단순화.
  static int _intOf(Map<String, dynamic> json, String snake, String camel) {
    return (json[snake] as num?)?.toInt() ??
        (json[camel] as num?)?.toInt() ??
        0;
  }

  /// 응답이 비어있을 때 사용할 0 통계
  static const PosStats empty = PosStats(
    pendingCount: 0,
    paidCount: 0,
    preparingCount: 0,
    readyCount: 0,
    completedCount: 0,
    cancelledCount: 0,
    totalRevenue: 0,
  );
}


class PosApiService {
  const PosApiService();

  // ── GET /api/pos/restaurants/:id/orders ─────────────────
  // status 쿼리 파라미터로 특정 상태 필터 가능 (예: status=PAID).
  // 실패 시 빈 리스트 반환 — 화면은 "주문이 없어요" 표시.
  Future<List<PosOrder>> getOrders({
    required String accessToken,
    required String restaurantId,
    String? status,
  }) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.backendBaseUrl}/pos/restaurants/$restaurantId/orders'
        '${status != null ? '?status=$status' : ''}',
      );
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode != 200) return const [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'];

      // 백엔드는 List 또는 { orders: [...] } 두 형태 모두 가능 — 둘 다 처리
      List<dynamic> rawList;
      if (data is List) {
        rawList = data;
      } else if (data is Map<String, dynamic>) {
        rawList = (data['orders'] as List<dynamic>?) ?? const [];
      } else {
        return const [];
      }

      return rawList
          .whereType<Map<String, dynamic>>()
          .map(PosOrder.fromJson)
          .toList(growable: false);
    } catch (e) {
      // ignore: avoid_print
      print('[PosApiService] getOrders 에러: $e');
      return const [];
    }
  }

  // ── GET /api/pos/restaurants/:id/stats ──────────────────
  // 사장 홈 요약 카드용. 실패 시 모든 카운트 0인 PosStats.empty 반환.
  Future<PosStats> getStats({
    required String accessToken,
    required String restaurantId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${AppConfig.backendBaseUrl}/pos/restaurants/$restaurantId/stats',
        ),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode != 200) return PosStats.empty;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'];

      if (data is Map<String, dynamic>) {
        return PosStats.fromJson(data);
      }
      return PosStats.empty;
    } catch (e) {
      // ignore: avoid_print
      print('[PosApiService] getStats 에러: $e');
      return PosStats.empty;
    }
  }

  // ── PATCH /api/pos/orders/:id/status ────────────────────
  // 주문 상태 전이 (PAID → PREPARING → READY → COMPLETED).
  // 잘못된 전이는 백엔드가 거절 — UI에서도 nextStatus 가드 권장.
  Future<bool> updateOrderStatus({
    required String accessToken,
    required String orderId,
    required String status,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('${AppConfig.backendBaseUrl}/pos/orders/$orderId/status'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'status': status}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── POST /api/pos/orders/:id/cancel ─────────────────────
  // 취소/환불 — reason은 운영 통계용 (선택).
  Future<bool> cancelOrder({
    required String accessToken,
    required String orderId,
    String? reason,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/pos/orders/$orderId/cancel'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'reason': ?reason}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
