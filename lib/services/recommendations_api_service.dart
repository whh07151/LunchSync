import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import '../core/config/app_config.dart';
import '../core/api/api_auth_hooks.dart';
import '../core/api/api_retry.dart';

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
/// recentVisitHint: CU-21 최근 식사 이력 hint
///   - 'RECENT_3D' : 최근 3일 내 방문 (강한 회피 -20점 적용)
///   - 'RECENT_7D' : 최근 7일 내 방문 (-10점)
///   - null        : 식사 이력 없음
///
/// 백엔드 응답에 hint 필드가 없는 구버전에서도 안전하게 null 로 폴백.
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
    this.recentVisitHint,
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
  // CU-21: 최근 방문 hint ('RECENT_3D' / 'RECENT_7D' / null)
  // 배지/칩 표시에 사용.
  final String? recentVisitHint;

  /// 최근에 다녀왔는지(3일/7일 통합) — UI 배지 노출 조건.
  bool get isRecentlyVisited =>
      recentVisitHint == 'RECENT_3D' || recentVisitHint == 'RECENT_7D';

  factory RecommendationDto.fromJson(Map<String, dynamic> json) {
    // reasons는 항상 배열이지만 방어적으로 안전 처리
    final reasonsRaw = json['reasons'];
    final reasons = reasonsRaw is List
        ? reasonsRaw.map((e) => e.toString()).toList()
        : <String>[];

    // recentVisitHint: 구버전 백엔드 호환을 위해 누락 시 null 폴백.
    // 잘못된 값은 무시(허용 enum 외에는 null 로 취급).
    final hintRaw = json['recentVisitHint'];
    final String? hint = (hintRaw == 'RECENT_3D' || hintRaw == 'RECENT_7D')
        ? hintRaw as String
        : null;

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
      recentVisitHint: hint,
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
      final response = await ApiRetry.get(
        Uri.parse(
            '${AppConfig.backendBaseUrl}/sessions/$sessionId/recommendations'),
        headers: _headers(accessToken),
        // 추천은 LLM 호출 가능성 있어 길게 (15s)
        timeout: const Duration(seconds: 15),
      );
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final list = json['data'] as List<dynamic>;

        // ── CU-21 metadata.recentPenalty 디버그 로그 ─────
        // 응답 봉투에 metadata 가 있으면 어느 식당이 -10/-20 감점을 받았는지
        // 콘솔에서 확인 가능. UI 칩 표시는 RecommendationDto.recentVisitHint
        // 기반으로 이뤄지므로 여기서는 가시성만 확보.
        final metadata = json['metadata'];
        if (metadata is Map<String, dynamic>) {
          final penalty = metadata['recentPenalty'];
          if (penalty is Map && penalty.isNotEmpty) {
            debugPrint(
              '[RecommendationsApiService] RECENT_PENALTY_APPLIED_${penalty.length}',
            );
          }
        }

        return list
            .map((e) => RecommendationDto.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[RecommendationsApiService] GET_RECOMMENDATIONS_FAILED');
      return [];
    }
  }
}
