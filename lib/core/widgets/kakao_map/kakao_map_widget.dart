import 'package:flutter/material.dart';

// 조건부 import:
//   - 웹 빌드(dart.library.html 있음) → kakao_map_web.dart 사용
//   - 그 외(모바일)                    → kakao_map_mobile.dart 사용
// 각 구현 파일은 동일한 시그니처의 `buildKakaoMap()` 함수를 제공해야 함.
import 'kakao_map_mobile.dart'
    if (dart.library.html) 'kakao_map_web.dart' as impl;

// ══════════════════════════════════════════════════════════
// 파일 역할: 카카오맵 위젯 공용 인터페이스
//
// 동작 방식:
//   - 카카오맵 JavaScript SDK를 WebView(모바일) / iframe(웹)으로 삽입
//   - 식당 위치에 핀을 찍고, 핀 클릭 시 식당 이름 말풍선 표시
//   - 지도 중심 좌표 = 핀 리스트의 평균 위치 (없으면 서울시청)
//
// 사용 예:
//   KakaoMapWidget(
//     pins: [
//       KakaoMapPin(name: '한솥도시락', lat: 37.5665, lng: 126.9780),
//     ],
//     height: 200,
//   )
//
// 주의:
//   - 카카오 개발자 콘솔에서 "플랫폼 → Web 사이트 도메인"에 localhost 등록 필요
//   - JavaScript 앱 키(AppConfig.kakaoJavaScriptAppKey)를 사용
// ══════════════════════════════════════════════════════════

/// 지도 위에 찍을 핀 하나의 데이터
class KakaoMapPin {
  const KakaoMapPin({
    required this.name,
    required this.lat,
    required this.lng,
  });

  /// 핀 클릭 시 말풍선에 표시될 식당 이름
  final String name;

  /// 위도
  final double lat;

  /// 경도
  final double lng;

  Map<String, dynamic> toJson() => {
        'name': name,
        'lat': lat,
        'lng': lng,
      };
}

/// 카카오맵 공용 위젯
///
/// 플랫폼별 구현은 `kakao_map_web.dart` / `kakao_map_mobile.dart`로 분리.
class KakaoMapWidget extends StatelessWidget {
  const KakaoMapWidget({
    super.key,
    required this.pins,
    required this.jsAppKey,
    this.myLocation,
    this.height = 200,
    this.defaultCenter = const KakaoMapPin(
      name: '서울시청',
      lat: 37.5665,
      lng: 126.9780,
    ),
    this.zoomLevel = 4,
  });

  /// 지도에 표시할 식당 핀 목록
  final List<KakaoMapPin> pins;

  /// 내 위치 핀 (GPS 조회 성공 시 전달). null이면 내 위치 표시 안 함.
  /// 식당 핀과 다른 파란색 원형 스타일로 렌더링됨.
  final KakaoMapPin? myLocation;

  /// 카카오 JavaScript 앱 키 (AppConfig.kakaoJavaScriptAppKey)
  final String jsAppKey;

  /// 지도 영역 높이 (px)
  final double height;

  /// pins/myLocation이 모두 비었을 때 사용할 기본 중심 좌표
  final KakaoMapPin defaultCenter;

  /// 카카오맵 확대 레벨 (1=가장 확대, 14=가장 축소, 일반적으로 3~5)
  final int zoomLevel;

