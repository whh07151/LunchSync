// ══════════════════════════════════════════════════════════
// 파일 역할: 두 좌표 사이의 거리를 계산하고 표시용 문자열로 변환하는 유틸
//
// 왜 별도 파일?
//   normalizer.dart 는 카테고리·가격·태그 등 도메인 정규화 전용이라
//   "거리 계산"이라는 수치 연산 헬퍼는 의미 단위가 달라 분리.
//
// 사용처:
//   - lib/features/home/home_screen.dart            (AI 추천 식당 카드)
//   - lib/features/session/recommendation_list_screen.dart (CU-11 추천 리스트)
//   - lib/features/restaurant/restaurant_detail_screen.dart (CU-13 식당 상세)
//
// 영감:
//   OpenTable / 배달앱 카드의 핵심 3요소 = cuisine · price · distance.
//   사용자가 "지금 갈만한 곳인지" 판단하기 위해 거리 한 줄이 결정적.
//
// 정책:
//   - 사용자 현재 좌표가 없으면(권한 거부/위치 서비스 꺼짐) null 반환 → 호출자가 UI 숨김
//   - 식당 lat/lng 이 누락된 경우도 null 반환
//
// ⚠️ 디자인 토큰/위젯 구조 변경 없음 — 이 모듈은 순수 함수만 제공.
// ══════════════════════════════════════════════════════════

import 'dart:math' as math;

/// 지구 반지름(미터).
/// Haversine 공식에서 평균 지구 반지름을 6,371km로 사용 (WGS84 평균값).
const double _earthRadiusMeters = 6371000.0;

/// 두 좌표 사이의 직선 거리(미터)를 Haversine 공식으로 계산.
///
/// Haversine 공식이란?
///   - 구(球) 위의 두 점 사이의 대원(great-circle) 거리를 구하는 공식.
///   - 도시 내 짧은 거리(수 km)에서 오차가 매우 작아 식당 거리 표기에 충분.
///
/// 좌표는 모두 도(degree) 단위. 함수 내부에서 라디안으로 환산.
double haversineMeters({
  required double lat1,
  required double lng1,
  required double lat2,
  required double lng2,
}) {
  // ── 도(degree) → 라디안 변환 ──
  // 삼각함수 계산은 라디안 단위로만 가능하므로 사전 변환 필수.
  final lat1Rad = lat1 * math.pi / 180.0;
  final lat2Rad = lat2 * math.pi / 180.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;  // 위도 차이
  final dLng = (lng2 - lng1) * math.pi / 180.0;  // 경도 차이

  // ── Haversine 본 공식 ──
  // a = sin²(Δφ/2) + cos(φ1)·cos(φ2)·sin²(Δλ/2)
  // c = 2 · atan2(√a, √(1−a))
  // d = R · c
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1Rad) * math.cos(lat2Rad) *
          math.sin(dLng / 2) * math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

  return _earthRadiusMeters * c;
}

/// 미터(double) 거리를 사용자 친화적인 표시 문자열로 변환.
///
/// 표기 규칙:
///   - 1,000m 미만 → "320m"  (정수 m 단위, 반올림)
///   - 1,000m 이상 → "1.2km" (소수점 1자리 km 단위)
///
/// 매우 가까울 때(0m, 1m 같은 GPS 노이즈)도 그냥 "0m" "1m" 로 노출 — 호출자가 필요 시 필터링.
///
/// 예시:
///   formatDistance(0)     → "0m"
///   formatDistance(45.7)  → "46m"
///   formatDistance(320)   → "320m"
///   formatDistance(999)   → "999m"
///   formatDistance(1000)  → "1.0km"
///   formatDistance(1234)  → "1.2km"
///   formatDistance(12345) → "12.3km"
String formatDistance(double meters) {
  // 음수가 들어오면 부호 무시(이론상 발생 안 되지만 방어).
  final m = meters.abs();

  if (m < 1000) {
    // 미터 단위: 반올림 후 정수 표기
    return '${m.round()}m';
  }

  // km 단위: 소수점 1자리. 1000으로 나누어 km로 환산.
  final km = m / 1000.0;
  return '${km.toStringAsFixed(1)}km';
}

/// 사용자 현재 좌표와 식당 좌표를 받아 표시용 거리 문자열을 반환.
///
/// 좌표가 하나라도 null 이면 null 반환 — 호출자는 거리 라인 자체를 숨김.
///
/// 사용 예:
///   final label = distanceLabel(
///     userLat: 37.501, userLng: 127.039,
///     targetLat: r.lat, targetLng: r.lng,
///   );
///   if (label != null) Text('거리 $label');  // "거리 320m"
String? distanceLabel({
  required double? userLat,
  required double? userLng,
  required double? targetLat,
  required double? targetLng,
}) {
  if (userLat == null || userLng == null) return null;
  if (targetLat == null || targetLng == null) return null;

  final meters = haversineMeters(
    lat1: userLat,
    lng1: userLng,
    lat2: targetLat,
    lng2: targetLng,
  );
  return formatDistance(meters);
}
