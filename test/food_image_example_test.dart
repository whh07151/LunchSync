import 'package:capstone/core/widgets/food_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('실제 사진이 없으면 예시 이미지로 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FoodImage(imageUrl: null, categoryLabel: '면류')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('예시'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/menu_examples/noodles.png',
    );
    expect(tester.takeException(), isNull);
  });
}
