import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:capstone/features/owner/inventory_management_screen.dart';
import 'package:capstone/services/owner_inventory_service.dart';
import 'package:capstone/services/pos_menus_api_service.dart';
import 'package:capstone/services/pos_operations_api_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('OwnerInventoryService & InventoryItem', () {
    test('detects sufficient, lowStock, and outOfStock statuses', () {
      const itemSufficient = InventoryItem(
        id: '1',
        name: '한돈 앞다리살',
        category: '육류/해산물',
        currentQty: 15,
        minThreshold: 5,
        unit: '인분',
      );
      const itemLow = InventoryItem(
        id: '2',
        name: '국산 손두부',
        category: '채소/농산물',
        currentQty: 4,
        minThreshold: 6,
        unit: '모',
      );
      const itemOut = InventoryItem(
        id: '3',
        name: '특란(계란)',
        category: '밥/면/기타',
        currentQty: 0,
        minThreshold: 10,
        unit: '개',
      );

      expect(itemSufficient.status, InventoryStockStatus.sufficient);
      expect(itemSufficient.needsAttention, isFalse);
      expect(itemLow.status, InventoryStockStatus.lowStock);
      expect(itemLow.needsAttention, isTrue);
      expect(itemOut.status, InventoryStockStatus.outOfStock);
      expect(itemOut.needsAttention, isTrue);

      final summary = InventorySummary.fromItems([
        itemSufficient,
        itemLow,
        itemOut,
      ]);
      expect(summary.totalCount, 3);
      expect(summary.sufficientCount, 1);
      expect(summary.lowStockCount, 1);
      expect(summary.outOfStockCount, 1);
      expect(summary.alertCount, 2);
    });

    test('matches linked menus by ingredients and linkedMenuNames', () {
      const item = InventoryItem(
        id: 'inv_tofu',
        name: '두부',
        category: '채소/농산물',
        currentQty: 2,
        minThreshold: 5,
        unit: '모',
        linkedMenuNames: ['된장찌개'],
      );

      const menus = [
        PosMenuItem(
          id: 'm1',
          restaurantId: 'r1',
          name: '한돈 김치찌개',
          price: 9000,
          isAvailable: true,
          ingredients: ['돼지고기', '김치', '국산 손두부'],
        ),
        PosMenuItem(
          id: 'm2',
          restaurantId: 'r1',
          name: '된장찌개',
          price: 8500,
          isAvailable: true,
          ingredients: ['된장', '애호박'],
        ),
        PosMenuItem(
          id: 'm3',
          restaurantId: 'r1',
          name: '돈까스',
          price: 10000,
          isAvailable: true,
          ingredients: ['등심', '빵가루'],
        ),
      ];

      final matched = item.matchMenus(menus);
      expect(matched.map((m) => m.id).toList(), ['m1', 'm2']);
    });

    test('merges newly registered menu ingredients into inventory', () {
      const service = OwnerInventoryService();
      final initial = OwnerInventoryService.buildInitialSeed();
      const menus = [
        PosMenuItem(
          id: 'm_new',
          restaurantId: 'r1',
          name: '차돌짬뽕순두부',
          price: 11000,
          isAvailable: true,
          ingredients: ['우삼겹차돌', '국산 손두부'],
        ),
      ];

      final merged = service.mergeIngredientsFromMenus(initial, menus);
      final added = merged.firstWhere((e) => e.name == '우삼겹차돌');
      expect(added.category, '육류/해산물');
      expect(added.linkedMenuNames, contains('차돌짬뽕순두부'));
      expect(added.currentQty, 0);
      expect(added.expiryDate, isNull);
    });

    test(
      'calculates expiry status, recipe capacity, and replenishes shortages',
      () {
        const service = OwnerInventoryService();
        final now = DateTime(2026, 11, 2);
        const items = [
          InventoryItem(
            id: 'inv_tofu',
            name: '국산 손두부',
            category: '채소/농산물',
            currentQty: 4,
            minThreshold: 6,
            unit: '모',
            expiryDate: '2026-11-03', // D-1 임박
            recipeUnitPerServing: 1,
            linkedMenuNames: ['한돈 숙성 김치찌개'],
          ),
          InventoryItem(
            id: 'inv_pork',
            name: '한돈 앞다리살',
            category: '육류/해산물',
            currentQty: 20,
            minThreshold: 5,
            unit: '인분',
            expiryDate: '2026-11-10', // D-8 신선
            recipeUnitPerServing: 2,
            linkedMenuNames: ['한돈 숙성 김치찌개'],
          ),
        ];
        const menus = [
          PosMenuItem(
            id: 'm1',
            restaurantId: 'r1',
            name: '한돈 숙성 김치찌개',
            price: 9500,
            isAvailable: true,
            ingredients: ['국산 손두부', '한돈 앞다리살'],
          ),
        ];

        expect(
          items[0].expiryStatus(now: now),
          InventoryExpiryStatus.expiringSoon,
        );
        expect(items[1].expiryStatus(now: now), InventoryExpiryStatus.fresh);

        final capacities = service.calculateMenuCapacities(items, menus);
        expect(capacities.single.maxServings, 4);
        expect(capacities.single.bottleneckIngredientName, '국산 손두부');

        final shortages = service.calculateShortagesForTarget(
          items,
          menus,
          targetServingsPerMenu: 15,
        );
        expect(shortages, isNotEmpty);

        final replenished = service.replenishShortages(
          items,
          menus,
          targetServingsPerMenu: 15,
        );
        expect(replenished[0].currentQty, greaterThanOrEqualTo(15));
        expect(replenished[0].expiryDate, items[0].expiryDate);
      },
    );
  });

  group('PosReservation & PosMenuItem models', () {
    test('calculates required tables and seat accommodation', () {
      final res2 = PosReservation.fromJson({
        'id': 'res_1',
        'restaurantId': 'r1',
        'kind': 'RESERVATION',
        'customerName': '김대리',
        'partySize': 4,
        'status': 'OPEN',
        'createdAt': '2026-11-02T03:00:00Z',
      });
      final res6 = PosReservation.fromJson({
        'id': 'res_2',
        'restaurantId': 'r1',
        'kind': 'WAITING',
        'customerName': '박팀장',
        'partySize': 6,
        'status': 'OPEN',
        'createdAt': '2026-11-02T03:05:00Z',
      });

      expect(res2.requiredTables, 1);
      expect(res2.canAccommodateWith(1), isTrue);
      expect(res2.canAccommodateWith(0), isFalse);
      expect(res6.requiredTables, 2);
      expect(res6.canAccommodateWith(1), isFalse);
      expect(res6.canAccommodateWith(2), isTrue);
    });

    test('parses ingredients and allergens from PosMenuItem JSON', () {
      final menu = PosMenuItem.fromJson({
        'id': 'm1',
        'restaurant_id': 'r1',
        'name': '김치찌개',
        'price': 9000,
        'is_available': true,
        'prep_time_minutes': 12,
        'ingredients': ['돼지고기', '김치'],
        'allergens': ['돼지고기', '대두'],
      });

      expect(menu.prepTimeMinutes, 12);
      expect(menu.ingredients, ['돼지고기', '김치']);
      expect(menu.allergens, ['돼지고기', '대두']);
    });
  });

  testWidgets('InventoryManagementScreen shows pending message when unmapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: InventoryManagementScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('매장 매핑이 완료되면 식자재 재고를 관리할 수 있어요.'), findsOneWidget);
  });
}
