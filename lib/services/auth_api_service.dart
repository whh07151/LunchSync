import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/api/error_message_extractor.dart';
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
  final bool isNewUser; // true: 신규 가입자

  /// 서버가 지정한 다음 화면.
  /// "PROFILE_SETUP"  → CU-03 기본 프로필 설정 (신규 손님)
  /// "CONDITION_SETUP" → CU-05 기본 조건 설정 (프로필 완료 후 재진입)
  /// "HOME"           → 손님 홈 대시보드
  /// "OWNER_PENDING"  → 사장 가입 후 운영자 승인 대기 안내
  /// "OWNER_HOME"     → 사장 홈 (승인 완료된 OWNER)
  final String nextStep;

  final String userId; // Supabase users.id (UUID)
  final String name; // 표시 이름
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
      nextStep:
          json['nextStep'] as String? ??
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
  const AuthApiService({http.Client? client}) : _client = client;

  final http.Client? _client;

  // ── POST /api/auth/kakao ──────────────────────────────
  // 카카오 access token을 서버에 전달해서 LunchSync JWT를 받아옴
  Future<AuthSignupResult> loginWithKakao(String kakaoAccessToken) async {
    try {
      final url = Uri.parse('${AppConfig.backendBaseUrl}/auth/kakao');
      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({'kakaoAccessToken': kakaoAccessToken});
      final request = _client == null
          ? http.post(url, headers: headers, body: body)
          : _client.post(url, headers: headers, body: body);
      final response = await request.timeout(AppConfig.apiTimeout);

      debugPrint('[AuthApiService] kakao 상태: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        return AuthSignupResult.success(AuthResponse.fromJson(data));
      }

      final message =
          extractApiErrorMessage(response.body) ??
          (response.statusCode >= 500
              ? '카카오 로그인 서버에 문제가 생겼어요. 잠시 후 다시 시도해주세요.'
              : '카카오 로그인에 실패했어요. 다시 시도해주세요.');
      return AuthSignupResult.failure(message);
    } on FormatException {
      debugPrint('[AuthApiService] KAKAO_LOGIN_INVALID_RESPONSE');
      return AuthSignupResult.failure(
        '카카오 로그인 응답을 읽지 못했어요. 앱과 서버 버전을 확인해 주세요.',
      );
    } on TypeError {
      debugPrint('[AuthApiService] KAKAO_LOGIN_INVALID_RESPONSE');
      return AuthSignupResult.failure(
        '카카오 로그인 응답을 읽지 못했어요. 앱과 서버 버전을 확인해 주세요.',
      );
    } catch (_) {
      debugPrint('[AuthApiService] KAKAO_LOGIN_FAILED');
      return AuthSignupResult.failure(
        '카카오 로그인 서버에 연결하지 못했어요. 네트워크를 확인하고 다시 시도해주세요.',
      );
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

      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/auth/signup/email'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(AppConfig.apiTimeout);

      debugPrint('[AuthApiService] signup 상태: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>;
        return AuthSignupResult.success(AuthResponse.fromJson(data));
      }

      // 에러 메시지 추출 (NestJS ValidationPipe / Exception 응답 구조)
      // 공용 헬퍼가 message 가 String / List<String> 양쪽을 모두 처리.
      final message = extractApiErrorMessage(response.body) ?? '회원가입에 실패했습니다.';

      return AuthSignupResult.failure(message);
    } catch (_) {
      return AuthSignupResult.failure('서버 연결에 실패했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  // ── POST /api/auth/verify-phone ────────────────────────
  // Firebase Phone Auth 로 받은 ID 토큰을 백엔드에 전달.
  // accessToken 이 있으면 인증된 "본인확인 모드", 없으면 공개 전화
  // 로그인/가입 모드다. 기존 사용자 ID는 서버로 보내지 않는다.
  Future<AuthSignupResult> verifyPhone({
    required String firebaseIdToken,
    String? accessToken,
  }) async {
    try {
      final body = <String, dynamic>{'idToken': firebaseIdToken};
      final isAttach = accessToken != null && accessToken.isNotEmpty;
      final path = isAttach ? 'verify-phone/attach' : 'verify-phone';

      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/auth/$path'),
            headers: {
              'Content-Type': 'application/json',
              if (isAttach) 'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          )
          .timeout(AppConfig.apiTimeout);

      debugPrint('[AuthApiService] verifyPhone 상태: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>;
        return AuthSignupResult.success(AuthResponse.fromJson(data));
      }

      // NestJS 에러 메시지 추출 (단일 String 또는 ValidationPipe 의 List<String>)
      final message = extractApiErrorMessage(response.body) ?? '휴대폰 인증에 실패했어요.';

      return AuthSignupResult.failure(message);
    } catch (_) {
      return AuthSignupResult.failure('서버 연결에 실패했어요. 잠시 후 다시 시도해주세요.');
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
      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/auth/login/email'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(AppConfig.apiTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>;
        return AuthSignupResult.success(AuthResponse.fromJson(data));
      }

      // NestJS 에러 메시지 추출 (단일 String 또는 ValidationPipe 의 List<String>)
      final message = extractApiErrorMessage(response.body) ?? '로그인에 실패했습니다.';
      String? errorCode;
      String? verificationToken;
      try {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
        errorCode = errorBody['code'] as String?;
        verificationToken = errorBody['verificationToken'] as String?;
      } catch (_) {
        // A non-JSON proxy error still follows the generic failure path.
      }

      return AuthSignupResult.failure(
        message,
        errorCode: errorCode,
        verificationToken: verificationToken,
      );
    } catch (_) {
      return AuthSignupResult.failure('서버 연결에 실패했어요. 잠시 후 다시 시도해주세요.');
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
    this.errorCode,
    this.verificationToken,
  });

  factory AuthSignupResult.success(AuthResponse response) =>
      AuthSignupResult._(isSuccess: true, response: response);

  factory AuthSignupResult.failure(
    String message, {
    String? errorCode,
    String? verificationToken,
  }) => AuthSignupResult._(
    isSuccess: false,
    errorMessage: message,
    errorCode: errorCode,
    verificationToken: verificationToken,
  );

  final bool isSuccess;
  final AuthResponse? response;
  final String? errorMessage;
  final String? errorCode;
  final String? verificationToken;

  bool get requiresEmailVerification =>
      errorCode == 'EMAIL_VERIFICATION_REQUIRED';
}

// ══════════════════════════════════════════════════════════
// 2026-05-31 시연 셋업: 폰 2대로 손님앱·사장앱 분리 시연용 시드 로그인.
// 백엔드 POST /api/dev/login-as-seed 호출 → 시드 사용자 JWT 발급.
// DEV_PROMOTE_ENABLED=true 환경에서만 200, 운영 환경에선 403.
// ══════════════════════════════════════════════════════════
class DevSeedLoginService {
  const DevSeedLoginService();

  Future<AuthSignupResult> loginAsSeed(String seedKey) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/dev/login-as-seed'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'seedKey': seedKey}),
          )
          .timeout(AppConfig.apiTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        // 시드 로그인은 nextStep 을 직접 안 주므로 role/status 로 추론
        final role = data['role'] as String? ?? 'CUSTOMER';
        final status = data['status'] as String? ?? 'APPROVED';
        final nextStep = role == 'OWNER'
            ? (status == 'APPROVED' ? 'OWNER_HOME' : 'OWNER_PENDING')
            : 'HOME';
        return AuthSignupResult.success(
          AuthResponse(
            accessToken: data['accessToken'] as String,
            isNewUser: false,
            nextStep: nextStep,
            userId: data['userId'] as String,
            name: data['name'] as String? ?? '시연 사용자',
            role: role,
            status: status,
          ),
        );
      }

      return AuthSignupResult.failure(
        extractApiErrorMessage(response.body) ??
            '시드 로그인 실패 (${response.statusCode})',
      );
    } catch (_) {
      debugPrint('[DevSeedLoginService] LOGIN_FAILED');
      return AuthSignupResult.failure('시드 로그인 중 오류가 발생했어요.');
    }
  }
}
