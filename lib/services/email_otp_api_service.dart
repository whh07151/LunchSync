import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 이메일 OTP 인증 API 호출 서비스
//
// 백엔드 매핑:
//   POST /api/auth/email/send-otp   → sendOtp(email)
//   POST /api/auth/email/verify-otp → verifyOtp(email, code)
//
// 사용 시점:
//   1. signup_screen 에서 회원가입 완료 직후 sendOtp(email)
//   2. email_otp_screen 에서 사용자가 받은 6자리 코드 입력 → verifyOtp
//   3. 검증 성공 시 users.email_verified_at 갱신됨 (백엔드)
// ══════════════════════════════════════════════════════════

/// API 결과 — 성공/실패 + 사용자 메시지를 함께 담아 반환.
class OtpResult {
  const OtpResult({required this.success, this.message});
  final bool success;
  final String? message;

  factory OtpResult.fail(String message) =>
      OtpResult(success: false, message: message);
  factory OtpResult.ok([String? message]) =>
      OtpResult(success: true, message: message);
}

class EmailOtpApiService {
  const EmailOtpApiService();

  /// OTP 발송 요청 — 백엔드가 Supabase Auth 를 통해 이메일 송신.
  /// 가입 안 된 이메일 → 백엔드가 400 BadRequest 반환 → success=false.
  Future<OtpResult> sendOtp(String email) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/auth/email/send-otp'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return OtpResult.ok('인증 메일을 보냈어요. 메일함을 확인해주세요.');
      }

      // 에러 메시지 추출
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final msg = body['message'] as String? ?? '메일 발송에 실패했어요.';
        return OtpResult.fail(msg);
      } catch (_) {
        return OtpResult.fail('메일 발송에 실패했어요. 잠시 후 다시 시도해주세요.');
      }
    } catch (e) {
      // ignore: avoid_print
      print('[EmailOtpApiService] sendOtp 에러: $e');
      return OtpResult.fail('네트워크 오류가 발생했어요.');
    }
  }

  /// 6자리 OTP 검증 — 성공 시 백엔드가 email_verified_at 갱신.
  Future<OtpResult> verifyOtp(String email, String code) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/auth/email/verify-otp'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return OtpResult.ok('이메일 인증이 완료됐어요.');
      }

      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final msg = body['message'] as String? ?? '인증 코드가 올바르지 않아요.';
        return OtpResult.fail(msg);
      } catch (_) {
        return OtpResult.fail('인증 코드가 올바르지 않거나 만료됐어요.');
      }
    } catch (e) {
      // ignore: avoid_print
      print('[EmailOtpApiService] verifyOtp 에러: $e');
      return OtpResult.fail('네트워크 오류가 발생했어요.');
    }
  }
}
