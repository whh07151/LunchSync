// ══════════════════════════════════════════════════════════
// 파일 역할: NestJS HTTP API 호출용 공통 헤더 빌더
//
// 왜 분리했나:
//   * 9개 *_api_service.dart 가 동일한 `_headers()` private 메서드를
//     중복 정의하고 있어 헤더 정책이 분기될 위험이 컸음.
//   * Content-Type / Authorization 두 줄짜리 헬퍼지만, 만약 추후
//     `X-Request-ID`, `Accept-Language`, OIDC 갱신 토큰 등 공통 키가
//     추가될 때 9개 파일을 동시에 손대지 않아도 되도록 단일 진실
//     공급원(SSOT)으로 추출.
//
// 정책:
//   * `Content-Type: application/json` 고정 — NestJS 의 모든 API 가
//     JSON body 만 받음(파일 업로드 multipart 는 별도 헤더 직접 작성).
//   * Bearer 토큰 표준 — JWT 가 null 이거나 빈 문자열이면 Authorization
//     헤더 자체를 누락시켜 익명 호출이 가능하게 함(로그인 전 호출 보호).
//
// 사용 예:
//   import '../core/api/http_headers_helper.dart';
//   await http.get(uri, headers: apiHeaders(accessToken));
//
// 통합 제외(2026-05-30 시점):
//   * recommendations_api_service.dart / restaurants_api_service.dart
//     은 GET 만 사용해 Content-Type 을 의도적으로 생략 — 헤더 동작이
//     달라 통합 보류. 추후 헤더 정책 통일 시 함께 마이그레이션.
// ══════════════════════════════════════════════════════════

/// JSON API 호출용 공통 헤더 맵을 만든다.
///
/// [token] 이 null 또는 빈 문자열이면 Authorization 헤더를 포함하지
/// 않는다 — 로그인 전 공개 엔드포인트 호출 시에도 그대로 사용 가능.
///
/// 반환값은 매 호출마다 새 Map 이므로, 호출처에서 자유롭게 추가
/// 키를 mutate 해도 SSOT 가 오염되지 않는다.
Map<String, String> apiHeaders(String? token) {
  // 1) 공통 키: Content-Type 은 NestJS DTO 검증이 application/json 을
  //    전제로 동작하므로 항상 고정.
  final headers = <String, String>{
    'Content-Type': 'application/json',
  };

  // 2) Bearer 토큰: 빈 문자열도 무효로 간주(공백 토큰으로 401 유발 방지).
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }

  return headers;
}
