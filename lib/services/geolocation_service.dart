import 'package:geolocator/geolocator.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 사용자 GPS 위치 조회 서비스
//
// 플랫폼별 동작:
//   - Android/iOS: OS 위치 권한 요청 후 GPS/네트워크 기반 좌표 반환
//   - Web: 브라우저 geolocation API 사용 (최초 1회 권한 팝업)
//
// 권한 상태 4단계:
//   denied        — 아직 권한 요청 전
//   deniedForever — 사용자가 영구 거부 (앱 설정에서 직접 켜야 함)
//   whileInUse    — 앱 사용 중 허용
//   always        — 항상 허용
//
// 제공 API:
//   1) getCurrentPosition() — 1회성 스냅샷 (세션 생성·크롤링 등)
//   2) positionStream()     — 실시간 위치 스트림 (지도 내 위치 마커 갱신)
//
// 반환 값:
//   - getCurrentPosition: Position | null (권한 거부/GPS 꺼짐/타임아웃 시 null)
//   - positionStream    : Stream<Position> (사전 권한 실패 시 빈 스트림)
//
// 사용 예(스냅샷):
//   final pos = await GeolocationService().getCurrentPosition();
//   if (pos != null) print('${pos.latitude}, ${pos.longitude}');
//
// 사용 예(스트림):
//   final sub = GeolocationService()
//       .positionStream()
//       .listen((pos) => print('${pos.latitude}, ${pos.longitude}'));
//   // 화면 dispose 시 sub.cancel() 필수
// ══════════════════════════════════════════════════════════

class GeolocationService {
  const GeolocationService();

  /// 사용자 현재 위치 조회
  ///
  /// 내부 흐름:
  ///   1. 위치 서비스(OS 레벨 GPS) 활성 여부 확인
  ///   2. 앱 위치 권한 상태 확인 → 없으면 요청
  ///   3. getCurrentPosition() 호출
  ///
  /// 실패 시 null 반환 (예외 던지지 않음).
  Future<Position?> getCurrentPosition({
    Duration timeLimit = const Duration(seconds: 10),
  }) async {
    try {
      // ① OS 위치 서비스(GPS) 활성 여부 — 꺼져 있으면 측정 자체 불가
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // ignore: avoid_print
        print('[GeolocationService] OS 위치 서비스가 꺼져 있습니다.');
        return null;
      }

      // ② 앱 권한 상태 확인
      LocationPermission permission = await Geolocator.checkPermission();

      // 권한이 없으면 요청 (최초 진입 시)
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // ignore: avoid_print
          print('[GeolocationService] 사용자가 권한을 거부했습니다.');
          return null;
        }
      }

      // 영구 거부 상태면 앱 설정으로 직접 이동해야 함
      if (permission == LocationPermission.deniedForever) {
        // ignore: avoid_print
        print('[GeolocationService] 권한 영구 거부 — 앱 설정에서 직접 허용 필요');
        return null;
      }

      // ③ 실제 좌표 조회 (timeLimit 초과 시 TimeoutException)
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeLimit,
        ),
      );
      return position;
    } catch (e) {
      // ignore: avoid_print
      print('[GeolocationService] 위치 조회 에러: $e');
      return null;
    }
  }

  /// 사용자 위치 실시간 스트림
  ///
  /// 내부 흐름:
  ///   1. OS 위치 서비스 활성 여부 확인 (꺼져 있으면 빈 스트림)
  ///   2. 권한 확인/요청 (거부 시 빈 스트림)
  ///   3. Geolocator.getPositionStream() 구독
  ///
  /// 파라미터:
  ///   - [distanceFilterMeters] 이 거리 이상 이동했을 때만 이벤트 발행
  ///     (기본 10m — 책상에서 살짝 흔들려도 이벤트가 폭주하지 않도록 억제)
  ///   - [accuracy] 정확도 레벨 (기본 high)
  ///
  /// 주의:
  ///   - 웹(데스크톱 크롬)은 실제 GPS가 없어 WiFi/IP 기반으로 추정되므로
  ///     스트림으로 계속 받아도 같은 좌표가 반복될 수 있음.
  ///   - 호출한 위젯은 dispose() 시 반드시 StreamSubscription.cancel() 필요.
  Stream<Position> positionStream({
    int distanceFilterMeters = 10,
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async* {
    try {
      // ① OS 위치 서비스 활성 여부
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // ignore: avoid_print
        print('[GeolocationService:stream] OS 위치 서비스가 꺼져 있습니다.');
        return;
      }

      // ② 앱 권한 상태 확인/요청
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // ignore: avoid_print
          print('[GeolocationService:stream] 사용자가 권한을 거부했습니다.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        // ignore: avoid_print
        print('[GeolocationService:stream] 권한 영구 거부 — 설정에서 직접 허용 필요');
        return;
      }

      // ③ 실제 스트림 구독 — 모든 이벤트를 호출자에게 그대로 전달
      yield* Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilterMeters,
        ),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[GeolocationService:stream] 스트림 에러: $e');
    }
  }
}
