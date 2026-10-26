import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 공통 HTTP 클라이언트 (timeout + 401 인터셉터 + 에러 분류)
//
// 프론트 에이전트 Critical 권장 통합:
//   1. 모든 호출에 apiTimeout(10s) 일괄 적용 — 무한 로딩 방지
//   2. 401 응답 시 onUnauthorized 콜백 (자동 로그아웃 흐름 트리거)
//   3. ApiResult<T> 패턴 — 성공/에러 타입을 명확히 분기
//
// 사용 패턴:
//   final api = ApiClient(onUnauthorized: () => ref.read(userProvider.notifier).clear());
//   final result = await api.get('/users/me', token: jwt);
//   result.when(
//     success: (data) => ...,
//     error: (err) => switch (err.type) {
//       ApiErrorType.timeout => '네트워크가 느려요. 다시 시도해주세요.',
//       ApiErrorType.unauthorized => '로그인이 만료됐어요.',
//       ApiErrorType.serverError => '서버에 문제가 있어요.',
//       _ => '요청을 처리하지 못했어요.',
//     },
//   );
//
// 점진 마이그레이션:
//   기존 14개 lib/services/*_api_service.dart 가 직접 http.* 를 호출함.
//   이 클라이언트는 신규 코드부터 사용하고, 기존 서비스는 점진 마이그레이션.
//
// 단일 책임:
//   응답 파싱 / camelCase 변환 / DTO 매핑은 각 서비스가 담당.
//   이 클라이언트는 네트워크 레이어(상태 코드, timeout, 401)만 담당.
// ══════════════════════════════════════════════════════════

/// API 에러 타입 분류 — UI 에서 친근체 메시지로 매핑
enum ApiErrorType {
  /// 응답이 [AppConfig.apiTimeout] 안에 도착하지 않음
  timeout,

  /// HTTP 401 — JWT 만료 또는 미인증
  unauthorized,

  /// HTTP 403 — 권한 부족 (예: 호스트만 가능한 작업)
  forbidden,

  /// HTTP 404 — 리소스 없음
  notFound,

  /// HTTP 4xx (위 3종 제외) — 클라이언트 입력 오류
  badRequest,

  /// HTTP 5xx — 서버 오류
  serverError,

  /// 네트워크 끊김 / DNS / TLS 오류
  network,

  /// 응답 JSON 파싱 실패
  parse,

  /// 그 외
  unknown,
}

/// API 에러 (예외 대신 값으로 반환)
class ApiError {
  const ApiError({
    required this.type,
    required this.message,
    this.statusCode,
  });

  final ApiErrorType type;
  final String message;
  final int? statusCode;

  /// UI 표시용 친근체 한글 메시지
  String get userMessage {
    switch (type) {
      case ApiErrorType.timeout:
        return '네트워크가 느려요. 다시 시도해주세요.';
      case ApiErrorType.unauthorized:
        return '로그인이 만료됐어요. 다시 로그인해주세요.';
      case ApiErrorType.forbidden:
        return '권한이 없어요.';
      case ApiErrorType.notFound:
        return '요청한 정보를 찾을 수 없어요.';
      case ApiErrorType.badRequest:
        return message.isNotEmpty ? message : '요청을 처리하지 못했어요.';
      case ApiErrorType.serverError:
        return '서버에 문제가 있어요. 잠시 후 다시 시도해주세요.';
      case ApiErrorType.network:
        return '인터넷 연결을 확인해주세요.';
      case ApiErrorType.parse:
        return '응답을 처리하지 못했어요.';
      case ApiErrorType.unknown:
        return '알 수 없는 오류가 발생했어요.';
    }
  }
}

/// API 결과 — 성공이면 [data], 실패면 [error] 가 채워짐 (둘 중 하나만)
class ApiResult<T> {
  const ApiResult._({this.data, this.error}) : assert(data != null || error != null);

  factory ApiResult.success(T data) => ApiResult._(data: data);
  factory ApiResult.failure(ApiError error) => ApiResult._(error: error);

  final T? data;
  final ApiError? error;

  bool get isSuccess => error == null;
  bool get isFailure => error != null;

  /// 성공이면 [onSuccess], 실패면 [onError] 호출 후 값 반환
  R when<R>({
    required R Function(T data) success,
    required R Function(ApiError error) error,
  }) {
    if (isSuccess) return success(data as T);
    return error(this.error!);
  }
}

/// 공통 HTTP 클라이언트
class ApiClient {
  ApiClient({this.onUnauthorized});

  /// 401 응답 수신 시 호출 — 보통 userProvider.clear() + 로그인 화면 이동
  final void Function()? onUnauthorized;

  Future<ApiResult<Map<String, dynamic>>> get(
    String path, {
    String? token,
    Map<String, String>? query,
  }) =>
      _request('GET', path, token: token, query: query);

