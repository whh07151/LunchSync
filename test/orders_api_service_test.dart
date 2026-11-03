import 'dart:convert';

import 'package:capstone/core/api/api_auth_hooks.dart';
import 'package:capstone/services/orders_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<T> _withMockClient<T>(
  Future<T> Function() body,
  Future<http.Response> Function(http.Request request) handler,
) {
  return http.runWithClient(body, () => MockClient(handler));
}

Future<CreateOrderResult?> _createOrder() {
  return const OrdersApiService().createOrder(
    accessToken: 'access-token',
    sessionId: 'session-id',
    items: const [CreateOrderItem(menuItemId: 'menu-id', quantity: 1)],
  );
}

void main() {
  group('OrdersApiService.createOrder', () {
    final controlledFailures = <CreateOrderFailureCode, String>{
      CreateOrderFailureCode.sessionNotFound: 'ORDER_SESSION_NOT_FOUND',
      CreateOrderFailureCode.sessionNotReady: 'ORDER_SESSION_NOT_READY',
      CreateOrderFailureCode.sessionRestaurantMismatch:
          'ORDER_SESSION_RESTAURANT_MISMATCH',
    };

    for (final failure in controlledFailures.entries) {
      test('${failure.value}만 통제된 예외로 전달한다', () async {
        final future = _withMockClient(
          _createOrder,
          (_) async => http.Response(
            jsonEncode({'code': failure.value, 'message': 'server message'}),
            failure.key == CreateOrderFailureCode.sessionNotFound ? 404 : 409,
          ),
        );

        await expectLater(
          future,
          throwsA(
            isA<CreateOrderException>().having(
              (error) => error.code,
              'code',
              failure.key,
            ),
          ),
        );
      });
    }

    test('알 수 없는 오류 코드는 기존처럼 null을 반환한다', () async {
      final result = await _withMockClient(
        _createOrder,
        (_) async => http.Response(
          jsonEncode({'code': 'ORDER_RESTAURANT_MISMATCH'}),
          409,
        ),
      );

      expect(result, isNull);
    });

    test('오류 코드가 없는 응답도 기존처럼 null을 반환한다', () async {
      final result = await _withMockClient(
        _createOrder,
        (_) async => http.Response(jsonEncode({'message': 'Bad request'}), 400),
      );

      expect(result, isNull);
    });

    test('오류 분류 전에 401 인증 훅을 실행한다', () async {
      final previousHook = ApiAuthHooks.onUnauthorized;
      addTearDown(() => ApiAuthHooks.onUnauthorized = previousHook);
      var unauthorizedNotified = false;
      ApiAuthHooks.onUnauthorized = () => unauthorizedNotified = true;

      final result = await _withMockClient(
        _createOrder,
        (_) async =>
            http.Response(jsonEncode({'message': 'Unauthorized'}), 401),
      );

      expect(unauthorizedNotified, isTrue);
      expect(result, isNull);
    });
  });
}
