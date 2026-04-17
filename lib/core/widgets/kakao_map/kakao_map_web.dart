// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'kakao_map_widget.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 카카오맵 웹 구현
//
// HtmlElementView + <iframe srcdoc>으로 카카오맵 HTML을 삽입.
// webview_flutter는 웹에서 직접 동작하지 않으므로 iframe을 직접 등록.
//
// 주의:
//   - 카카오 개발자 콘솔 "플랫폼 → Web" 에 http://localhost:8080 등록 필수
//   - viewType은 인스턴스마다 고유해야 함 (registerViewFactory 중복 방지)
// ══════════════════════════════════════════════════════════

/// 각 위젯 인스턴스에 고유 viewType을 부여하기 위한 카운터
int _viewTypeCounter = 0;

/// 웹(HtmlElementView + iframe) 기반 카카오맵 위젯 빌더
Widget buildKakaoMap({
  required double centerLat,
  required double centerLng,
  required List<KakaoMapPin> pins,
  required String jsAppKey,
  required int zoomLevel,
  KakaoMapPin? myLocation,
}) {
  final html5 = buildKakaoMapHtml(
    centerLat: centerLat,
    centerLng: centerLng,
    pins: pins,
    myLocation: myLocation,
    jsAppKey: jsAppKey,
    zoomLevel: zoomLevel,
  );

  // 매 빌드마다 새 viewType 사용 (hot reload 시 기존 iframe 재활용 회피)
  final viewType = 'kakao-map-${_viewTypeCounter++}';

  // platformViewRegistry.registerViewFactory: Flutter 웹에서
  // 특정 viewType 문자열이 요청될 때 실제 DOM 엘리먼트를 반환하는 팩토리 등록
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
    final iframe = html.IFrameElement()
      ..srcdoc = html5
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      // sandbox: JS/동일 출처 허용 — iframe 내부에서 카카오 SDK 동작해야 함
      ..setAttribute('sandbox', 'allow-scripts allow-same-origin');
    return iframe;
  });

  return HtmlElementView(viewType: viewType);
}