  Future<ApiResult<Map<String, dynamic>>> post(
    String path, {
    String? token,
    Object? body,
  }) =>
      _request('POST', path, token: token, body: body);

  Future<ApiResult<Map<String, dynamic>>> patch(
    String path, {
    String? token,
    Object? body,
  }) =>
      _request('PATCH', path, token: token, body: body);

  Future<ApiResult<Map<String, dynamic>>> delete(
    String path, {
    String? token,
  }) =>
      _request('DELETE', path, token: token);

  // ── 내부: 모든 HTTP 메서드 공통 로직 ───────────────────
  Future<ApiResult<Map<String, dynamic>>> _request(
    String method,
    String path, {
    String? token,
    Map<String, String>? query,
    Object? body,
  }) async {
    final url = _buildUrl(path, query);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    http.Response response;
    try {
      final future = switch (method) {
        'GET' => http.get(url, headers: headers),
        'POST' => http.post(url, headers: headers, body: jsonEncode(body)),
        'PATCH' => http.patch(url, headers: headers, body: jsonEncode(body)),
        'DELETE' => http.delete(url, headers: headers),
        _ => throw ArgumentError('Unsupported method $method'),
      };
      response = await future.timeout(AppConfig.apiTimeout);
    } on TimeoutException {
      debugPrint('[ApiClient] HTTP_TIMEOUT');
      return ApiResult.failure(const ApiError(
        type: ApiErrorType.timeout,
        message: 'timeout',
      ));
    } catch (_) {
      debugPrint('[ApiClient] HTTP_NETWORK_FAILED');
      return ApiResult.failure(const ApiError(
        type: ApiErrorType.network,
        message: 'network failed',
      ));
    }

    // 401 — 자동 로그아웃 콜백 트리거
    if (response.statusCode == 401) {
      if (AppConfig.autoLogoutOn401 && onUnauthorized != null) {
        try {
          onUnauthorized!();
        } catch (_) {
          debugPrint('[ApiClient] UNAUTHORIZED_CALLBACK_FAILED');
        }
      }
      return ApiResult.failure(const ApiError(
        type: ApiErrorType.unauthorized,
        message: 'unauthorized',
        statusCode: 401,
      ));
    }

    // 응답 본문 파싱
    Map<String, dynamic>? parsed;
    try {
      if (response.body.isNotEmpty) {
        parsed = jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {
      debugPrint('[ApiClient] HTTP_RESPONSE_PARSE_FAILED');
      return ApiResult.failure(ApiError(
        type: ApiErrorType.parse,
        message: 'parse failed',
        statusCode: response.statusCode,
      ));
    }

    // 상태 코드별 분기
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return ApiResult.success(parsed ?? <String, dynamic>{});
    }
    if (response.statusCode == 403) {
      return ApiResult.failure(ApiError(
        type: ApiErrorType.forbidden,
        message: _extractMessage(parsed) ?? 'forbidden',
        statusCode: 403,
      ));
    }
    if (response.statusCode == 404) {
      return ApiResult.failure(ApiError(
        type: ApiErrorType.notFound,
        message: _extractMessage(parsed) ?? 'not found',
        statusCode: 404,
      ));
    }
    if (response.statusCode >= 400 && response.statusCode < 500) {
      return ApiResult.failure(ApiError(
        type: ApiErrorType.badRequest,
        message: _extractMessage(parsed) ?? 'bad request',
        statusCode: response.statusCode,
      ));
    }
    if (response.statusCode >= 500) {
      return ApiResult.failure(ApiError(
        type: ApiErrorType.serverError,
        message: _extractMessage(parsed) ?? 'server error',
        statusCode: response.statusCode,
      ));
    }

    return ApiResult.failure(ApiError(
      type: ApiErrorType.unknown,
      message: 'http ${response.statusCode}',
      statusCode: response.statusCode,
    ));
  }

  // ── 내부 헬퍼들 ───────────────────────────────────────
  Uri _buildUrl(String path, Map<String, String>? query) {
    final base = AppConfig.backendBaseUrl;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final url = Uri.parse('$base$cleanPath');
    if (query == null || query.isEmpty) return url;
    return url.replace(queryParameters: query);
  }

  /// NestJS 표준 에러 응답에서 사용자 메시지 추출
  /// 예: { "success": false, "message": "...", "error": {...} }
  String? _extractMessage(Map<String, dynamic>? body) {
    if (body == null) return null;
    final msg = body['message'];
    if (msg is String) return msg;
    if (msg is List && msg.isNotEmpty) return msg.first.toString();
    final error = body['error'];
    if (error is Map && error['message'] is String) {
      return error['message'] as String;
    }
    return null;
  }
}