  /// 지도 중심 좌표 계산 (우선순위):
  ///   1. myLocation이 있으면 내 위치 중심
  ///   2. 그 외에는 pins의 평균 위경도
  ///   3. 둘 다 없으면 defaultCenter
  KakaoMapPin _computeCenter() {
    if (myLocation != null) return myLocation!;
    if (pins.isEmpty) return defaultCenter;
    double sumLat = 0;
    double sumLng = 0;
    for (final p in pins) {
      sumLat += p.lat;
      sumLng += p.lng;
    }
    return KakaoMapPin(
      name: 'center',
      lat: sumLat / pins.length,
      lng: sumLng / pins.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _computeCenter();
    return SizedBox(
      height: height,
      child: ClipRRect(
        // 지도에도 앱 카드와 동일한 둥근 모서리 적용
        borderRadius: BorderRadius.circular(12),
        child: impl.buildKakaoMap(
          centerLat: center.lat,
          centerLng: center.lng,
          pins: pins,
          myLocation: myLocation,
          jsAppKey: jsAppKey,
          zoomLevel: zoomLevel,
        ),
      ),
    );
  }
}

/// 카카오맵 HTML 문자열 생성 (웹/모바일 공통)
///
/// JS 내부에서 `kakao.maps.load()`로 지연 로딩 + 핀을 JSON으로 주입.
/// 내 위치가 있으면 CustomOverlay로 파란 원형 마커를 추가로 그린다.
String buildKakaoMapHtml({
  required double centerLat,
  required double centerLng,
  required List<KakaoMapPin> pins,
  required String jsAppKey,
  required int zoomLevel,
  KakaoMapPin? myLocation,
}) {
  // 핀 데이터를 JavaScript 배열 리터럴로 직렬화
  // 예: [{"name":"한솥","lat":37.5,"lng":127.0}, ...]
  final pinsJson = pins.map((p) {
    // 따옴표가 포함된 이름이 있을 수 있어 기본적인 이스케이프 처리
    final escapedName = p.name.replaceAll('"', r'\"');
    return '{"name":"$escapedName","lat":${p.lat},"lng":${p.lng}}';
  }).join(',');

  // 내 위치 마커 생성 JS (파란 원 + 하얀 테두리 + 반투명 정확도 원)
  // 없으면 아예 JS 자체를 주입하지 않음 (비용 절감)
  final myLocationJs = myLocation == null
      ? ''
      : '''
    // ── 내 위치 마커 (파란 원형 오버레이) ───────────
    var myPos = new kakao.maps.LatLng(${myLocation.lat}, ${myLocation.lng});
    var myMarkerEl = document.createElement('div');
    myMarkerEl.style.cssText = 'width:16px;height:16px;border-radius:50%;' +
      'background:#2979FF;border:3px solid #fff;' +
      'box-shadow:0 0 0 4px rgba(41,121,255,0.25);';
    new kakao.maps.CustomOverlay({
      map: map,
      position: myPos,
      content: myMarkerEl,
      yAnchor: 0.5,
      xAnchor: 0.5
    });
''';

  return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
<style>
  html, body, #map { margin: 0; padding: 0; width: 100%; height: 100%; }
</style>
</head>
<body>
<div id="map"></div>
<script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=$jsAppKey&autoload=false"></script>
<script>
  kakao.maps.load(function() {
    var container = document.getElementById('map');
    var options = {
      center: new kakao.maps.LatLng($centerLat, $centerLng),
      level: $zoomLevel
    };
    var map = new kakao.maps.Map(container, options);

    var pins = [$pinsJson];
    pins.forEach(function(pin, index) {
      var pos = new kakao.maps.LatLng(pin.lat, pin.lng);
      var marker = new kakao.maps.Marker({ position: pos, map: map });

      // 식당 순위 번호 라벨 (마커 위 작은 원형 배지)
      // 2026-05-15 사장님 요청: "핀 위에 식당 번호도 보이면 좋겠다"
      var numLabel = document.createElement('div');
      numLabel.textContent = (index + 1);
      numLabel.style.cssText = 'background:#FF6B2C;color:#fff;font-size:11px;' +
                               'font-weight:700;border-radius:50%;width:20px;' +
                               'height:20px;display:flex;align-items:center;' +
                               'justify-content:center;box-shadow:0 1px 2px rgba(0,0,0,0.3);' +
                               'border:2px solid #fff;';
      new kakao.maps.CustomOverlay({
        map: map,
        position: pos,
        content: numLabel,
        yAnchor: 2.6,  // 마커 위쪽으로 살짝 띄움
      });

      var infowindow = new kakao.maps.InfoWindow({
        content: '<div style="padding:4px 8px;font-size:12px;font-weight:600;">' +
                 (index + 1) + '. ' + pin.name + '</div>'
      });
      kakao.maps.event.addListener(marker, 'click', function() {
        infowindow.open(map, marker);
      });
    });
$myLocationJs
  });
</script>
</body>
</html>
''';
}
