import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../core/api/api_auth_hooks.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 식당/메뉴 관련 API 호출 서비스
//
// 담당 엔드포인트:
//   GET /api/restaurants            — 식당 목록 (필터)
//   GET /api/restaurants/:id        — 식당 상세
//   GET /api/restaurants/:id/menus  — 메뉴 목록
// ══════════════════════════════════════════════════════════

/// 식당 데이터 모델
///
/// [imageUrl 처리 — 2026-05-13 추가]
///   사장님 피드백("사진이 잘 보였으면") 대응을 위해 클라이언트 측에서
///   먼저 imageUrl 매핑을 받을 수 있도록 옵셔널 필드를 추가했다.
///   현재 백엔드 restaurants 응답에는 image_url 컬럼이 select 에 포함되지
///   않으므로 대부분 null 로 들어오지만, 추후 백엔드가 채워주기만 하면
///   클라이언트는 자동으로 사진을 렌더링한다. null 일 때는 FoodImage
///   위젯이 카테고리별 이모지 fallback 으로 graceful 하게 대체.
class RestaurantDto {
  const RestaurantDto({
    required this.id,
    required this.name,
    this.category,
    this.priceRange,
    this.address,
    this.lat,
    this.lng,
    this.imageUrl,
    this.rating,
  });

  final String id;
  final String name;
  final String? category;
  final int? priceRange;
  final String? address;
  final double? lat;
  final double? lng;
  /// 식당 대표 이미지 URL. 백엔드가 내려주지 않으면 null.
  /// FoodImage 위젯에서 null/빈 문자열을 안전 처리하므로 그대로 전달해도 됨.
  final String? imageUrl;

  /// 식당 평점 (0.0 ~ 5.0)
  ///
  /// [출처 및 흐름 — 2026-05-14 추가]
  ///   네이버 플레이스 reviewScore → CrawlService.fetchNaverPlaceDetail() →
  ///   restaurants.rating(NUMERIC(2,1)) → RestaurantsService.getRestaurants()/
  ///   getRestaurantById() → 본 DTO.
  ///
  ///   사장님 피드백 "네이버나 구글로 식당 평점 조사한 거 맞아?" 에 대한
  ///   응답으로, 그동안 수집되고도 버려졌던 네이버 평점 값을 UI 까지 흘려보낸다.
  ///   평점 미수집 식당은 null 이므로 위젯에서 안전 분기 처리(없으면 칩 미표시).
  final double? rating;

  factory RestaurantDto.fromJson(Map<String, dynamic> json) {
    return RestaurantDto(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String?,
      priceRange: json['priceRange'] as int?,
      address: json['address'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      // 백엔드가 응답에 imageUrl 키를 포함하지 않더라도 안전(null) 매핑.
      imageUrl: json['imageUrl'] as String?,
      // NUMERIC 컬럼은 JSON 으로 number 또는 string 형태가 둘 다 가능하므로
      // num 으로 받아 toDouble 변환. 백엔드가 명시적으로 Number() 변환 후 보내지만
      // 클라이언트도 방어적 매핑 유지(추후 컬럼 타입 변경에 대비).
      rating: (json['rating'] as num?)?.toDouble(),
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

      final response = await http
          .get(uri, headers: _headers(accessToken))
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final list = json['data'] as List<dynamic>;
        return list
            .map((e) => RestaurantDto.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[RestaurantsApiService] getRestaurants 에러: $e');
      return [];
    }
  }

  // ── GET /api/restaurants/:id ───────────────────────────
  // 단건 조회 — getRestaurants 전체 받고 필터링하던 비효율 제거용.
  // 백엔드 응답은 RestaurantDto 단일 객체.
  Future<RestaurantDto?> getRestaurantById({
    required String accessToken,
    required String restaurantId,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.backendBaseUrl}/restaurants/$restaurantId'),
            headers: _headers(accessToken),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>?;
        if (data == null) return null;
        return RestaurantDto.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('[RestaurantsApiService] getRestaurantById 에러: $e');
      return null;
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
      final response = await http
          .get(
            Uri.parse(
                '${AppConfig.backendBaseUrl}/restaurants/$restaurantId/menus'),
            headers: _headers(accessToken),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

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
      debugPrint('[RestaurantsApiService] getMenus 에러: $e');
      return [];
    }
  }
}
