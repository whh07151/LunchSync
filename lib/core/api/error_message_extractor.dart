import 'dart:convert';

// ══════════════════════════════════════════════════════════
// 파일 역할: NestJS 에러 응답 body 에서 한국어 메시지를 추출하는 공용 헬퍼
//
// 배경:
//   NestJS 백엔드는 4xx/5xx 응답 body 에 다음 두 가지 형태로
//   한국어 안내 메시지를 내려줍니다.
//     1) { "message": "이메일이 이미 존재합니다.", ... }            ← 단일 문자열
//     2) { "message": ["email 은 필수 항목입니다.", ...], ... }    ← class-validator 배열
//
//   각 *_api_service.dart 마다 동일한 try / jsonDecode / message 분기
//   try-catch 가 5곳 이상 반복되고 있어서 한 곳으로 모았습니다.
//   (auth_api_service signup/verifyPhone/loginEmail, votes_api_service castVote,
//    sessions_api_service updateSessionStatus/deleteSession,
//    friends_api_service _extractMessage)
//
// 호출 규약:
//   - body 만 받고 statusCode 별 분기는 호출처(서비스) 책임
//   - jsonDecode 실패·Map 아님·message 필드 없음·빈 문자열 → 모두 null 반환
//   - 호출처는 `extractApiErrorMessage(body) ?? '기본 안내 문구'` 형태로
//     기본 메시지와 결합해 사용
//
// 빈 문자열을 null 로 처리하는 이유:
//   백엔드가 실수로 `message: ""` 를 내려줘도 사용자에게 빈 토스트가
//   뜨지 않도록 호출처의 한국어 기본 안내가 살아남게 합니다.
//   (votes / sessions 의 기존 `raw.isNotEmpty` 분기와 동일한 동작)
// ══════════════════════════════════════════════════════════

/// NestJS 응답 body 문자열에서 `message` 필드의 값을 한국어 한 줄로 추출합니다.
///
/// 반환:
///   - 단일 문자열 message → 그 값 그대로
///   - 문자열 배열 message → 첫 번째 원소를 toString() 으로 변환
///   - 그 외(파싱 실패, Map 아님, message 없음, 빈 문자열) → null
String? extractApiErrorMessage(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      final raw = decoded['message'];
      // 1) message 가 단일 문자열인 일반적인 NestJS HttpException 케이스
      if (raw is String) {
        return raw.isEmpty ? null : raw;
      }
      // 2) class-validator ValidationPipe 가 내려주는 문자열 배열 케이스
      if (raw is List && raw.isNotEmpty) {
        final first = raw.first.toString();
        return first.isEmpty ? null : first;
      }
    }
  } catch (_) {
    // jsonDecode 실패·타입 캐스팅 실패는 모두 무시하고 null 반환
    // (호출처에서 기본 안내 문구로 fallback 됨)
  }
  return null;
}
