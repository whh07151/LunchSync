import 'dart:async';

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

  String _mapHtml() => buildKakaoMapHtml(
    centerLat: widget.centerLat,
    centerLng: widget.centerLng,
    pins: widget.pins,
    myLocation: widget.myLocation,
    jsAppKey: widget.jsAppKey,
    zoomLevel: widget.zoomLevel,
  );

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // 투명 배경 방지: 로딩 중 검은 화면 깜빡임 회피
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _syncLocation(),
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            final uri = Uri.tryParse(request.url);
            if (request.url == 'about:blank' ||
                uri?.scheme == 'data' ||
                (uri?.scheme == 'http' &&
                    uri?.host == 'localhost' &&
                    uri?.port == 8080)) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      // 2026-05-15 사장님 라이브 발견 — 웹에서는 지도 잘 뜨는데 모바일만 안 뜸.
      // 카카오 개발자센터 "웹 도메인 화이트리스트" 에 http://localhost:8080 은
      // 등록돼 있지만 https://localhost (모바일 baseUrl) 는 없을 수 있음.
      // → 등록된 도메인 http://localhost:8080 으로 baseUrl 통일해 화이트리스트
      //   미스매치 제거. (실제 호스트 통신은 안 함 — origin 만 카카오 SDK 검증용)
      ..loadHtmlString(_mapHtml(), baseUrl: 'http://localhost:8080/');
  }

  @override
  void didUpdateWidget(covariant _MobileKakaoMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pinsChanged =
        oldWidget.pins.length != widget.pins.length ||
        List.generate(widget.pins.length, (i) => i).any((i) {
          final before = oldWidget.pins[i];
          final after = widget.pins[i];
          return before.name != after.name ||
              before.lat != after.lat ||
              before.lng != after.lng;
        });
    if (pinsChanged ||
        oldWidget.jsAppKey != widget.jsAppKey ||
        oldWidget.zoomLevel != widget.zoomLevel) {
      unawaited(
        _controller.loadHtmlString(
          _mapHtml(),
          baseUrl: 'http://localhost:8080/',
        ),
      );
      return;
    }
    if (oldWidget.myLocation?.lat != widget.myLocation?.lat ||
        oldWidget.myLocation?.lng != widget.myLocation?.lng) {
      _syncLocation(recenter: oldWidget.myLocation == null);
    }
  }

  void _syncLocation({bool recenter = false}) {
    final lat = widget.myLocation?.lat;
    final lng = widget.myLocation?.lng;
    unawaited(
      _controller
          .runJavaScript(
            'window.updateLunchSyncLocation(${lat ?? 'null'}, ${lng ?? 'null'}, $recenter);',
          )
          .catchError((Object _) {
            // The SDK may still be loading; the HTML starts with the latest position
            // and onPageFinished retries this update.
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
