import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: AI 추천(CORE-07/08) API 호출 서비스
//
// 담당 엔드포인트:
//   GET /api/sessions/:id/recommendations — 세션 기반 그룹 추천
//
// 백엔드 응답 DTO:
//   { restaurantId, name, category, priceRange, address, score, reasons[] }
// ══════════════════════════════════════════════════════════

/// 추천 결과 하나
///
/// score: 추천 점수 (높을수록 상위)
/// reasons: 추천 근거 문구 리스트 (예: ["전원 예산 범위 내", "알레르기 없음"])
class RecommendationDto {
  const RecommendationDto({
    required this.restaurantId,
    required this.name,
    required this.category,
    required this.priceRange,
    required this.address,
    required this.lat,
    required this.lng,
    required this.score,
    required this.reasons,
  });

  final String restaurantId;
  final String name;
  final String? category;
  final int? priceRange;
  final String? address;
  final double? lat;   // 지도 표시용 좌표
  final double? lng;
  final int score;
  final List<String> reasons;

  factory RecommendationDto.fromJson(Map<String, dynamic> json) {
    // reasons는 항상 배열이지만 방어적으로 안전 처리
    final reasonsRaw = json['reasons'];
    final reasons = reasonsRaw is List
        ? reasonsRaw.map((e) => e.toString()).toList()
        : <String>[];

    return RecommendationDto(
      restaurantId: json['restaurantId'] as String,
      name: json['name'] as String,
      category: json['category'] as String?,
      priceRange: json['priceRange'] as int?,
      address: json['address'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      score: (json['score'] as num?)?.toInt() ?? 0,
      reasons: reasons,
    );
  }
}

class RecommendationsApiService {
  const RecommendationsApiService();

  Map<String, String> _headers(String accessToken) => {
        'Authorization': 'Bearer $accessToken',
      };

  // ── GET /api/sessions/:id/recommendations ────────────
  // 세션 멤버 전원의 프로필을 기반으로 점수화된 식당 리스트 반환.
  // 상위 10개까지 반환되며 score 내림차순 정렬.
  Future<List<RecommendationDto>> getRecommendations({
    required String accessToken,
    required String sessionId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
            '${AppConfig.backendBaseUrl}/sessions/$sessionId/recommendations'),
        headers: _headers(accessToken),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final list = json['data'] as List<dynamic>;
        return list
            .map((e) => RecommendationDto.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[RecommendationsApiService] getRecommendations 에러: $e');
      return [];
    }
  }
}
