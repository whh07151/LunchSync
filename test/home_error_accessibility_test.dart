import 'package:capstone/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(20), child: child),
    ),
  );
}

void main() {
  testWidgets('세션 조회 오류는 한국어 재시도를 표시하고 생성 CTA를 숨긴다', (tester) async {
    var retryCount = 0;

    await tester.pumpWidget(
      _wrap(
        HomeTodaySessionsErrorCard(
          message: '서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.',
          onRetry: () => retryCount++,
        ),
      ),
    );

    expect(find.text('오늘의 세션을 불러오지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('점심 만들기'), findsNothing);

    await tester.tap(find.text('다시 시도'));
    expect(retryCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('알림 버튼의 툴팁과 의미론에 실제 미읽음 개수를 포함한다', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              HomeNotificationButton(unreadCount: 12, onPressed: () {}),
            ],
          ),
        ),
      ),
    );

    const label = '알림, 읽지 않음 12개';
    expect(find.byTooltip(label), findsOneWidget);
    expect(find.bySemanticsLabel(label), findsOneWidget);
    expect(find.text('9+'), findsOneWidget);
    expect(tester.takeException(), isNull);

    semantics.dispose();
  });
}
