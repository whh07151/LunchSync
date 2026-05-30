// ══════════════════════════════════════════════════════════
// 파일 역할: 토너먼트 결과/트렌딩 API 호출 서비스 (WOW#6 + WOW#9)
//
// 담당 엔드포인트:
//   POST /api/tournaments
//     - 토너먼트 우승 결과 1건 기록.
//     - body: { mode, winnerRestaurantId?, winnerMenuId?, candidateCount, durationMs }
//     - 201 Created → { success, data: { id } }
//
//   GET /api/tournaments/trending?limit=5&days=7
//     - 최근 N일 동안 우승 빈도 상위 N개 식당.
//     - 200 OK → { success, data: TrendingRestaurantDto[] }
//
// 흐름:
//   - 로그인 사용자의 JWT(accessToken) 를 Authorization 헤더로 전달.
//   - POST 는 백그라운드 호출 — 실패해도 UX 막지 않도록 void/bool 반환.
//   - GET 은 실패 시 빈 리스트로 폴백(섹션 자체가 0개일 때와 동일하게 숨김).
//
// 에러 처리 정책:
//   - 네트워크/타임아웃은 catch 후 false / 빈 리스트.
//   - 401 응답은 ApiAuthHooks.check 가 글로벌 로그아웃 처리.
//   - 본 화면(홈/우승 화면)에는 SnackBar 등 사용자 피드백 없음 (조용한 실패).
// ══════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../core/api/api_auth_hooks.dart';
import '../core/api/http_headers_helper.dart';
import '../core/config/app_config.dart';

/// 토너먼트 모드 — 백엔드 enum 과 동일 문자열.
enum TournamentApiMode {
  restaurant,
  menu,
}

/// 트렌딩 식당 1개 데이터 (백엔드 TrendingRestaurantDto 와 1:1 매칭).
///
/// 필드 의미:
///   restaurantId — 식당 UUID (탭하면 식당 상세로 이동)
///   name         — 식당 이름
///   category     — 카테고리(한식/중식 등) — null 가능 → FoodImage 폴백
///   imageUrl     — 대표 이미지 URL — null 가능 → FoodImage 가 이모지로 폴백
///   winCount     — 이번 주(또는 N일) 우승 횟수
class TrendingRestaurantDto {
  const TrendingRestaurantDto({
    required this.restaurantId,
    required this.name,
    required this.category,
    required this.imageUrl,
    required this.winCount,
  });

  final String restaurantId;
  final String name;
  final String? category;
  final String? imageUrl;
  final int winCount;

  /// 백엔드 응답 JSON → DTO 변환.
  /// 방어적 캐스트 — 키 누락 시 안전한 기본값 사용.
  factory TrendingRestaurantDto.fromJson(Map<String, dynamic> json) {
    return TrendingRestaurantDto(
      restaurantId: json['restaurantId'] as String,
      name: (json['name'] as String?) ?? '이름 없음',
      category: json['category'] as String?,
      imageUrl: json['imageUrl'] as String?,
      winCount: (json['winCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class TournamentsApiService {
  const TournamentsApiService();

  // ── POST /api/tournaments — 우승 결과 1건 저장 ──────────
  //
  // 백그라운드 호출 의도 — 실패해도 우승 화면 UX 를 막지 않는다.
  // 반환:
  //   true  — 201 Created 정상.
  //   false — 네트워크/서버 오류 (호출자는 무시).
  //
  // 인자 정책:
  //   - winnerRestaurantId : 식당 모드는 필수, 메뉴 모드도 가능한 한 전달
  //     (백엔드 트렌딩 집계가 winner_restaurant_id 기준이므로 메뉴 모드도 채움 권장).
  //   - winnerMenuId       : 메뉴 모드일 때만 필요.
  //   - candidateCount / durationMs : 분석용 보조 — null 이면 그대로 전송 안 함.
  Future<bool> postResult({
    required String accessToken,
    required TournamentApiMode mode,
    String? winnerRestaurantId,
    String? winnerMenuId,
    int? candidateCount,
    int? durationMs,
  }) async {
    try {
      // mode enum → 백엔드 문자열로 직접 매핑 (toString 의존 회피).
      final modeString =
          mode == TournamentApiMode.restaurant ? 'restaurant' : 'menu';

      // null 값은 JSON 에 포함하지 않음 — 백엔드 ValidationPipe whitelist 친화.
      final body = <String, dynamic>{'mode': modeString};
      if (winnerRestaurantId != null && winnerRestaurantId.isNotEmpty) {
        body['winnerRestaurantId'] = winnerRestaurantId;
      }
      if (winnerMenuId != null && winnerMenuId.isNotEmpty) {
        body['winnerMenuId'] = winnerMenuId;
      }
      if (candidateCount != null) {
        body['candidateCount'] = candidateCount;
      }
      if (durationMs != null) {
        body['durationMs'] = durationMs;
      }

      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/tournaments'),
            headers: apiHeaders(accessToken),
            body: jsonEncode(body),
          )
          .timeout(AppConfig.apiTimeout);

      // 401 자동 로그아웃 글로벌 훅 (다른 서비스와 동일 패턴).
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }

      // 400/5xx — 분석용 로그만 남기고 false.
      debugPrint(
        '[TournamentsApiService] postResult 실패: '
        '${response.statusCode} ${response.body}',
      );
      return false;
    } catch (e) {
      // 네트워크/타임아웃/JSON encode 실패 — 모두 조용히 false.
      debugPrint('[TournamentsApiService] postResult 에러: $e');
      return false;
    }
  }

  // ── GET /api/tournaments/trending — 트렌딩 식당 조회 ────
  //
  // 반환:
  //   - 성공: TrendingRestaurantDto 리스트 (winCount desc).
  //   - 실패: 빈 리스트 → 호출자가 섹션 자체를 숨겨 UX 안전.
  //
  // 파라미터:
  //   limit (1~20, 기본 5) — 홈 가로 스크롤 권장 5개.
  //   days  (1~30, 기본 7) — "이번 주" 기준.
  //   백엔드가 clamp 하므로 클라이언트도 그대로 전달.
  Future<List<TrendingRestaurantDto>> getTrending({
    required String accessToken,
    int limit = 5,
    int days = 7,
  }) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.backendBaseUrl}/tournaments/trending'
        '?limit=$limit&days=$days',
      );

      final response = await http
          .get(uri, headers: apiHeaders(accessToken))
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (json['data'] as List<dynamic>?) ?? const [];
        return list
            .map((e) => TrendingRestaurantDto.fromJson(
                  e as Map<String, dynamic>,
                ))
            .toList();
      }

      debugPrint(
        '[TournamentsApiService] getTrending 실패: ${response.statusCode}',
      );
      return const [];
    } catch (e) {
      debugPrint('[TournamentsApiService] getTrending 에러: $e');
      return const [];
    }
  }
}
