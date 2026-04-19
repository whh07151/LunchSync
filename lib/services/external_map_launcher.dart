import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 외부 지도 앱 길찾기 실행 헬퍼
//
// 지원 대상:
//   - 카카오맵  (kakaomap://)
//   - 네이버 지도 (nmap://)
//
// 폴백 전략:
//   모바일 → 앱 URL scheme 실행 시도 → 실패 시 웹 URL로 열기
//   웹      → 처음부터 웹 URL로 열기
//
// 참고 문서:
//   - 카카오맵 URL: https://apis.map.kakao.com/android/guide/#appscheme
//   - 네이버 지도 URL: https://www.ncloud.com/ 검색
// ══════════════════════════════════════════════════════════

class ExternalMapLauncher {
  const ExternalMapLauncher();

  /// 카카오맵으로 길찾기 실행
  ///
  /// - destLat/destLng: 도착지 좌표 (식당)
  /// - destName: 도착지 이름 (라벨 표시용)
  /// - mode: 'CAR' | 'PUBLICTRANSIT' | 'FOOT' | 'BICYCLE' (기본 FOOT)
  Future<bool> openKakaoRoute({
    required double destLat,
    required double destLng,
    required String destName,
    String mode = 'FOOT',
  }) async {
    // 웹에서는 앱 스킴이 동작하지 않으므로 바로 웹 URL로
    if (kIsWeb) {
      return _launch(_kakaoWebUrl(
        destLat: destLat,
        destLng: destLng,
        destName: destName,
      ));
    }

    // 모바일: 앱 스킴 먼저 시도
    final appUri = Uri.parse(
      'kakaomap://route?ep=$destLat,$destLng&by=${_kakaoBy(mode)}',
    );
    if (await canLaunchUrl(appUri)) {
      return launchUrl(appUri);
    }

    // 폴백: 웹 URL
    return _launch(_kakaoWebUrl(
      destLat: destLat,
      destLng: destLng,
      destName: destName,
    ));
  }

  /// 네이버 지도로 길찾기 실행
  ///
  /// - destLat/destLng: 도착지 좌표
  /// - destName: 도착지 이름
  Future<bool> openNaverRoute({
    required double destLat,
    required double destLng,
    required String destName,
  }) async {
    // 웹에서는 바로 웹 URL
    if (kIsWeb) {
      return _launch(_naverWebUrl(
        destLat: destLat,
        destLng: destLng,
        destName: destName,
      ));
    }

    // 모바일: nmap:// 앱 스킴 시도
    // 네이버 지도는 appname 파라미터가 있어야 앱이 돌아올 때 복귀 가능
    final encodedName = Uri.encodeComponent(destName);
    final appUri = Uri.parse(
      'nmap://route/public?dlat=$destLat&dlng=$destLng'
      '&dname=$encodedName&appname=com.lunchsync',
    );
    if (await canLaunchUrl(appUri)) {
      return launchUrl(appUri);
    }

    // 폴백: 웹 URL
    return _launch(_naverWebUrl(
      destLat: destLat,
      destLng: destLng,
      destName: destName,
    ));
  }

  // ── 내부 유틸 ─────────────────────────────────────────
  Future<bool> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  // 카카오맵 웹 길찾기 URL
  // 형식: https://map.kakao.com/link/to/이름,위도,경도
  String _kakaoWebUrl({
    required double destLat,
    required double destLng,
    required String destName,
  }) {
    final encodedName = Uri.encodeComponent(destName);
    return 'https://map.kakao.com/link/to/$encodedName,$destLat,$destLng';
  }

  // 네이버 지도 웹 길찾기 URL
  // 형식: https://map.naver.com/p/directions/-/위도,경도,이름/-/transit
  String _naverWebUrl({
    required double destLat,
    required double destLng,
    required String destName,
  }) {
    final encodedName = Uri.encodeComponent(destName);
    return 'https://map.naver.com/p/directions/-/$destLng,$destLat,$encodedName/-/transit';
  }

  // 카카오맵 이동수단 파라미터
  String _kakaoBy(String mode) {
    switch (mode) {
      case 'CAR':
        return 'CAR';
      case 'PUBLICTRANSIT':
        return 'PUBLICTRANSIT';
      case 'BICYCLE':
        return 'BICYCLE';
      case 'FOOT':
      default:
        return 'FOOT';
    }
  }
}
