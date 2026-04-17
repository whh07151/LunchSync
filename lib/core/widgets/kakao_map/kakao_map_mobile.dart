import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'kakao_map_widget.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 카카오맵 모바일 구현 (Android/iOS)
//
// webview_flutter의 WebViewController에 HTML 문자열을 직접 로드.
// loadHtmlString은 file:// 스킴을 baseUrl로 넣어야 외부 리소스(카카오 SDK)를
// 로드할 수 있음 → baseUrl을 https://localhost로 지정.
// ══════════════════════════════════════════════════════════

/// 모바일(webview_flutter) 기반 카카오맵 위젯 빌더
Widget buildKakaoMap({
  required double centerLat,
  required double centerLng,
  required List<KakaoMapPin> pins,
  required String jsAppKey,
  required int zoomLevel,
  KakaoMapPin? myLocation,
}) {
  return _MobileKakaoMap(
    centerLat: centerLat,
    centerLng: centerLng,
    pins: pins,
    myLocation: myLocation,
    jsAppKey: jsAppKey,
    zoomLevel: zoomLevel,
  );
}

class _MobileKakaoMap extends StatefulWidget {
  const _MobileKakaoMap({
    required this.centerLat,
    required this.centerLng,
    required this.pins,
    required this.jsAppKey,
    required this.zoomLevel,
    this.myLocation,
  });

  final double centerLat;
  final double centerLng;
  final List<KakaoMapPin> pins;
  final KakaoMapPin? myLocation;
  final String jsAppKey;
  final int zoomLevel;

  @override
  State<_MobileKakaoMap> createState() => _MobileKakaoMapState();
}

class _MobileKakaoMapState extends State<_MobileKakaoMap> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    final html = buildKakaoMapHtml(
      centerLat: widget.centerLat,
      centerLng: widget.centerLng,
      pins: widget.pins,
      myLocation: widget.myLocation,
      jsAppKey: widget.jsAppKey,
      zoomLevel: widget.zoomLevel,
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // 투명 배경 방지: 로딩 중 검은 화면 깜빡임 회피
      ..setBackgroundColor(Colors.white)
      // baseUrl을 http로 지정해야 외부 스크립트 태그(카카오 SDK)가 로드됨
      ..loadHtmlString(html, baseUrl: 'https://localhost/');
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
