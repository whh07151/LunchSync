import 'dart:async';

import 'package:capstone/features/payment/order_review_screen.dart';
import 'package:capstone/models/menu_item.dart';
import 'package:capstone/providers/cart_provider.dart';
import 'package:capstone/providers/user_provider.dart';
import 'package:capstone/services/orders_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _menuItem = MenuItem(
  id: 'menu-id',
  restaurantId: 'restaurant-id',
  name: '테스트 메뉴',
  description: '테스트 설명',
  price: 1000,
  category: MenuCategory.rice,
);

class _TestUserNotifier extends UserNotifier {
  @override
  UserState build() => const UserState(
    accessToken: 'access-token',
    userId: 'user-id',
    name: '테스터',
  );
}

class _TestCartNotifier extends CartNotifier {
  @override
  List<CartItem> build() => const [CartItem(item: _menuItem, quantity: 1)];
}

class _FakeOrdersApiService extends OrdersApiService {
  _FakeOrdersApiService(this._createOrder);

  final Future<CreateOrderResult?> Function() _createOrder;

  @override
  Future<CreateOrderResult?> createOrder({
    required String accessToken,
    required String sessionId,
    required List<CreateOrderItem> items,
    String paymentMethod = 'TOSS',
  }) {
    return _createOrder();
  }
}

Widget _testApp(OrdersApiService ordersApi) {
  return ProviderScope(
    overrides: [
      userProvider.overrideWith(_TestUserNotifier.new),
      cartProvider.overrideWith(_TestCartNotifier.new),
    ],
    child: MaterialApp(
      home: OrderReviewScreen(
        sessionId: 'session-id',
        restaurantName: '테스트 식당',
        ordersApi: ordersApi,
      ),
    ),
  );
}

Future<void> _startPayment(
  WidgetTester tester,
  OrdersApiService ordersApi,
) async {
  await tester.pumpWidget(_testApp(ordersApi));
  await tester.tap(find.text('1,000원 결제하기'));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('OrderReviewScreen 주문 생성 오류', () {
    final controlledMessages = <CreateOrderFailureCode, String>{
      CreateOrderFailureCode.sessionNotFound:
          '주문 세션을 찾을 수 없습니다. 세션을 다시 확인해주세요.',
      CreateOrderFailureCode.sessionNotReady: '식당 선택이 완료된 세션에서만 주문할 수 있어요.',
      CreateOrderFailureCode.sessionRestaurantMismatch:
          '세션에서 선택한 식당의 메뉴만 주문할 수 있어요.',
    };

    for (final failure in controlledMessages.entries) {
      testWidgets('${failure.key.backendCode}를 명확한 안내로 표시한다', (tester) async {
        await _startPayment(
          tester,
          _FakeOrdersApiService(
            () async => throw CreateOrderException(failure.key),
          ),
        );

        expect(find.text(failure.value), findsOneWidget);
      });
    }

    testWidgets('null 응답은 기존 주문 생성 실패 안내를 유지한다', (tester) async {
      await _startPayment(tester, _FakeOrdersApiService(() async => null));

      expect(
        find.text('주문 생성에 실패했습니다.\n메뉴가 DB 에 등록되어 있는지 확인해주세요.'),
        findsOneWidget,
      );
    });

    testWidgets('알 수 없는 예외는 서버 내용을 노출하지 않는 일반 안내를 표시한다', (tester) async {
      await _startPayment(
        tester,
        _FakeOrdersApiService(() async => throw StateError('sensitive detail')),
      );

      expect(find.text('결제 시작 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.'), findsOneWidget);
      expect(find.textContaining('sensitive detail'), findsNothing);
    });

    testWidgets('응답 대기 중 화면이 dispose 되어도 setState 예외가 없다', (tester) async {
      final response = Completer<CreateOrderResult?>();
      await tester.pumpWidget(
        _testApp(_FakeOrdersApiService(() => response.future)),
      );
      await tester.tap(find.text('1,000원 결제하기'));
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      response.complete(null);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
