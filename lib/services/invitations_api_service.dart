import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../core/api/api_auth_hooks.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 초대 링크 관련 API 호출 서비스
//
// 담당 엔드포인트:
//   POST /api/invitations           — 초대 코드 생성
//   GET  /api/invitations/:code     — 초대 정보 확인
//   POST /api/invitations/:code/accept — 초대 수락
// ══════════════════════════════════════════════════════════

/// 초대 생성 응답 모델
class InvitationInfo {
  const InvitationInfo({
    required this.inviteCode,
    required this.sessionId,
    this.expiresAt,
  });

  final String inviteCode;
  final String sessionId;
  final String? expiresAt;

  factory InvitationInfo.fromJson(Map<String, dynamic> json) {
    return InvitationInfo(
      inviteCode: json['inviteCode'] as String,
      sessionId: json['sessionId'] as String,
      expiresAt: json['expiresAt'] as String?,
    );
  }
}

class InvitationsApiService {
  const InvitationsApiService();

  Map<String, String> _headers(String accessToken) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

  // ── POST /api/invitations ─────────────────────────────
  Future<InvitationInfo?> createInvitation({
    required String accessToken,
    required String sessionId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/invitations'),
            headers: _headers(accessToken),
            body: jsonEncode({'sessionId': sessionId}),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return InvitationInfo.fromJson(json['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[InvitationsApiService] createInvitation 에러: $e');
      return null;
    }
  }

  // ── POST /api/invitations/:code/accept ────────────────
  // 결과 타입:
  //   success   → sessionId 반환
  //   duplicate → 이미 참가한 멤버 (409) — 본인 초대코드 사용 시 포함
  //   invalid   → 코드 없음/만료 등
  Future<AcceptInvitationResult> acceptInvitation({
    required String accessToken,
    required String code,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/invitations/$code/accept'),
            headers: _headers(accessToken),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>;
        return AcceptInvitationResult.success(data['sessionId'] as String);
      }
      if (response.statusCode == 409) {
        return const AcceptInvitationResult.duplicate();
      }
      return const AcceptInvitationResult.invalid();
    } catch (_) {
      return const AcceptInvitationResult.invalid();
    }
  }
}

// ── 초대 수락 결과 타입 ────────────────────────────────────
sealed class AcceptInvitationResult {
  const AcceptInvitationResult();
  const factory AcceptInvitationResult.success(String sessionId) = AcceptSuccess;
  const factory AcceptInvitationResult.duplicate() = AcceptDuplicate;
  const factory AcceptInvitationResult.invalid() = AcceptInvalid;
}

class AcceptSuccess extends AcceptInvitationResult {
  const AcceptSuccess(this.sessionId);
  final String sessionId;
}

class AcceptDuplicate extends AcceptInvitationResult {
  const AcceptDuplicate();
}

class AcceptInvalid extends AcceptInvitationResult {
  const AcceptInvalid();
}
