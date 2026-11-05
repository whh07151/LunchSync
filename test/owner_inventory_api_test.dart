import 'dart:convert';
import 'package:capstone/services/owner_inventory_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'local replenishment and edits preserve the server concurrency revision',
    () {
      const item = InventoryItem(
        id: 'item',
        name: 'tofu',
        category: 'other',
        currentQty: 1,
        minThreshold: 5,
        unit: 'pcs',
        updatedAt: 'server-revision',
      );
      expect(item.copyWith(currentQty: 2).updatedAt, 'server-revision');
      expect(
        const OwnerInventoryService()
            .replenishShortages([item], [])
            .single
            .updatedAt,
        'server-revision',
      );
    },
  );

  test(
    '409 exposes a conflict that requires refreshing the server inventory',
    () async {
      await http.runWithClient(
        () async {
          await expectLater(
            const OwnerInventoryService().saveInventory(
              'rest',
              [],
              accessToken: 'token',
            ),
            throwsA(
              isA<OwnerInventoryException>().having(
                (error) => error.isConflict,
                'isConflict',
                isTrue,
              ),
            ),
          );
        },
        () => MockClient(
          (request) async =>
              http.Response('{"code":"INVENTORY_VERSION_CONFLICT"}', 409),
        ),
      );
    },
  );
  test(
    'save returns the new server revision and sends the original revision',
    () async {
      const item = InventoryItem(
        id: 'item',
        name: 'tofu',
        category: 'other',
        currentQty: 4,
        minThreshold: 1,
        unit: 'pcs',
        updatedAt: '2026-11-05T01:00:00Z',
      );
      final dynamic operation = http.runWithClient(
        () => const OwnerInventoryService().saveInventory('rest', [
          item.copyWith(currentQty: 5),
        ], accessToken: 'token'),
        () => MockClient((request) async {
          final row = (jsonDecode(request.body)['items'] as List).single as Map;
          expect(row['updatedAt'], item.updatedAt);
          return http.Response(
            jsonEncode({
              'data': [
                {
                  ...item.toJson(),
                  'currentQty': 5,
                  'updatedAt': '2026-11-05T02:00:00Z',
                },
              ],
            }),
            200,
          );
        }),
      );
      final dynamic result = await operation;
      expect(result, isA<List<InventoryItem>>());
      expect(
        (result as List<InventoryItem>).single.updatedAt,
        '2026-11-05T02:00:00Z',
      );
    },
  );
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'ls_jwt': 'stale-token',
      'ls_owner_inventory_v1_rest':
          '[{"id":"old","name":"old","currentQty":50}]',
    }),
  );

  test('an empty server inventory stays empty and reads never write', () async {
    final requests = <http.Request>[];
    final result = await http.runWithClient(
      () => const OwnerInventoryService().loadInventory(
        'rest',
        accessToken: 'current-token',
      ),
      () => MockClient((request) async {
        requests.add(request);
        return http.Response('{"data":[]}', 200);
      }),
    );
    expect(result, isEmpty);
    expect(requests.map((r) => r.method).toList(), ['GET']);
    expect(requests.single.headers['authorization'], 'Bearer current-token');
  });

  test(
    'server read failure never replaces server data with cached inventory',
    () async {
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          await expectLater(
            const OwnerInventoryService().loadInventory(
              'rest',
              accessToken: 'current-token',
            ),
            throwsA(isA<OwnerInventoryException>()),
          );
        },
        () => MockClient((request) async {
          requests.add(request);
          return http.Response('unavailable', 503);
        }),
      );
      expect(requests.map((r) => r.method).toList(), ['GET']);
    },
  );

  test(
    'server inventory keeps unspecified expiry and no fabricated stock',
    () async {
      final result = await http.runWithClient(
        () => const OwnerInventoryService().loadInventory(
          'rest',
          accessToken: 'current-token',
        ),
        () => MockClient(
          (request) async => http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'item',
                  'name': 'tofu',
                  'currentQty': 0,
                  'expiryDate': null,
                },
              ],
            }),
            200,
          ),
        ),
      );
      expect(result.single.expiryDate, isNull);
      expect(result.single.currentQty, 0);
    },
  );

  test('failed save throws and leaves previous cache untouched', () async {
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString('ls_owner_inventory_v1_rest');
    await http.runWithClient(() async {
      await expectLater(
        const OwnerInventoryService().saveInventory(
          'rest',
          [],
          accessToken: 'current-token',
        ),
        throwsA(isA<OwnerInventoryException>()),
      );
    }, () => MockClient((request) async => http.Response('forbidden', 403)));
    expect(prefs.getString('ls_owner_inventory_v1_rest'), before);
  });

  test(
    'business status and hours read and save the server contract with current token',
    () async {
      var status = 'CLOSED';
      var hours = '12:00~19:00';
      await http.runWithClient(
        () async {
          const service = OwnerInventoryService();
          expect(
            await service.loadBusinessStatus(
              'rest',
              accessToken: 'current-token',
            ),
            StoreBusinessStatus.closed,
          );
          expect(
            await service.loadOperatingHoursNote(
              'rest',
              accessToken: 'current-token',
            ),
            hours,
          );
          await service.saveBusinessStatus(
            'rest',
            StoreBusinessStatus.breakTime,
            accessToken: 'current-token',
          );
          expect(status, 'BREAK_TIME');
          await service.saveOperatingHoursNote(
            'rest',
            ' 11:00~18:00 ',
            accessToken: 'current-token',
          );
          expect(hours, '11:00~18:00');
        },
        () => MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer current-token');
          expect(request.url.path, endsWith('/store-status'));
          if (request.method == 'PATCH') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            status = body['businessStatus'] as String? ?? status;
            hours = body['operatingHoursNote'] as String? ?? hours;
          }
          return http.Response(
            jsonEncode({
              'data': {'businessStatus': status, 'operatingHoursNote': hours},
            }),
            200,
          );
        }),
      );
    },
  );

  test('no explicit current token fails without sending a request', () async {
    await http.runWithClient(() async {
      await expectLater(
        const OwnerInventoryService().loadInventory('rest', accessToken: ''),
        throwsA(isA<OwnerInventoryException>()),
      );
    }, () => MockClient((request) async => fail('must not use stale ls_jwt')));
  });
}
