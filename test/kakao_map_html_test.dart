import 'package:capstone/core/widgets/kakao_map/kakao_map_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restaurant names cannot break the map script or info window', () {
    final html = buildKakaoMapHtml(
      centerLat: 37.5665,
      centerLng: 126.9780,
      pins: const [
        KakaoMapPin(
          name: '</script><img src=x onerror=alert(1)> " \\',
          lat: 37.5665,
          lng: 126.9780,
        ),
      ],
      jsAppKey: 'a' * 32,
      zoomLevel: 4,
    );

    expect(html, isNot(contains('</script><img')));
    expect(html, contains(r'\u003C/script>'));
    expect(html, contains(".replace(/</g, '&lt;')"));
    expect(html, contains('window.updateLunchSyncLocation'));
  });

  testWidgets('missing map key shows a clear fallback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KakaoMapWidget(pins: [], jsAppKey: '', height: 200),
        ),
      ),
    );
    expect(find.text('지도 설정이 없어 목록으로 확인해 주세요'), findsOneWidget);
  });
}
