import 'dart:async';
import 'dart:convert';
import 'package:capstone/features/menu/menu_screen.dart';
import 'package:capstone/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _User extends UserNotifier {
  @override
  UserState build() => const UserState(accessToken: 'test', userId: 'user');
}

void main() {
  testWidgets('first add and rapid quantity changes save in order', (
    tester,
  ) async {
    final firstWrite = Completer<http.Response>();
    final quantities = <int>[];
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [userProvider.overrideWith(_User.new)],
            child: const MaterialApp(
              home: MenuScreen(
                restaurantId: 'restaurant',
                restaurantName: '식당',
                sessionId: 'session',
              ),
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        await tester.tap(find.text('담기'));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump();
        expect(quantities, [1]);
        firstWrite.complete(http.Response('{"data":[]}', 201));
        for (var i = 0; i < 5; i++) {
          await tester.pump();
        }
        expect(quantities, [1, 2]);
        await tester.tap(find.byIcon(Icons.remove_rounded));
        for (var i = 0; i < 5; i++) {
          await tester.pump();
        }
        expect(quantities, [1, 2, 1]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
      () => MockClient((request) async {
        if (request.method == 'POST') {
          quantities.add(
            (jsonDecode(request.body) as Map<String, dynamic>)['quantity']
                as int,
          );
          if (quantities.length == 1) return firstWrite.future;
          return http.Response('{"data":[]}', 201);
        }
        if (request.url.path.endsWith('/menus')) {
          return http.Response(
            jsonEncode({
              'data': {
                'menus': [
                  {
                    'id': 'menu',
                    'name': '점심',
                    'price': 1000,
                    'source': 'MANUAL',
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{"data":[]}', 200);
      }),
    );
  });
}
