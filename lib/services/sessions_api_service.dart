import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../core/api/api_auth_hooks.dart';
import '../core/api/api_retry.dart';
import '../core/api/error_message_extractor.dart';
import '../core/api/http_headers_helper.dart';
import '../models/session.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 세션 관련 API 호출 서비스
//
// 담당 엔드포인트:
//   POST   /api/sessions              — 세션 생성
//   GET    /api/sessions/today        — 오늘 내 세션 목록
//   GET    /api/sessions/:id          — 세션 상세
//   PATCH  /api/sessions/:id/status   — 상태 변경
//   DELETE /api/sessions/:id          — 세션 삭제 (호스트, WAITING/DONE 만)
//   GET    /api/sessions/:id/members  — 멤버 목록
//   POST   /api/sessions/:id/members  — 멤버 추가
//   DELETE /api/sessions/:id/members/:userId — 멤버 제거
//   GET    /api/sessions/:id/chemistry — WOW#3 점심 케미 매트릭스
// ══════════════════════════════════════════════════════════

class SessionsApiService {
  const SessionsApiService();

  // 2026-05-30 헤더 빌더 통합: 공통 헬퍼 apiHeaders() 로 이관.
  //   기존 private `_headers()` 는 9개 서비스에 중복 정의되어 있었음.
  //   `lib/core/api/http_headers_helper.dart` 한 곳에서 관리.

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
            headers: apiHeaders(accessToken),
            body: jsonEncode(body),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

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
      final response = await ApiRetry.get(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions/today'),
        headers: apiHeaders(accessToken),
        timeout: AppConfig.apiTimeout,
      );
      ApiAuthHooks.check(response.statusCode);

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
      final response = await ApiRetry.get(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId'),
        headers: apiHeaders(accessToken),
        timeout: AppConfig.apiTimeout,
      );
      ApiAuthHooks.check(response.statusCode);

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
    final result = await updateSessionStatusDetailed(
      accessToken: accessToken,
      sessionId: sessionId,
      status: status,
    );
    return result.isSuccess;
  }

  // ── PATCH /api/sessions/:id/status (상세 응답) ─────────
  // 2026-05-13 추가: 단순 bool 만으로는 "왜 실패했는지" 알 수 없어
  // 호스트가 아닌 사용자에게도 "호스트만 시작할 수 있어요" 가 떠서 진단이 어려웠음.
  // 백엔드가 던지는 401/403/400/404 를 상태코드/메시지로 그대로 전달해
  // UI 가 정확한 안내(재로그인/상태 오류/세션 없음 등) 를 보여줄 수 있게 함.
  Future<SessionStatusUpdateResult> updateSessionStatusDetailed({
    required String accessToken,
    required String sessionId,
    required String status,
  }) async {
    try {
      final response = await http
          .patch(
            Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId/status'),
            headers: apiHeaders(accessToken),
            body: jsonEncode({'status': status}),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return const SessionStatusUpdateResult.success();
      }

      // 백엔드 에러 메시지 추출 (NestJS 표준 응답 구조)
      String message;
      switch (response.statusCode) {
        case 401:
          // 친근한 안내 + 정확한 사유(로그인 만료) 유지
          message = '로그인이 풀렸어요. 다시 로그인하고 시도해봐요';
          break;
        case 403:
          // 권한 부족 — 누가 가능한지 + 다음 액션(방장에게 부탁) 안내
          message = '방장만 투표를 시작할 수 있어요. 방장에게 부탁해봐요!';
          break;
        case 404:
          // 세션 자체가 사라진 경우 — 새로고침이라는 다음 액션 유도
          message = '세션이 사라졌어요. 화면을 새로고침해봐요';
          break;
        case 400:
          // 상태 전이 불가 — 가장 흔한 원인(이미 진행 중)을 함께 안내
          message = '지금은 투표를 시작할 수 없어요. 이미 진행 중인지 확인해봐요';
          break;
        default:
          message = '투표 시작이 안 됐어요. 잠시 후 다시 시도해봐요';
      }
      // 백엔드가 더 구체적인 message 를 내려주면 그걸 우선 사용
      // (공용 헬퍼가 String / List<String> / 빈 문자열을 일괄 처리)
      final backendMsg = extractApiErrorMessage(response.body);
      if (backendMsg != null) {
        message = backendMsg;
      }

      debugPrint(
        '[SessionsApiService] updateSessionStatus 실패: '
        '${response.statusCode} body=${response.body}',
      );
      return SessionStatusUpdateResult.failure(
        statusCode: response.statusCode,
        message: message,
      );
    } catch (e) {
      debugPrint('[SessionsApiService] updateSessionStatus 예외: $e');
      // 네트워크 오류 — 인터넷 점검이라는 다음 액션 안내
      return const SessionStatusUpdateResult.failure(
        statusCode: 0,
        message: '서버에 닿지 못했어요. 인터넷 연결을 확인해봐요',
      );
    }
  }

  // ── DELETE /api/sessions/:id ──────────────────────────
  // 사장님 시연 피드백(2026-05-13) 반영 — 잘못 만든 세션 삭제.
  // 백엔드 권한 정책:
  //   - 호스트만 가능 (403)
  //   - WAITING / DONE 상태에서만 가능 (400)
  //   - 인증 만료 (401), 세션 없음 (404)
  //
  // 반환 타입은 SessionDeleteResult — 단순 bool 대신 statusCode/message 를
  // 함께 전달해 UI 가 정확한 안내(재로그인/상태 오류/방장만 가능 등)를 띄울 수 있게 함.
  Future<SessionDeleteResult> deleteSession({
    required String accessToken,
    required String sessionId,
  }) async {
    try {
      final response = await http
          .delete(
            Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId'),
            headers: apiHeaders(accessToken),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200 || response.statusCode == 204) {
        return const SessionDeleteResult.success();
      }

      // HTTP 상태별 한국어 메시지 — 친근 톤 유지
      String message;
      switch (response.statusCode) {
        case 401:
          message = '로그인이 풀렸어요. 다시 로그인하고 시도해봐요';
          break;
        case 403:
          message = '방장만 세션을 삭제할 수 있어요';
          break;
        case 400:
          message = '투표/주문이 진행 중인 세션은 삭제할 수 없어요. 세션을 종료한 뒤 다시 시도해봐요';
          break;
        case 404:
          message = '이미 삭제된 세션이에요. 화면을 새로고침해봐요';
          break;
        default:
          message = '세션을 삭제하지 못했어요. 잠시 후 다시 시도해봐요';
      }
      // 백엔드 message 우선 사용
      // (공용 헬퍼가 String / List<String> / 빈 문자열을 일괄 처리)
      final backendMsg = extractApiErrorMessage(response.body);
      if (backendMsg != null) {
        message = backendMsg;
      }

      debugPrint(
        '[SessionsApiService] deleteSession 실패: '
        '${response.statusCode} body=${response.body}',
      );
      return SessionDeleteResult.failure(
        statusCode: response.statusCode,
        message: message,
      );
    } catch (e) {
      debugPrint('[SessionsApiService] deleteSession 예외: $e');
      return const SessionDeleteResult.failure(
        statusCode: 0,
        message: '서버에 닿지 못했어요. 인터넷 연결을 확인해봐요',
      );
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
      final response = await ApiRetry.get(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId/members'),
        headers: apiHeaders(accessToken),
        timeout: AppConfig.apiTimeout,
      );
      ApiAuthHooks.check(response.statusCode);

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
            headers: apiHeaders(accessToken),
            body: jsonEncode({'userId': userId}),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // ── GET /api/sessions/:id/chemistry ───────────────────
  // WOW 포인트 #3 점심 케미 매트릭스 — 그룹 점수/한 줄 라벨/톤/카테고리 칩.
  //
  // 백엔드 응답:
  //   - 정상: { success: true, data: { score, label, tone, topCategories[] } }
  //   - 데이터 없음 / Gemini 실패: { success: true, data: null }
  //     → 호출측은 null 이면 케미 카드 자체를 미노출 (장애 차단 정책).
  //
  // 본 메서드는 어떤 종류의 예외에도 null 을 반환 → 추천 화면 렌더링을
  // 절대 막지 않는다. (Gemini 비용/장애에 화면 깨지지 않게)
  Future<ChemistryResult?> getChemistry({
    required String accessToken,
    required String sessionId,
  }) async {
    try {
      final response = await ApiRetry.get(
        Uri.parse(
            '${AppConfig.backendBaseUrl}/sessions/$sessionId/chemistry'),
        headers: apiHeaders(accessToken),
        timeout: AppConfig.apiTimeout,
      );
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode != 200) {
        debugPrint(
            '[SessionsApiService] getChemistry ${response.statusCode} body=${response.body}');
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'];
      if (data is! Map<String, dynamic>) return null; // null 이면 카드 미노출.
      return ChemistryResult.fromJson(data);
    } catch (e) {
      debugPrint('[SessionsApiService] getChemistry 예외: $e');
      return null;
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
            headers: apiHeaders(accessToken),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── GET /api/sessions/:id/invite ──────────────────────
  // WOW#8 친구 초대 시스템 (2026-05-31):
  //   세션 로비의 "친구 초대" 버튼이 호출하는 통합 페이로드 엔드포인트.
  //   기존 POST /invitations 와 다른 점:
  //     - 호스트 아닌 일반 멤버도 호출 가능 (코드 자체가 권한 토큰)
  //     - inviteCode + deepLink + shortLink + expiresAt 4종 한 번에 응답
  //     - share_plus 의 Share.share() 가 그대로 사용할 수 있는 형태
  //   실패 시 null 반환 — 호출부에서 토스트 띄우고 fallback (코드만 복사).
  Future<InviteInfo?> getInviteInfo({
    required String accessToken,
    required String sessionId,
  }) async {
    try {
      final response = await ApiRetry.get(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId/invite'),
        headers: apiHeaders(accessToken),
        timeout: AppConfig.apiTimeout,
      );
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode != 200) {
        debugPrint(
            '[SessionsApiService] getInviteInfo ${response.statusCode} body=${response.body}');
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'];
      if (data is! Map<String, dynamic>) return null;
      return InviteInfo.fromJson(data);
    } catch (e) {
      debugPrint('[SessionsApiService] getInviteInfo 예외: $e');
      return null;
    }
  }
}

// ══════════════════════════════════════════════════════════
// InviteInfo — WOW#8 친구 초대 응답 모델
//
// 백엔드 GET /api/sessions/:id/invite 응답을 그대로 매핑.
// share_plus 의 Share.share() 가 받을 수 있도록 4개 필드를 1:1 보존.
//   - inviteCode : 8자리 hex 코드 (UI 큰 글씨 표시 + Clipboard 복사)
//   - deepLink   : `lunchsync://join?code=XXXXXXXX` (앱 설치자 자동 라우팅용)
//   - shortLink  : `https://lunchsync.duckdns.org/j/XXXXXXXX` (웹 호환)
//   - expiresAt  : ISO8601 만료 시각 (UI "24시간 유효" 문구의 동적 표현)
//
// 방어적 파싱: 한 필드가 비더라도 객체 생성에 실패하지 않도록 ?? 폴백 사용.
// ══════════════════════════════════════════════════════════
class InviteInfo {
  const InviteInfo({
    required this.inviteCode,
    required this.deepLink,
    required this.shortLink,
    this.expiresAt,
  });

  final String inviteCode;
  final String deepLink;
  final String shortLink;
  final String? expiresAt;

  factory InviteInfo.fromJson(Map<String, dynamic> json) {
    return InviteInfo(
      inviteCode: (json['inviteCode'] as String?) ?? '',
      deepLink: (json['deepLink'] as String?) ?? '',
      shortLink: (json['shortLink'] as String?) ?? '',
      expiresAt: json['expiresAt'] as String?,
    );
  }
}


// ══════════════════════════════════════════════════════════
// SessionStatusUpdateResult — updateSessionStatusDetailed() 응답 래퍼
//
// 단순 bool 반환은 "왜 실패했는지" 를 호출부가 알 수 없어 사용자에게
// 잘못된 안내가 나가는 문제(예: 인증 만료인데 "호스트가 아니에요" 토스트)
// 의 원인이 됐다. 이 래퍼는 statusCode + 사람용 메시지를 함께 전달.
// ══════════════════════════════════════════════════════════
class SessionStatusUpdateResult {
  const SessionStatusUpdateResult.success()
      : isSuccess = true,
        statusCode = 200,
        message = null;

  const SessionStatusUpdateResult.failure({
    required this.statusCode,
    required this.message,
  }) : isSuccess = false;

  final bool isSuccess;
  final int statusCode; // 0 = 네트워크/예외, 그 외 = HTTP 상태코드
  final String? message; // UI 토스트에 그대로 표시할 한국어 메시지
}


// ══════════════════════════════════════════════════════════
// SessionDeleteResult — deleteSession() 응답 래퍼
//
// SessionStatusUpdateResult 와 동일 패턴. 호출부가 statusCode 로 분기해
// 정확한 토스트(403 → 방장만, 400 → 진행 중 차단, 401 → 재로그인) 노출 가능.
// ══════════════════════════════════════════════════════════
class SessionDeleteResult {
  const SessionDeleteResult.success()
      : isSuccess = true,
        statusCode = 200,
        message = null;

  const SessionDeleteResult.failure({
    required this.statusCode,
    required this.message,
  }) : isSuccess = false;

  final bool isSuccess;
  final int statusCode; // 0 = 네트워크/예외, 그 외 = HTTP 상태코드
  final String? message; // UI 토스트에 그대로 표시할 한국어 메시지
}


// ══════════════════════════════════════════════════════════
// ChemistryResult — WOW 포인트 #3 점심 케미 매트릭스 응답
//
// 백엔드 ChemistryService 응답을 그대로 매핑. tone 은 카드 색상 분기에 사용:
//   warm    : 빨강 계열(한식/매콤)
//   cool    : 파랑 계열(일식/샐러드)
//   neutral : 회색 계열(기타/데이터 부족)
// score, label 은 카드 본문에 그대로 노출.
// topCategories 는 카드 하단 칩 3개로 표시 (없으면 칩 영역 미노출).
// ══════════════════════════════════════════════════════════
class ChemistryResult {
  const ChemistryResult({
    required this.score,
    required this.label,
    required this.tone,
    required this.topCategories,
  });

  final int score;              // 0~100
  final String label;           // "매콤+가성비형" 같은 한 줄 라벨
  final String tone;            // warm | cool | neutral
  final List<String> topCategories; // 상위 3개 카테고리

  factory ChemistryResult.fromJson(Map<String, dynamic> json) {
    // 방어적 파싱 — 백엔드가 한 필드 누락해도 카드가 깨지지 않게 기본값 채움.
    final rawScore = json['score'];
    final score = (rawScore is num) ? rawScore.round().clamp(0, 100) : 50;
    final rawCats = json['topCategories'];
    final cats = (rawCats is List)
        ? rawCats
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .take(3)
            .toList(growable: false)
        : const <String>[];
    return ChemistryResult(
      score: score,
      label: (json['label'] as String?)?.trim().isNotEmpty == true
          ? (json['label'] as String).trim()
          : '점심 케미',
      tone: (json['tone'] as String?)?.trim().toLowerCase() ?? 'neutral',
      topCategories: cats,
    );
  }
}
