// ══════════════════════════════════════════════════════════
// 파일 역할: CORE-09 메뉴 알레르기 충돌 검증 API 호출 서비스
//
// 담당 엔드포인트:
//   GET /api/menus/restaurant/:restaurantId/check-allergens?userId=
//     - 사용자가 등록한 알레르기와 식당 메뉴들의 알레르기 교집합 조회.
//     - 200 OK → { success, data: { conflicts: [...] } }
//
// 흐름:
//   - 손님앱 메뉴 화면(CU-16) 진입 시 1회 호출.
//   - 메뉴 목록(restaurants_api_service.getMenus) 이 도착한 다음에
//     호출해야 menuId 기준으로 카드 위에 ⚠️ 배지를 합칠 수 있음.
//
// 에러 처리 정책:
//   - 401 — ApiAuthHooks.check 가 글로벌 로그아웃 처리.
//   - 그 외 실패(네트워크/타임아웃/500) 는 catch 후 빈 conflicts 폴백.
//     → 알레르기 표시는 부가 기능이라 사용자 흐름을 막지 않는다.
// ══════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;

import '../core/api/api_auth_hooks.dart';
import '../core/api/api_retry.dart';
import '../core/api/http_headers_helper.dart';
import '../core/config/app_config.dart';

/// 단일 메뉴 충돌 정보 DTO — 백엔드 MenuAllergenConflict 와 1:1.
class MenuAllergenConflictDto {
  const MenuAllergenConflictDto({
    required this.menuId,
    required this.name,
    required this.matchedAllergens,
  });

  /// 메뉴 UUID — 화면에서 카드와 매칭할 키.
  final String menuId;

  /// 메뉴 이름 — BottomSheet 상단에 표시.
  final String name;

  /// 사용자 알레르기와 정확 매칭된 키워드 배열.
  /// 예: ['nuts', 'egg']. 빈 배열로 내려오는 경우는 없음 (서버가 필터).
  final List<String> matchedAllergens;

  factory MenuAllergenConflictDto.fromJson(Map<String, dynamic> json) {
    final raw = json['matchedAllergens'] as List<dynamic>? ?? const [];
    return MenuAllergenConflictDto(
      menuId: json['menuId'] as String,
      name: json['name'] as String,
      matchedAllergens: raw.map((e) => e as String).toList(),
    );
  }
}

/// CORE-09 검증 API 클라이언트.
class MenusApiService {
  const MenusApiService();

  /// 식당 + 사용자 쌍에 대한 알레르기 충돌 메뉴 목록 조회.
  ///
  /// [반환]
  ///   - 200 OK: 백엔드 conflicts 배열 매핑 결과.
  ///   - 그 외/예외: 빈 리스트 폴백 (사용자 흐름 비차단).
  ///
  /// [accessToken]
  ///   - userProvider.accessToken — 누락 시 호출 자체 건너뛰는 책임은 호출부.
  ///
  Future<List<MenuAllergenConflictDto>> checkAllergens({
    required String accessToken,
    required String restaurantId,
  }) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.backendBaseUrl}/menus/restaurant/$restaurantId/check-allergens',
      );

      final response = await ApiRetry.get(
        uri,
        headers: apiHeaders(accessToken),
        timeout: AppConfig.apiTimeout,
      );
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode != 200) {
        return const [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      // success:false 도 방어 — 백엔드가 BadRequest(400) 가 아닌 200 + false
      // 로 떨어뜨릴 가능성은 낮지만 일관성 차원에서 한 번 더 가드.
      if (json['success'] == false) return const [];
      final data = json['data'] as Map<String, dynamic>? ?? const {};
      final list = data['conflicts'] as List<dynamic>? ?? const [];
      return list
          .map((e) =>
              MenuAllergenConflictDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[MenusApiService] CHECK_ALLERGENS_FAILED');
      return const [];
    }
  }
}
