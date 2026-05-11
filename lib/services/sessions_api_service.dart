import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../models/session.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 세션 관련 API 호출 서비스
//
// 담당 엔드포인트:
//   POST   /api/sessions              — 세션 생성
//   GET    /api/sessions/today        — 오늘 내 세션 목록
//   GET    /api/sessions/:id          — 세션 상세
//   PATCH  /api/sessions/:id/status   — 상태 변경
//   GET    /api/sessions/:id/members  — 멤버 목록
//   POST   /api/sessions/:id/members  — 멤버 추가
//   DELETE /api/sessions/:id/members/:userId — 멤버 제거
// ══════════════════════════════════════════════════════════

class SessionsApiService {
  const SessionsApiService();

  Map<String, String> _headers(String accessToken) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

  // ── POST /api/sessions ────────────────────────────────
  // CU-09에서 입력한 세션 조건을 모두 전달.
  // null 필드는 body에서 제외 → 백엔드/DB default 값 사용.
  Future<Session?> createSession({
    required String accessToken,
    required String name,
    String? scheduledAt,
    int? radius,        // 식당 검색 반경 (미터)
    int? budget,        // 1인당 예산 상한 (원)
    int? returnMinutes, // 복귀 여유 시간 (분)
    String? memo,       // 자유 메모
    double? lat,        // 세션 기준 위도 (추천 반경 필터용)
    double? lng,        // 세션 기준 경도 (추천 반경 필터용)
  }) async {
    try {
      final body = <String, dynamic>{'name': name};
      if (scheduledAt != null)    body['scheduledAt']    = scheduledAt;
      if (radius != null)         body['radius']         = radius;
      if (budget != null)         body['budget']         = budget;
      if (returnMinutes != null)  body['returnMinutes']  = returnMinutes;
      if (memo != null && memo.isNotEmpty) body['memo'] = memo;
      // 위치 좌표 — 둘 다 있어야 의미 있음 (한쪽만 들어와도 백엔드는 무시)
      if (lat != null)            body['lat']            = lat;
      if (lng != null)            body['lng']            = lng;

      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/sessions'),
            headers: _headers(accessToken),
            body: jsonEncode(body),
          )
          .timeout(AppConfig.apiTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return Session.fromJson(json['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[SessionsApiService] createSession 에러: $e');
      return null;
    }
  }

  // ── GET /api/sessions/today ───────────────────────────
  Future<List<Session>> getTodaySessions({
    required String accessToken,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.backendBaseUrl}/sessions/today'),
            headers: _headers(accessToken),
          )
          .timeout(AppConfig.apiTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final list = json['data'] as List<dynamic>;
        return list
            .map((e) => Session.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[SessionsApiService] getTodaySessions 에러: $e');
      return [];
    }
  }

  // ── GET /api/sessions/:id ─────────────────────────────
  Future<Session?> getSessionById({
    required String accessToken,
    required String sessionId,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId'),
            headers: _headers(accessToken),
          )
          .timeout(AppConfig.apiTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return Session.fromJson(json['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[SessionsApiService] getSessionById 에러: $e');
      return null;
    }
  }

  // ── PATCH /api/sessions/:id/status ────────────────────
  // 세션 상태 전이 (WAITING → VOTING → ORDERED → DONE).
  // 백엔드가 호스트 권한 + 전이 유효성을 검증. 본 클라이언트는 단순 호출.
  Future<bool> updateSessionStatus({
    required String accessToken,
    required String sessionId,
    required String status,
  }) async {
    try {
      final response = await http
          .patch(
            Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId/status'),
            headers: _headers(accessToken),
            body: jsonEncode({'status': status}),
          )
          .timeout(AppConfig.apiTimeout);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // ── GET /api/sessions/:id/members ─────────────────────
  // 백엔드 응답: { totalCount, joinedCount, members[] }
  // 배열 직접이 아닌 래퍼 객체로 반환됨 → SessionMembersResponse 사용
  Future<SessionMembersResponse?> getSessionMembers({
    required String accessToken,
    required String sessionId,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId/members'),
            headers: _headers(accessToken),
          )
          .timeout(AppConfig.apiTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        // data가 { totalCount, joinedCount, members[] } 구조
        return SessionMembersResponse.fromJson(
            json['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[SessionsApiService] getSessionMembers 에러: $e');
      return null;
    }
  }

  // ── POST /api/sessions/:id/members ────────────────────
  Future<bool> addMember({
    required String accessToken,
    required String sessionId,
    required String userId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId/members'),
            headers: _headers(accessToken),
            body: jsonEncode({'userId': userId}),
          )
          .timeout(AppConfig.apiTimeout);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // ── DELETE /api/sessions/:id/members/:userId ──────────
  Future<bool> removeMember({
    required String accessToken,
    required String sessionId,
    required String userId,
  }) async {
    try {
      final response = await http
          .delete(
            Uri.parse(
                '${AppConfig.backendBaseUrl}/sessions/$sessionId/members/$userId'),
            headers: _headers(accessToken),
          )
          .timeout(AppConfig.apiTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
