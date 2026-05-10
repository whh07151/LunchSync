import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 사장/POS 메뉴 관리 API 호출 서비스
//
// 백엔드 매핑 (PosMenusController):
//   GET    /api/pos/menus/:restaurantId   → list(token, restaurantId)
//   POST   /api/pos/menus/:restaurantId   → create(token, restaurantId, payload)
//   PATCH  /api/pos/menus/item/:id        → update(token, menuId, patch)
//   DELETE /api/pos/menus/item/:id        → delete(token, menuId)
//
// 인증:
//   Bearer JWT 필수 (USER role=OWNER 또는 POS 토큰).
// ══════════════════════════════════════════════════════════

/// 메뉴 한 건 — 사장/POS 화면 표시용
class PosMenuItem {
  const PosMenuItem({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.price,
    required this.isAvailable,
    this.category,
    this.description,
    this.imageUrl,
  });

  final String id;
  final String restaurantId;
  final String name;
  final int price;
  final bool isAvailable;
  final String? category;
  final String? description;
  final String? imageUrl;

  factory PosMenuItem.fromJson(Map<String, dynamic> json) {
    return PosMenuItem(
      id: json['id'] as String,
      restaurantId: (json['restaurantId'] ?? json['restaurant_id']) as String,
      name: json['name'] as String,
      price: (json['price'] as num).toInt(),
      isAvailable: (json['isAvailable'] ?? json['is_available'] ?? true) as bool,
      category: json['category'] as String?,
      description: json['description'] as String?,
      imageUrl: (json['imageUrl'] ?? json['image_url']) as String?,
    );
  }
}

class PosMenusApiService {
  const PosMenusApiService();

  /// 식당의 모든 메뉴 — 품절 포함. 실패 시 빈 리스트.
  Future<List<PosMenuItem>> list({
    required String accessToken,
    required String restaurantId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/pos/menus/$restaurantId'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (body['data'] as List<dynamic>?) ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(PosMenuItem.fromJson)
          .toList(growable: false);
    } catch (e) {
      // ignore: avoid_print
      print('[PosMenusApiService] list 에러: $e');
      return const [];
    }
  }

  /// 메뉴 추가. 성공 시 추가된 PosMenuItem, 실패 시 null.
  Future<PosMenuItem?> create({
    required String accessToken,
    required String restaurantId,
    required String name,
    required int price,
    String? category,
    String? description,
    String? imageUrl,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/pos/menus/$restaurantId'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'price': price,
          'category': ?category,
          'description': ?description,
          'imageUrl': ?imageUrl,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return PosMenuItem.fromJson(body['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 메뉴 부분 수정. 품절 토글도 동일 메서드.
  Future<PosMenuItem?> update({
    required String accessToken,
    required String menuId,
    String? name,
    int? price,
    String? category,
    String? description,
    String? imageUrl,
    bool? isAvailable,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (price != null) body['price'] = price;
      if (category != null) body['category'] = category;
      if (description != null) body['description'] = description;
      if (imageUrl != null) body['imageUrl'] = imageUrl;
      if (isAvailable != null) body['isAvailable'] = isAvailable;

      final response = await http.patch(
        Uri.parse('${AppConfig.backendBaseUrl}/pos/menus/item/$menuId'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final resBody = jsonDecode(response.body) as Map<String, dynamic>;
        return PosMenuItem.fromJson(resBody['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 메뉴 삭제. 이미 주문에 사용된 메뉴는 백엔드가 거절(FK).
  Future<bool> delete({
    required String accessToken,
    required String menuId,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.backendBaseUrl}/pos/menus/item/$menuId'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
