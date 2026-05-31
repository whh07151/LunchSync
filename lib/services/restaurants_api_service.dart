import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import '../core/config/app_config.dart';
import '../core/api/api_auth_hooks.dart';
import '../core/api/api_retry.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 식당/메뉴 관련 API 호출 서비스
//
// 담당 엔드포인트:
//   GET /api/restaurants               — 식당 목록 (필터)
//   GET /api/restaurants/:id           — 식당 상세
//   GET /api/restaurants/:id/menus     — 메뉴 목록
//   GET /api/restaurants/:id/loyalty   — 단골 등급 (WOW#5, 2026-05-31)
// ══════════════════════════════════════════════════════════

/// 단골 등급 응답 모델 (WOW#5, 2026-05-31 추가)
///
/// [규칙 — 백엔드 restaurants.service.ts resolveLoyaltyRank 와 1:1]
///   0~2회 → NORMAL  (흰 배경 뱃지)
///   3~4회 → REGULAR (주황 뱃지)
///   5회+  → VIP     (금색 뱃지)
///
/// [isFirstTime]
///   visitCount == 1 일 때 true. 픽업 완료 직후 토스트 카피
///   "이번이 첫 방문이에요" 용. 헤더 뱃지에서는 사용 안 함.
class LoyaltyDto {
  const LoyaltyDto({
    required this.visitCount,
    required this.rank,
    required this.isFirstTime,
  });

  /// 누적 픽업 횟수 (orders.status='COMPLETED' 기준).
  final int visitCount;

  /// 'NORMAL' | 'REGULAR' | 'VIP' (백엔드 문자열 그대로).
  final String rank;

  final bool isFirstTime;

  /// 픽업 완료 직후 토스트에서 쓸 친근 카피.
  ///   - 1회: "이 식당의 첫 손님이 되셨어요"
  ///   - 2~4회: "이 식당의 N번째 방문이에요"
  ///   - 5회+: "VIP 단골이 되셨어요!"
  String toastMessage() {
    if (visitCount <= 0) return '';
    if (visitCount == 1) return '🎉 이 식당의 첫 손님이 되셨어요';
    if (rank == 'VIP') return '🏆 VIP 단골이 되셨어요! ($visitCount번째 방문)';
    return '🎉 이 식당의 $visitCount번째 단골이 되셨어요';
  }

