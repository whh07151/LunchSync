import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 식당/메뉴 관련 API 호출 서비스
//
// 담당 엔드포인트:
//   GET /api/restaurants            — 식당 목록 (필터)
//   GET /api/restaurants/:id        — 식당 상세
//   GET /api/restaurants/:id/menus  — 메뉴 목록
// ══════════════════════════════════════════════════════════

/// 식당 데이터 모델
class RestaurantDto {
  const RestaurantDto({
    required this.id,
    required this.name,
    this.category,
    this.priceRange,
    this.address,
    this.lat,
    this.lng,
  });

  final String id;
  final String name;
  final String? category;
  final int? priceRange;
  final String? address;
  final double? lat;
  final double? lng;

  factory RestaurantDto.fromJson(Map<String, dynamic> json) {
    return RestaurantDto(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String?,
      priceRange: json['priceRange'] as int?,
      address: json['address'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
    );
  }
}

/// 메뉴 아이템 데이터 모델
class MenuItemDto {
  const MenuItemDto({
    required this.id,
    required this.name,
    required this.price,
    this.category,
    this.description,
    this.imageUrl,
  });

  final String id;
  final String name;
  final int price;
  final String? category;
  final String? description;
  final String? imageUrl;

  factory MenuItemDto.fromJson(Map<String, dynamic> json) {
    return MenuItemDto(
      id: json['id'] as String,
      name: json['name'] as String,
      price: json['price'] as int,
      category: json['category'] as String?,
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
    );
  }
}

class RestaurantsApiService {
  const RestaurantsApiService();

  Map<String, String> _headers(String accessToken) => {
        'Authorization': 'Bearer $accessToken',
      };

  // ── GET /api/restaurants ──────────────────────────────
  Future<List<RestaurantDto>> getRestaurants({
    required String accessToken,
    String? category,
    int? maxPrice,
    int? limit,
  }) async {
    try {
      final params = <String, String>{};
      if (category != null) params['category'] = category;
      if (maxPrice != null) params['maxPrice'] = maxPrice.toString();
      if (limit != null) params['limit'] = limit.toString();

      final uri = Uri.parse('${AppConfig.backendBaseUrl}/restaurants')
          .replace(queryParameters: params.isNotEmpty ? params : null);

      final response = await http.get(uri, headers: _headers(accessToken));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final list = json['data'] as List<dynamic>;
        return list
            .map((e) => RestaurantDto.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('[RestaurantsApiService] getRestaurants 에러: $e');
      return [];
    }
  }

  // ── GET /api/restaurants/:id/menus ────────────────────
  // 백엔드 응답 구조: data: { categories: [...], menus: [...] }
  // (배열이 아니라 래퍼 객체라서 data.menus를 꺼내서 매핑)
  Future<List<MenuItemDto>> getMenus({
    required String accessToken,
    required String restaurantId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
            '${AppConfig.backendBaseUrl}/restaurants/$restaurantId/menus'),
        headers: _headers(accessToken),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>? ?? const {};
        final list = data['menus'] as List<dynamic>? ?? const [];
        return list
            .map((e) => MenuItemDto.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('[RestaurantsApiService] getMenus 에러: $e');
      return [];
    }
  }
}
