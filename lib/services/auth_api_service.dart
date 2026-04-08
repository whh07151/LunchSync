import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: LunchSync 백엔드 인증 API 호출 서비스
//
// 담당 엔드포인트:
//   POST /api/auth/kakao — 카카오 토큰 → LunchSync JWT + isNewUser
//
// 왜 별도 파일로 분리하나?
//   HTTP 호출 코드가 UI나 Provider에 섞이면
//   서버 URL이 바뀌거나 인증 방식이 변경될 때 수정 범위가 넓어짐.
//   서비스 클래스로 분리하면 이 파일만 수정하면 됨.
//
// TODO: 추후 dio 패키지로 교체 시 이 파일만 수정하면 됨.
//       JWT 인터셉터, 에러 핸들링 등을 dio로 일괄 처리 가능.
// ══════════════════════════════════════════════════════════

// POST /auth/kakao 응답 데이터 모델
class AuthResponse {
  const AuthResponse({
    required this.accessToken,
    required this.isNewUser,
    required this.userId,
    required this.name,
    this.profileImage,
  });

  final String accessToken; // LunchSync 자체 JWT
  final bool isNewUser;     // true: 온보딩 필요, false: 홈으로 바로
  final String userId;      // Supabase users.id (UUID)
  final String name;        // 카카오 닉네임 (온보딩 전 임시)
  final String? profileImage;

  // JSON 파싱: POST /auth/kakao 응답의 data 필드에서 생성
  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return AuthResponse(
      accessToken: json['accessToken'] as String,
      isNewUser: json['isNewUser'] as bool,
      userId: user['id'] as String,
      name: user['name'] as String,
      profileImage: user['profileImage'] as String?,
    );
  }
}


class AuthApiService {
  const AuthApiService();

  // ── POST /api/auth/kakao ──────────────────────────────
  // 카카오 access token을 서버에 전달해서
  // LunchSync JWT + isNewUser + 유저 정보를 받아옴
  //
  // 반환: AuthResponse (성공) / null (실패)
  // TODO: 실패 시 상세 에러 메시지 분리가 필요하면 Exception을 throw하도록 변경
  Future<AuthResponse?> loginWithKakao(String kakaoAccessToken) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/auth/kakao'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'kakaoAccessToken': kakaoAccessToken}),
      );

      // ignore: avoid_print
      print('[AuthApiService] 상태코드: ${response.statusCode}');
      // ignore: avoid_print
      print('[AuthApiService] 응답: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        return AuthResponse.fromJson(data);
      }

      return null;
    } catch (e) {
      // 네트워크 오류, 파싱 오류 등
      // ignore: avoid_print
      print('[AuthApiService] 에러: $e');
      return null;
    }
  }
}
