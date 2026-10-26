import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:capstone/main.dart';

void main() {
  testWidgets('첫 실행 시 한국어 서비스 소개 화면을 표시한다', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: LunchSyncApp()));
    await tester.pumpAndSettle();

    expect(find.text('LunchSync'), findsOneWidget);
    expect(find.text('AI가 추천하는 우리 팀 점심,\n함께 고르고 함께 즐기세요'), findsOneWidget);
    expect(find.text('서비스 이용을 위해 다음 권한이 필요해요'), findsOneWidget);
    expect(find.text('로그인·회원가입'), findsOneWidget);
    await tester.tap(find.text('로그인·회원가입'));
    await tester.pumpAndSettle();
    expect(find.text('카카오로 시작하기'), findsOneWidget);
    expect(find.text('둘러보기 (준비 중)'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
