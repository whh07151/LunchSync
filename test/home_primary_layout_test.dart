import 'package:capstone/features/home/widgets/home_primary_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _subject(double width) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: const HomePrimaryLayout(
            todaySession: SizedBox(height: 120, child: Text('실제 세션 영역')),
            quickActions: SizedBox(height: 120, child: Text('실제 빠른 실행 영역')),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('모바일에서는 오늘 세션을 빠른 실행보다 먼저 배치한다', (tester) async {
    await tester.pumpWidget(_subject(390));

    expect(find.byKey(const ValueKey('home-primary-compact')), findsOneWidget);
    expect(find.text('오늘의 점심 세션'), findsOneWidget);
    expect(find.text('바로가기'), findsOneWidget);

    final sessionTop = tester.getTopLeft(find.text('오늘의 점심 세션')).dy;
    final actionsTop = tester.getTopLeft(find.text('바로가기')).dy;
    expect(sessionTop, lessThan(actionsTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('넓은 웹에서는 핵심 세션과 빠른 실행을 나란히 배치한다', (tester) async {
    await tester.pumpWidget(_subject(1000));

    expect(find.byKey(const ValueKey('home-primary-wide')), findsOneWidget);

    final sessionTop = tester.getTopLeft(find.text('오늘의 점심 세션')).dy;
    final actionsTop = tester.getTopLeft(find.text('바로가기')).dy;
    expect((sessionTop - actionsTop).abs(), lessThan(2));
    expect(tester.takeException(), isNull);
  });
}