  factory LoyaltyDto.fromJson(Map<String, dynamic> json) {
    return LoyaltyDto(
      visitCount: (json['visitCount'] as num?)?.toInt() ?? 0,
      rank: (json['rank'] as String?) ?? 'NORMAL',
      isFirstTime: (json['isFirstTime'] as bool?) ?? false,
    );
  }
}

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
    this.todaysNote,
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

  /// 사장님 "오늘의 한 줄" 메시지 (200자 이하)
  ///
  /// [출처 및 흐름 — 2026-05-31 WOW#1]
  ///   사장(LSPOS 대시보드/사장앱) → PATCH /pos/restaurants/:id/todays-note
  ///   → restaurants.todays_note → RestaurantsService → 본 DTO.
  ///
  /// UI:
  ///   · null 이면 노란 띠 미노출 (기존 카드 디자인 유지)
  ///   · 값이 있으면 추천 카드/상세 헤더 상단에 #FFF3CD 배경 인용구.
  ///
  /// 백엔드 정책:
  ///   · 빈 문자열은 백엔드에서 null 로 정규화됨 — 클라이언트는 그대로 신뢰.
  ///   · 200자 초과는 백엔드 400 에러로 차단되어 손님 측엔 항상 200자 이하.
  final String? todaysNote;

  factory RestaurantDto.fromJson(Map<String, dynamic> json) {
    // 2026-05-31 WOW#1 todaysNote 정규화 헬퍼.
    // 백엔드가 빈 문자열을 null 로 정규화하지만, 다른 어댑터(POSjihyo 등)에서
    // 빈 문자열이 들어와도 trim 후 null 로 일관 처리한다.
    String? parseTodaysNote(dynamic raw) {
      if (raw is String && raw.trim().isNotEmpty) return raw;
      return null;
    }

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
      todaysNote: parseTodaysNote(json['todaysNote']),
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
  //
  // [throwOnError — 2026-05-31 한성대 시연 대비]
  //   false(기본): 네트워크 오류 시 빈 배열([]) 반환 — 기존 호출자 호환.
  //   true        : 재시도까지 다 실패하면 ApiNetworkException 을 그대로
  //                 throw. 호출 측(토너먼트 등)이 "후보 0개"와 "통신 오류"를
  //                 구분해 다른 안내를 띄울 수 있게 한다.
  //   ※ 어느 경우든 ApiRetry.get 이 내부에서 2~3회 자동 재시도하므로
  //     공용 와이파이/핫스팟이 잠깐 깜빡여도 대부분 자동 복구된다.
  Future<List<RestaurantDto>> getRestaurants({
    required String accessToken,
    String? category,
    int? maxPrice,
    int? limit,
    bool throwOnError = false,
  }) async {
    try {
      final params = <String, String>{};
      if (category != null) params['category'] = category;
      if (maxPrice != null) params['maxPrice'] = maxPrice.toString();
      if (limit != null) params['limit'] = limit.toString();

      final uri = Uri.parse('${AppConfig.backendBaseUrl}/restaurants')
          .replace(queryParameters: params.isNotEmpty ? params : null);

      final response = await ApiRetry.get(
        uri,
        headers: _headers(accessToken),
        timeout: AppConfig.apiTimeout,
      );
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
      // 네트워크 오류를 호출 측에 알려야 하는 경우(토너먼트 등)는 재던짐.
      if (throwOnError && e is ApiNetworkException) rethrow;
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
      final response = await ApiRetry.get(
        Uri.parse('${AppConfig.backendBaseUrl}/restaurants/$restaurantId'),
        headers: _headers(accessToken),
        timeout: AppConfig.apiTimeout,
      );
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

  // ── GET /api/restaurants/:id/loyalty (WOW#5, 2026-05-31) ──
  //
  // 손님의 이 식당 누적 방문(픽업 완료) 횟수 + 등급 조회.
  // 식당 상세 헤더 뱃지 / 픽업 완료 토스트에서 호출.
  //
  // 실패 시 null — UI 는 뱃지를 그리지 않고 graceful 하게 폴백.
  Future<LoyaltyDto?> getLoyalty({
    required String accessToken,
    required String restaurantId,
    required String userId,
  }) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.backendBaseUrl}/restaurants/$restaurantId/loyalty',
      ).replace(queryParameters: {'userId': userId});

      final response = await ApiRetry.get(
        uri,
        headers: _headers(accessToken),
        timeout: AppConfig.apiTimeout,
      );
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        // 백엔드가 success:false 로 떨어뜨릴 수도 있음(userId 누락 등) — 방어.
        if (json['success'] == false) return null;
        final data = json['data'] as Map<String, dynamic>?;
        if (data == null) return null;
        return LoyaltyDto.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('[RestaurantsApiService] getLoyalty 에러: $e');
      return null;
    }
  }

  // ── GET /api/restaurants/:id/menus ────────────────────
  // 백엔드 응답 구조: data: { categories: [...], menus: [...] }
  // (배열이 아니라 래퍼 객체라서 data.menus를 꺼내서 매핑)
  Future<List<MenuItemDto>> getMenus({
    required String accessToken,
    required String restaurantId,
    bool throwOnError = false,
  }) async {
    try {
      final response = await ApiRetry.get(
        Uri.parse(
            '${AppConfig.backendBaseUrl}/restaurants/$restaurantId/menus'),
        headers: _headers(accessToken),
        timeout: AppConfig.apiTimeout,
      );
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
      // 네트워크 오류를 호출 측에 알려야 하는 경우(메뉴 토너먼트 등)는 재던짐.
      if (throwOnError && e is ApiNetworkException) rethrow;
      return [];
    }
  }
}
