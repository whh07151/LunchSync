import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

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
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/invitations'),
        headers: _headers(accessToken),
        body: jsonEncode({'sessionId': sessionId}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return InvitationInfo.fromJson(json['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[InvitationsApiService] createInvitation 에러: $e');
      return null;
    }
  }

  // ── POST /api/invitations/:code/accept ────────────────
  Future<bool> acceptInvitation({
    required String accessToken,
    required String code,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/invitations/$code/accept'),
        headers: _headers(accessToken),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}
