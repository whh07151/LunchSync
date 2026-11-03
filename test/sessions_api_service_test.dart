import 'package:capstone/services/sessions_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<T> _withMockClient<T>(
  Future<T> Function() body,
  Future<http.Response> Function(http.Request request) handler,
) {
  return http.runWithClient(body, () => MockClient(handler));
}

void main() {
  group('SessionsApiService.getTodaySessionsResult', () {
    test('정상 빈 목록을 성공 결과로 구분한다', () async {
      final result = await _withMockClient(
        () => const SessionsApiService().getTodaySessionsResult(
          accessToken: 'token',
        ),
        (_) async => http.Response('{"data":[]}', 200),
      );

      expect(result.isSuccess, isTrue);
      expect(result.sessions, isEmpty);
      expect(result.failureType, isNull);
    });

    test('401 응답은 인증 실패이며 빈 목록이 아니다', () async {
      final result = await _withMockClient(
        () => const SessionsApiService().getTodaySessionsResult(
          accessToken: 'expired-token',
        ),
        (_) async => http.Response('{"message":"Unauthorized"}', 401),
      );

      expect(result.isSuccess, isFalse);
      expect(result.sessions, isNull);
      expect(result.failureType, TodaySessionsFailureType.unauthorized);
      expect(result.statusCode, 401);
      expect(result.message, contains('로그인'));
    });

    test('그 밖의 비정상 HTTP 응답도 빈 목록이 아니다', () async {
      final result = await _withMockClient(
        () => const SessionsApiService().getTodaySessionsResult(
          accessToken: 'token',
        ),
        (_) async => http.Response('{"message":"Forbidden"}', 403),
      );

      expect(result.isSuccess, isFalse);
      expect(result.sessions, isNull);
      expect(result.failureType, TodaySessionsFailureType.http);
      expect(result.statusCode, 403);
    });

    test('JSON 파싱 실패도 빈 목록이 아니다', () async {
      final result = await _withMockClient(
        () => const SessionsApiService().getTodaySessionsResult(
          accessToken: 'token',
        ),
        (_) async => http.Response('not-json', 200),
      );

      expect(result.isSuccess, isFalse);
      expect(result.sessions, isNull);
      expect(result.failureType, TodaySessionsFailureType.invalidResponse);
      expect(result.message, contains('세션 정보'));
    });

    test('네트워크 실패도 빈 목록이 아니다', () async {
      final result = await _withMockClient(
        () => const SessionsApiService().getTodaySessionsResult(
          accessToken: 'token',
        ),
        (_) async => throw http.ClientException('offline'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.sessions, isNull);
      expect(result.failureType, TodaySessionsFailureType.network);
      expect(result.message, contains('인터넷 연결'));
    });

    test('기존 목록 API도 실패를 빈 목록으로 숨기지 않는다', () async {
      final future = _withMockClient(
        () => const SessionsApiService().getTodaySessions(accessToken: 'token'),
        (_) async => http.Response('{"message":"Bad request"}', 400),
      );

      await expectLater(future, throwsA(isA<TodaySessionsFetchException>()));
    });
  });
}
