import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../core/api/api_auth_hooks.dart';
import '../core/api/api_retry.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 즐겨찾기 API 호출 서비스 (배민 패턴 — 2026-05-15 발전)
//
// 담당 엔드포인트:
//   POST   /api/users/me/favorites              — 식당 즐겨찾기 추가
//   DELETE /api/users/me/favorites/:restaurantId — 제거
//   GET    /api/users/me/favorites              — 내 즐겨찾기 목록
//
// 데이터 모델:
//   - users.favorites JSONB (식당 ID 배열, 추가 순)
//   - 최대 100개 한도 (백엔드 검증)
//
// 화면 사용:
//   - restaurant_detail_screen: 우상단 하트 아이콘 토글
//   - home_screen (옵션): "내 즐겨찾기" 위젯 (향후)
// ══════════════════════════════════════════════════════════

/// 즐겨찾기 식당 단건
class FavoriteDto {
  const FavoriteDto({
    required this.id,
    required this.name,
    required this.category,
    this.address,
    this.imageUrl,
    this.rating,
  });

  final String id;
  final String name;
  final String category;
  final String? address;
  final String? imageUrl;
  final double? rating;

  factory FavoriteDto.fromJson(Map<String, dynamic> json) {
    return FavoriteDto(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '식당',
      category: (json['category'] as String?) ?? '기타',
      address: json['address'] as String?,
      imageUrl: json['imageUrl'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
    );
  }
}

class FavoritesApiService {
  const FavoritesApiService();

  Map<String, String> _headers(String accessToken) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

  // ── POST /favorites — 즐겨찾기 추가 ───────────────────
  // 성공: 갱신된 즐겨찾기 식당 ID 배열 반환
  // 409 (한도 초과): null + 메시지 — 호출부가 토스트
  Future<List<String>?> add({
    required String accessToken,
    required String restaurantId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/users/me/favorites'),
            headers: _headers(accessToken),
            body: jsonEncode({'restaurantId': restaurantId}),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>;
        final list = (data['favorites'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList();
        return list;
      }
      debugPrint(
        '[FavoritesApi] add 실패: ${response.statusCode} ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[FavoritesApi] add 예외: $e');
      return null;
    }
  }

  // ── DELETE /favorites/:id — 제거 ──────────────────────
  Future<List<String>?> remove({
    required String accessToken,
    required String restaurantId,
  }) async {
    try {
      final response = await http
          .delete(
            Uri.parse(
                '${AppConfig.backendBaseUrl}/users/me/favorites/$restaurantId'),
            headers: _headers(accessToken),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>;
        final list = (data['favorites'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList();
        return list;
      }
      debugPrint(
        '[FavoritesApi] remove 실패: ${response.statusCode} ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[FavoritesApi] remove 예외: $e');
      return null;
    }
  }

  // ── GET /favorites — 목록 (식당 정보 join) ─────────────
  Future<List<FavoriteDto>> list({required String accessToken}) async {
    try {
      final response = await ApiRetry.get(
        Uri.parse('${AppConfig.backendBaseUrl}/users/me/favorites'),
        headers: _headers(accessToken),
        timeout: AppConfig.apiTimeout,
      );
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (json['data'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(FavoriteDto.fromJson)
            .toList();
        return list;
      }
      debugPrint(
        '[FavoritesApi] list 실패: ${response.statusCode} ${response.body}',
      );
      return const [];
    } catch (e) {
      debugPrint('[FavoritesApi] list 예외: $e');
      return const [];
    }
  }
}
