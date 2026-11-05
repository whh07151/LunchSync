import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../core/api/api_auth_hooks.dart';
import '../core/api/api_retry.dart';
import '../core/config/app_config.dart';

class PosSeatItem {
  const PosSeatItem({
    required this.menuId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.addedAt,
  });

  final String menuId;
  final String name;
  final int price;
  final int quantity;
  final String addedAt;

  factory PosSeatItem.fromJson(Map<String, dynamic> json) {
    return PosSeatItem(
      menuId: json['menuId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      price: (json['price'] as num?)?.toInt() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      addedAt: json['addedAt']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'menuId': menuId,
        'name': name,
        'price': price,
        'quantity': quantity,
        'addedAt': addedAt,
      };
}

class PosSeat {
  const PosSeat({
    required this.id,
    required this.restaurantId,
    required this.label,
    required this.status,
    this.startedAt,
    this.items = const [],
    this.sortOrder = 0,
  });

  final String id;
  final String restaurantId;
  final String label;
  final String status;
  final String? startedAt;
  final List<PosSeatItem> items;
  final int sortOrder;

  bool get isOccupied => status == 'occupied';

  int get totalOrderAmount =>
      items.fold<int>(0, (sum, item) => sum + item.price * item.quantity);

  factory PosSeat.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return PosSeat(
      id: json['id']?.toString() ?? '',
      restaurantId:
          (json['restaurantId'] ?? json['restaurant_id'])?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      status: json['status']?.toString() ?? 'empty',
      startedAt: (json['startedAt'] ?? json['started_at']) as String?,
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(PosSeatItem.fromJson)
              .toList(growable: false)
          : const [],
      sortOrder:
          ((json['sortOrder'] ?? json['sort_order']) as num?)?.toInt() ?? 0,
    );
  }
}

class PosReservation {
  const PosReservation({
    required this.id,
    required this.restaurantId,
    required this.kind,
    required this.customerName,
    required this.partySize,
    required this.status,
    required this.createdAt,
    this.scheduledAt,
    this.note,
  });

  final String id;
  final String restaurantId;
  final String kind;
  final String customerName;
  final int partySize;
  final String status;
  final String createdAt;
  final String? scheduledAt;
  final String? note;

  bool get isOpen => status == 'OPEN';
  bool get isReservation => kind == 'RESERVATION';

  int get requiredTables => ((partySize - 1) ~/ 4) + 1;

  bool canAccommodateWith(int emptySeatCount) =>
      emptySeatCount >= requiredTables;

  factory PosReservation.fromJson(Map<String, dynamic> json) {
    return PosReservation(
      id: json['id']?.toString() ?? '',
      restaurantId:
          (json['restaurantId'] ?? json['restaurant_id'])?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'RESERVATION',
      customerName:
          (json['customerName'] ?? json['customer_name'])?.toString() ?? '손님',
      partySize:
          ((json['partySize'] ?? json['party_size']) as num?)?.toInt() ?? 1,
      status: json['status']?.toString() ?? 'OPEN',
      createdAt:
          (json['createdAt'] ?? json['created_at'])?.toString() ?? '',
      scheduledAt: (json['scheduledAt'] ?? json['scheduled_at']) as String?,
      note: json['note'] as String?,
    );
  }
}

class PosOperationsApiService {
  const PosOperationsApiService();

  Future<List<PosSeat>> listSeats({
    required String accessToken,
    required String restaurantId,
  }) async {
    try {
      final response = await ApiRetry.get(
        Uri.parse('${AppConfig.backendBaseUrl}/pos/seats/$restaurantId'),
        headers: {'Authorization': 'Bearer $accessToken'},
        timeout: AppConfig.apiTimeout,
      );
      ApiAuthHooks.check(response.statusCode);
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (body['data'] as List<dynamic>?) ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(PosSeat.fromJson)
          .toList(growable: false);
    } catch (_) {
      debugPrint('[PosOperationsApiService] LIST_SEATS_FAILED');
      return const [];
    }
  }

  Future<PosSeat?> addSeat({
    required String accessToken,
    required String restaurantId,
    String? label,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/pos/seats/$restaurantId'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'label': ?label}),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return PosSeat.fromJson(body['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<PosSeat?> updateSeatStatus({
    required String accessToken,
    required String seatId,
    required bool occupied,
    String? label,
  }) async {
    try {
      final payload = <String, dynamic>{
        'status': occupied ? 'occupied' : 'empty',
        'startedAt': occupied ? DateTime.now().toUtc().toIso8601String() : null,
        if (!occupied) 'items': const <Map<String, dynamic>>[],
        'label': ?label,
      };
      final response = await http
          .patch(
            Uri.parse('${AppConfig.backendBaseUrl}/pos/seats/item/$seatId'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return PosSeat.fromJson(body['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteSeat({
    required String accessToken,
    required String seatId,
  }) async {
    try {
      final response = await http
          .delete(
            Uri.parse('${AppConfig.backendBaseUrl}/pos/seats/item/$seatId'),
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<PosReservation>> listReservations({
    required String accessToken,
    required String restaurantId,
  }) async {
    try {
      final response = await ApiRetry.get(
        Uri.parse(
          '${AppConfig.backendBaseUrl}/pos/reservations/$restaurantId',
        ),
        headers: {'Authorization': 'Bearer $accessToken'},
        timeout: AppConfig.apiTimeout,
      );
      ApiAuthHooks.check(response.statusCode);
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (body['data'] as List<dynamic>?) ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(PosReservation.fromJson)
          .toList(growable: false);
    } catch (_) {
      debugPrint('[PosOperationsApiService] LIST_RESERVATIONS_FAILED');
      return const [];
    }
  }

  Future<PosReservation?> createReservation({
    required String accessToken,
    required String restaurantId,
    required String kind,
    required String customerName,
    required int partySize,
    String? scheduledAt,
    String? note,
  }) async {
    try {
      final payload = <String, dynamic>{
        'kind': kind,
        'customerName': customerName,
        'partySize': partySize,
        'scheduledAt': ?scheduledAt,
        'note': ?note,
      };
      final response = await http
          .post(
            Uri.parse(
              '${AppConfig.backendBaseUrl}/pos/reservations/$restaurantId',
            ),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return PosReservation.fromJson(body['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<PosReservation?> updateReservationStatus({
    required String accessToken,
    required String reservationId,
    required String status,
  }) async {
    try {
      final response = await http
          .patch(
            Uri.parse(
              '${AppConfig.backendBaseUrl}/pos/reservations/item/$reservationId/status',
            ),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'status': status}),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return PosReservation.fromJson(body['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteReservation({
    required String accessToken,
    required String reservationId,
  }) async {
    try {
      final response = await http
          .delete(
            Uri.parse(
              '${AppConfig.backendBaseUrl}/pos/reservations/item/$reservationId',
            ),
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateTodaysNote({
    required String accessToken,
    required String restaurantId,
    required String? note,
  }) async {
    try {
      final response = await http
          .patch(
            Uri.parse(
              '${AppConfig.backendBaseUrl}/pos/restaurants/$restaurantId/todays-note',
            ),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'note': note}),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
