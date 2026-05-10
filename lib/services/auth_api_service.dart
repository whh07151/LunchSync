import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: LunchSync 백엔드 인증 API 호출 서비스
//
// 담당 엔드포인트:
//   POST /api/auth/kakao         — 카카오 토큰 → JWT
//   POST /api/auth/signup/email  — 이메일+비번 회원가입 (역할 선택 포함)
//   POST /api/auth/login/email   — 이메일+비번 로그인
//
// 왜 별도 파일로 분리하나?
//   HTTP 호출 코드가 UI나 Provider에 섞이면
//   서버 URL이 바뀌거나 인증 방식이 변경될 때 수정 범위가 넓어짐.
//
// 회원가입/인증 결정(2026-05-07) 반영:
//   - AuthResponse에 role / status 필드 추가
//   - nextStep에 OWNER_PENDING / OWNER_HOME 케이스 추가
// ══════════════════════════════════════════════════════════

// 인증 응답 데이터 모델 (카카오·이메일·휴대폰 공통 응답 형태)
class AuthResponse {
  const AuthResponse({
    required this.accessToken,
    required this.isNewUser,
    required this.nextStep,
    required this.userId,
    required this.name,
    required this.role,
    required this.status,
    this.profileImage,
  });

  final String accessToken; // LunchSync 자체 JWT
  final bool isNewUser;     // true: 신규 가입자

  /// 서버가 지정한 다음 화면.
  /// "PROFILE_SETUP"  → CU-03 기본 프로필 설정 (신규 손님)
  /// "CONDITION_SETUP" → CU-05 기본 조건 설정 (프로필 완료 후 재진입)
  /// "HOME"           → 손님 홈 대시보드
  /// "OWNER_PENDING"  → 사장 가입 후 운영자 승인 대기 안내
  /// "OWNER_HOME"     → 사장 홈 (승인 완료된 OWNER)
  final String nextStep;

  final String userId;       // Supabase users.id (UUID)
  final String name;         // 표시 이름
  final String? profileImage;

  /// 유저 역할: CUSTOMER | OWNER
  final String role;

  /// 가입 승인 상태: PENDING | APPROVED | REJECTED
  /// (CUSTOMER는 항상 APPROVED, OWNER는 승인 대기 흐름 있음)
  final String status;

  // JSON 파싱: 백엔드 응답의 data 필드에서 생성
  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return AuthResponse(
      accessToken: json['accessToken'] as String,
      isNewUser: json['isNewUser'] as bool,
      nextStep: json['nextStep'] as String? ??
          (json['isNewUser'] as bool ? 'PROFILE_SETUP' : 'HOME'),
      userId: user['id'] as String,
      name: user['name'] as String,
      profileImage: user['profileImage'] as String?,
      role: (user['role'] as String?) ?? 'CUSTOMER',
      status: (user['status'] as String?) ?? 'APPROVED',
    );
  }
}


class AuthApiService {
  const AuthApiService();

  // ── POST /api/auth/kakao ──────────────────────────────
  // 카카오 access token을 서버에 전달해서 LunchSync JWT를 받아옴
  Future<AuthResponse?> loginWithKakao(String kakaoAccessToken) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/auth/kakao'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'kakaoAccessToken': kakaoAccessToken}),
      );

      // ignore: avoid_print
      print('[AuthApiService] kakao 상태: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        return AuthResponse.fromJson(data);
      }

      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[AuthApiService] kakao 에러: $e');
      return null;
    }
  }

  // ── POST /api/auth/signup/email ────────────────────────
  // 이메일+비밀번호 회원가입. role/businessName/businessNumber 선택적 전달.
  //
  // 반환:
  //   AuthSignupResult.success(response) — 가입 성공
  //   AuthSignupResult.failure(message)  — 실패 (중복 이메일·검증 오류 등)
  Future<AuthSignupResult> signupEmail({
    required String email,
    required String password,
    required String name,
    required String role, // 'CUSTOMER' | 'OWNER'
    String? businessName,
    String? businessNumber,
  }) async {
    try {
      final body = <String, dynamic>{
        'email': email,
        'password': password,
        'name': name,
        'role': role,
      };
      if (businessName != null) body['businessName'] = businessName;
      if (businessNumber != null) body['businessNumber'] = businessNumber;

      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/auth/signup/email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      // ignore: avoid_print
      print('[AuthApiService] signup 상태: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>;
        return AuthSignupResult.success(AuthResponse.fromJson(data));
      }

      // 에러 메시지 추출 (NestJS ValidationPipe / Exception 응답 구조)
      String message = '회원가입에 실패했습니다.';
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final raw = json['message'];
        if (raw is String) {
          message = raw;
        } else if (raw is List && raw.isNotEmpty) {
          message = raw.first.toString();
        }
      } catch (_) {}

      return AuthSignupResult.failure(message);
    } catch (e) {
      return AuthSignupResult.failure('서버 연결에 실패했어요. ($e)');
    }
  }

  // ── POST /api/auth/login/email ─────────────────────────
  // 이메일+비밀번호 로그인.
  //
  // 반환:
  //   AuthSignupResult.success(response) — 로그인 성공
  //   AuthSignupResult.failure(message)  — 실패 (계정 없음·비번 불일치 등)
  Future<AuthSignupResult> loginEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/auth/login/email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>;
        return AuthSignupResult.success(AuthResponse.fromJson(data));
      }

      String message = '로그인에 실패했습니다.';
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final raw = json['message'];
        if (raw is String) {
          message = raw;
        } else if (raw is List && raw.isNotEmpty) {
          message = raw.first.toString();
        }
      } catch (_) {}

      return AuthSignupResult.failure(message);
    } catch (e) {
      return AuthSignupResult.failure('서버 연결에 실패했어요. ($e)');
    }
  }
}


// ══════════════════════════════════════════════════════════
// AuthSignupResult: 회원가입/이메일 로그인 응답 래퍼
//
// success/failure를 명확히 구분해서, UI에서 에러 메시지를
// 그대로 스낵바에 표시할 수 있도록 분리.
// ══════════════════════════════════════════════════════════
class AuthSignupResult {
  const AuthSignupResult._({
    required this.isSuccess,
    this.response,
    this.errorMessage,
  });

  factory AuthSignupResult.success(AuthResponse response) =>
      AuthSignupResult._(isSuccess: true, response: response);

  factory AuthSignupResult.failure(String message) =>
      AuthSignupResult._(isSuccess: false, errorMessage: message);

  final bool isSuccess;
  final AuthResponse? response;
  final String? errorMessage;
}
