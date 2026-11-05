import 'package:capstone/features/payment/payment_success_screen.dart';
import 'package:capstone/features/payment/order_cart_snapshot.dart';
import 'package:capstone/models/menu_item.dart';
import 'package:capstone/providers/cart_provider.dart';
import 'package:capstone/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const item = MenuItem(
  id: 'menu',
  restaurantId: 'restaurant',
  name: '메뉴',
  description: '',
  price: 1000,
  category: MenuCategory.rice,
);

class TestUser extends UserNotifier {
  @override
  UserState build() => const UserState(accessToken: 'token', userId: 'user');
}

void main() {
  test(
    'stored snapshots require the matching order and valid whole quantities',
    () {
      const snapshot = OrderCartSnapshot(
        orderId: 'a',
        items: [(menuItemId: 'menu', quantity: 2)],
      );
      expect(
        OrderCartSnapshot.decode(snapshot.encode(), 'a')?.items.single.quantity,
        2,
      );
      expect(OrderCartSnapshot.decode(snapshot.encode(), 'b'), isNull);
      expect(
        OrderCartSnapshot.decode(
          '{"orderId":"a","items":[{"menuItemId":"menu","quantity":1.5}]}',
          'a',
        ),
        isNull,
      );
      expect(
        OrderCartSnapshot.decode('[{"menuItemId":"menu","quantity":2}]', 'a'),
        isNull,
      );
      expect(OrderCartSnapshot.decode('invalid', 'a'), isNull);
      expect(
        OrderCartSnapshot.storageKey('a'),
        isNot(OrderCartSnapshot.storageKey('b')),
      );
    },
  );

  test('consuming a confirmed order once preserves later cart additions', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final cart = container.read(cartProvider.notifier);
    cart.addItem(item);
    cart.addItem(item);
    cart.consumeOrderSnapshot('order', [(menuItemId: 'menu', quantity: 1)]);
    expect(cart.quantityOf('menu'), 1);
    cart.addItem(item);
    cart.consumeOrderSnapshot('order', [(menuItemId: 'menu', quantity: 1)]);
    expect(cart.quantityOf('menu'), 2);
    cart.consumeOrderSnapshot('next-order', [
      (menuItemId: 'menu', quantity: 1),
    ]);
    expect(cart.quantityOf('menu'), 1);
  });

  testWidgets('success without an order snapshot preserves the current cart', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [userProvider.overrideWith(TestUser.new)],
    );
    addTearDown(container.dispose);
    container.read(cartProvider.notifier).addItem(item);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PaymentSuccessScreen(
            paymentKey: 'sim_order',
            orderId: 'order',
            amount: 1000,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(container.read(cartProvider.notifier).quantityOf('menu'), 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'mobile success consumes exactly its snapshot once across remounts',
    (tester) async {
      final container = ProviderContainer(
        overrides: [userProvider.overrideWith(TestUser.new)],
      );
      addTearDown(container.dispose);
      final cart = container.read(cartProvider.notifier);
      cart.addItem(item);
      cart.addItem(item);
      const screen = PaymentSuccessScreen(
        paymentKey: 'sim_order',
        orderId: 'order',
        amount: 1000,
        cartSnapshot: OrderCartSnapshot(
          orderId: 'order',
          items: [(menuItemId: 'menu', quantity: 1)],
        ),
      );
      Future<void> mount() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: screen),
          ),
        );
        await tester.pump();
      }

      await mount();
      expect(cart.quantityOf('menu'), 1);
      await tester.pumpWidget(const SizedBox());
      cart.addItem(item);
      await mount();
      expect(cart.quantityOf('menu'), 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a snapshot for another order leaves the cart untouched', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [userProvider.overrideWith(TestUser.new)],
    );
    addTearDown(container.dispose);
    final cart = container.read(cartProvider.notifier)..addItem(item);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PaymentSuccessScreen(
            paymentKey: 'sim_order',
            orderId: 'order',
            amount: 1000,
            cartSnapshot: OrderCartSnapshot(
              orderId: 'other',
              items: [(menuItemId: 'menu', quantity: 1)],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(cart.quantityOf('menu'), 1);
    await tester.pumpWidget(const SizedBox());
  });
}
