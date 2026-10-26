import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

// ══════════════════════════════════════════════════════════
// 파일 역할: HTTP GET 자동 재시도 + 네트워크 오류 분류 헬퍼
//
// 배경 (2026-05-31 한성대 시연 대비):
//   공용 와이파이(스타벅스/학교 캡티브 포털)는 간헐적으로 연결이 끊긴다.
//   끊긴 순간 http.get 이 SocketException / "Connection reset by peer"
//   / TimeoutException 으로 실패하는데, 기존 *_api_service.dart 는 이걸
//   catch 해서 빈 배열([])로 돌려준다. 그러면 화면은 "통신 실패"인지
//   "진짜 후보 0개"인지 구분하지 못하고 "이 동네는 후보가 부족해요"
//   같은 오해를 주는 메시지를 띄운다. (토너먼트 후보 0개 오표시 사고)
//
// 이 헬퍼가 해결하는 것:
//   1) 자동 재시도 — 일시적 네트워크 오류/5xx 는 짧은 백오프로 N회 재시도.
//      와이파이가 한두 번 깜빡여도 사용자가 모르게 복구된다.
//   2) 오류 분류 — 재시도까지 다 실패하면 ApiNetworkException 을 throw 해서
//      호출 측이 "네트워크 문제"와 "정상 응답(빈 결과)"를 구분할 수 있게 한다.
//
// 사용 패턴:
//   final res = await ApiRetry.get(uri, headers: h, timeout: t);
//   // 성공 응답(2xx~4xx)은 그대로 반환. 재시도 소진 시 ApiNetworkException.
//
// 재시도 대상(일시적이라 다시 시도할 가치가 있는 것):
//   - SocketException            : 연결 끊김/도달 불가 (와이파이 깜빡임)
//   - http.ClientException       : "Connection reset by peer" / "Connection closed"
//   - TimeoutException           : 응답 지연
//   - HTTP 5xx (502/503/504 등)  : 서버 일시 과부하/재배포 순간
//
// 재시도 안 하는 것(다시 시도해도 같은 결과):
//   - 2xx / 3xx / 4xx(401/404 등) : 정상 응답이므로 그대로 반환.
// ══════════════════════════════════════════════════════════

/// 재시도까지 모두 실패했을 때 던지는 네트워크 오류.
///
/// 호출 측은 이 예외를 catch 해서 "후보 0개"가 아니라
/// "연결이 불안정해요 — 다시 시도" 같은 메시지를 구분 표시할 수 있다.
class ApiNetworkException implements Exception {
  ApiNetworkException(this.message, {this.lastError});

  /// 사람이 읽는 요약 메시지.
  final String message;

  /// 마지막으로 발생한 원본 예외(디버깅용).
  final Object? lastError;

  @override
  String toString() => 'ApiNetworkException: $message';
}

class ApiRetry {
  ApiRetry._();

  /// 재시도 간 백오프(점증). attempts=3 이면 [실패→300ms→실패→600ms→실패→throw].
  static const List<Duration> _backoff = <Duration>[
    Duration(milliseconds: 300),
    Duration(milliseconds: 600),
    Duration(milliseconds: 1000),
  ];

  /// HTTP GET 을 자동 재시도와 함께 수행한다.
  ///
  /// [maxAttempts] : 총 시도 횟수(최초 1회 + 재시도). 기본 3.
  /// [timeout]     : 매 시도별 타임아웃.
  ///
  /// 반환: 성공/정상 실패(4xx 포함) 응답.
  /// throw: 모든 시도가 일시적 오류로 실패하면 [ApiNetworkException].
  static Future<http.Response> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    int maxAttempts = 3,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await http.get(uri, headers: headers).timeout(timeout);

        // 5xx 는 일시적 서버 오류로 보고 재시도(마지막 시도면 그대로 반환).
        if (response.statusCode >= 500 && attempt < maxAttempts) {
          lastError = 'HTTP ${response.statusCode}';
          debugPrint(
            '[ApiRetry] HTTP_RETRY_${response.statusCode}_$attempt',
          );
          await _wait(attempt);
          continue;
        }

        // 2xx~4xx 는 정상 흐름이므로 그대로 반환(호출 측이 statusCode 로 분기).
        return response;
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      } on HttpException catch (e) {
        lastError = e;
      }

      // 여기 도달 = 일시적 오류 발생. 마지막 시도가 아니면 백오프 후 재시도.
      if (attempt < maxAttempts) {
        debugPrint(
          '[ApiRetry] NETWORK_RETRY_$attempt',
        );
        await _wait(attempt);
      }
    }

    // 모든 시도 소진 — 네트워크 오류로 분류해 throw.
    throw ApiNetworkException(
      '네트워크 연결이 불안정해요',
      lastError: lastError,
    );
  }

  /// attempt(1-based)에 해당하는 백오프만큼 대기.
  static Future<void> _wait(int attempt) {
    final idx = (attempt - 1).clamp(0, _backoff.length - 1);
    return Future<void>.delayed(_backoff[idx]);
  }
}
