import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../core/api/api_auth_hooks.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 식당 크롤링 API 호출 서비스
//
// 담당 엔드포인트:
//   POST /api/crawl/restaurants  { lat, lng, radius? }
//     → 카카오 로컬 API로 반경 내 음식점 조회
//     → 네이버 플레이스에서 메뉴 상세 추가
//     → Supabase restaurants / menu_items 테이블에 upsert
//
// 용도:
//   세션 생성 직후 호스트의 GPS 좌표로 호출하여 "우리 앱이 알고 있는 식당"을
//   주변 실제 식당으로 채움. 그 후 추천 엔진이 이 데이터를 기반으로 점수화.
//
// 주의:
//   - 응답 지연이 길 수 있음 (네이버 상세 fetch 병렬) → 호출은 비동기로 fire-and-forget
//   - 이미 DB에 있는 식당은 중복 insert 대신 최신 정보로 덮어쓰기
// ══════════════════════════════════════════════════════════

class CrawlResult {
  const CrawlResult({
    required this.totalSearched,
    required this.successCount,
    required this.failedCount,
  });

  final int totalSearched;
  final int successCount;
  final int failedCount;

  factory CrawlResult.fromJson(Map<String, dynamic> json) {
    return CrawlResult(
      totalSearched: (json['totalSearched'] as num?)?.toInt() ?? 0,
      successCount: (json['successCount'] as num?)?.toInt() ?? 0,
      failedCount: (json['failedCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class CrawlApiService {
  const CrawlApiService();

  Map<String, String> _headers(String accessToken) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

  /// 주변 식당 크롤링 트리거
  ///
  /// - lat/lng: 호스트 현재 GPS 좌표
  /// - radius: 미터 단위 (기본 1000m)
  ///
  /// 실패 시 null 반환 — fire-and-forget 용도라 앱 흐름엔 영향 없음.
  Future<CrawlResult?> crawlRestaurants({
    required String accessToken,
    required double lat,
    required double lng,
    int radius = 1000,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/crawl/restaurants'),
            headers: _headers(accessToken),
            body: jsonEncode({
              'lat': lat,
              'lng': lng,
              'radius': radius,
            }),
          )
          // 크롤링은 카카오 + 네이버 + Gemini AI 호출까지 길어질 수 있음
          .timeout(const Duration(seconds: 30));
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return CrawlResult.fromJson(json['data'] as Map<String, dynamic>);
      }
      debugPrint('[CrawlApiService] 응답 실패: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[CrawlApiService] crawlRestaurants 에러: $e');
      return null;
    }
  }
}
