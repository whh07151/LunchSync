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
  Future<Session?> createSession({
    required String accessToken,
    required String name,
    String? scheduledAt,
  }) async {
    try {
      final body = <String, dynamic>{'name': name};
      if (scheduledAt != null) body['scheduledAt'] = scheduledAt;

      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions'),
        headers: _headers(accessToken),
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return Session.fromJson(json['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[SessionsApiService] createSession 에러: $e');
      return null;
    }
  }

  // ── GET /api/sessions/today ───────────────────────────
  Future<List<Session>> getTodaySessions({
    required String accessToken,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions/today'),
        headers: _headers(accessToken),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final list = json['data'] as List<dynamic>;
        return list
            .map((e) => Session.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('[SessionsApiService] getTodaySessions 에러: $e');
      return [];
    }
  }

  // ── GET /api/sessions/:id ─────────────────────────────
  Future<Session?> getSessionById({
    required String accessToken,
    required String sessionId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId'),
        headers: _headers(accessToken),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return Session.fromJson(json['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[SessionsApiService] getSessionById 에러: $e');
      return null;
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
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId/members'),
        headers: _headers(accessToken),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        // data가 { totalCount, joinedCount, members[] } 구조
        return SessionMembersResponse.fromJson(
            json['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[SessionsApiService] getSessionMembers 에러: $e');
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
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId/members'),
        headers: _headers(accessToken),
        body: jsonEncode({'userId': userId}),
      );
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
      final response = await http.delete(
        Uri.parse(
            '${AppConfig.backendBaseUrl}/sessions/$sessionId/members/$userId'),
        headers: _headers(accessToken),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
