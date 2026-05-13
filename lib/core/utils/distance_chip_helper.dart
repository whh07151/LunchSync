// ══════════════════════════════════════════════════════════
// 파일 역할: GPS 거리(미터)를 사용자 친화적 "거리 칩" 라벨로 변환하는 헬퍼
//
// 왜 분리?
//   - distance_calculator.dart 는 Haversine 수치 계산 + "320m / 1.2km" 같은
//     원시 표기만 담당. 사장님 피드백(스크린샷 분석)에서 "도보 1~2분 거리" 같은
//     도보/이동 칩이 13km 카드에도 박혀 있는 모순이 보고됨.
//   - 백엔드 reasons 배열은 비율(반경 대비) 기반이라 실거리와 어긋날 수 있어
//     프론트에서 실거리로 다시 라벨링하는 단일 진실 소스 함수가 필요했음.
//
// 사용 가이드:
//   1) 식당 좌표 + 내 좌표로 distanceLabel(...) 결과 또는 raw meters를 받음
//   2) walkChipFor(meters) 호출 → "가까운 거리" / "도보 5분" / "차 10분" 등 반환
//   3) null 이면 카드에서 칩 자체를 그리지 않음 (위치 권한 없음·좌표 없음)
//
// 분기 정책 (사장님 피드백 기준):
//   - 0 ~ 200m       → "바로 앞"        (눈에 보이는 거리)
//   - 200 ~ 500m     → "가까운 거리"     (한 골목 안)
//   - 500m ~ 1km     → "도보 5~10분"   (걸어서 부담 적음)
//   - 1km ~ 1.5km    → "도보 15분"     (걸을 수는 있는 한계)
//   - 1.5km ~ 5km    → "차로 N분"       (도보 비추, 차 권장)
//   - 5km 이상       → "거리 N km"      (이동 부담 — 모순 라벨 방지)
//
// 도보 속도 가정: 4 km/h ≒ 67 m/min (성인 평균)
// 차량 속도 가정: 30 km/h (시내 평균, 신호 포함)
//
// ⚠️ 색상/타이포는 전혀 다루지 않음. 호출자가 자체 텍스트 위젯으로 렌더링하면 됨.
// ══════════════════════════════════════════════════════════

import 'distance_calculator.dart' show haversineMeters;

/// 미터 → 칩 라벨 변환의 단일 진실 함수.
///
/// 좌표가 모두 있을 때만 의미 있는 칩이 반환된다.
/// null 을 반환하면 호출자는 칩을 아예 그리지 않아야 한다(디자인 유지 원칙).
///
/// 사용 예 (recommendation_list_screen.dart):
/// ```dart
/// final chip = walkChipForCoords(
///   userLat: _userLat, userLng: _userLng,
///   targetLat: rec.lat, targetLng: rec.lng,
/// );
/// if (chip != null) Text(chip);  // "도보 5~10분"
/// ```
String? walkChipForCoords({
  required double? userLat,
  required double? userLng,
  required double? targetLat,
  required double? targetLng,
}) {
  // ── 좌표 누락 방어 ──────────────────────────────────────
  // 위치 권한 거부 / GPS 꺼짐 / 식당 lat/lng 누락(크롤 실패 등)이면 null.
  // 호출자가 칩을 안 그리도록 명확히 분기.
  if (userLat == null || userLng == null) return null;
  if (targetLat == null || targetLng == null) return null;

  // ── 실거리 계산 ─────────────────────────────────────────
  // Haversine 공식으로 미터 단위 직선 거리.
  // 도시 내 짧은 거리(수 km)에서 오차가 매우 작아 충분히 정확.
  final meters = haversineMeters(
    lat1: userLat,
    lng1: userLng,
    lat2: targetLat,
    lng2: targetLng,
  );
  return walkChipFor(meters);
}

/// 미터(double) → 칩 라벨 직접 변환.
///
/// 분기 표 (파일 헤더 참조):
///   ≤ 200m         → "바로 앞"
///   ≤ 500m         → "가까운 거리"
///   ≤ 1,000m       → "도보 5~10분"
///   ≤ 1,500m       → "도보 15분"
///   ≤ 5,000m       → "차로 N분"
///   그 외           → "거리 N km"
///
/// 음수(이론상 없음)는 부호를 무시.
String walkChipFor(double meters) {
  // 음수 방어 — 부호 무시
  final m = meters.abs();

  // ── 매우 가까움 ─────────────────────────────────────────
  // 눈에 보이는 거리. "도보 N분" 같은 시간 라벨보다 더 직관적.
  if (m <= 200) {
    return '바로 앞';
  }

  // ── 가까움 ─────────────────────────────────────────────
  // 한 골목 정도. 도보 시간 명시할 필요가 없을 만큼 짧음.
  if (m <= 500) {
    return '가까운 거리';
  }

  // ── 일반 도보 범위 ──────────────────────────────────────
  // 4 km/h 기준 500m=7.5분 / 1km=15분.
  // 점심 도보 식당의 표준 범위 — "도보 5~10분" 으로 표기.
  if (m <= 1000) {
    return '도보 5~10분';
  }

  // ── 도보 가능 한계 ──────────────────────────────────────
  // 1~1.5km는 시간 여유 있을 때 걷는 사람용 — "도보 15분".
  if (m <= 1500) {
    return '도보 15분';
  }

  // ── 차량 권장 구간 ──────────────────────────────────────
  // 1.5~5km 는 도보 부담 → "차로 N분" (30 km/h 기준).
  // 예: 3km → 6분, 5km → 10분.
  if (m <= 5000) {
    // 30 km/h = 500 m/min
    final carMinutes = (m / 500).round();
    // 0분이 되지 않도록 최소 1분 보장
    final safeMinutes = carMinutes < 1 ? 1 : carMinutes;
    return '차로 $safeMinutes분';
  }

  // ── 장거리 ─────────────────────────────────────────────
  // 5km 초과는 "도보"/"차로 N분" 어느 쪽도 정확히 표현하기 어려움.
  // 단순 km 표기로 모순(13km + 도보 1~2분) 방지.
  final km = (m / 1000).toStringAsFixed(1);
  return '거리 $km km';
}

/// 백엔드 reasons 배열에서 "거리 관련 라벨"을 골라 실거리 칩으로 교체하는 헬퍼.
///
/// 사용 시나리오:
///   - GET /recommendations 응답 reasons 에는 "도보 1~2분 거리" / "가까운 거리"
///     같은 칩이 백엔드 산정 비율 기준으로 박혀있음.
///   - 비율 기반이라 13km 카드에도 "도보 1~2분 거리"가 붙는 모순 발생.
///   - 이 함수로 거리 관련 reason 만 실거리 칩으로 갈아치움 → 다른 reason
///     (예: "예산 적합", "한식 카테고리")은 그대로 유지.
///
/// 동작:
///   1) chip 이 null 이면(좌표 없음) 거리 관련 reason 제거 후 반환.
///   2) chip 이 있으면 거리 관련 reason 자리에 chip 삽입.
///   3) 거리 관련 reason 이 원래 없었으면 변경 없이 그대로 반환.
///
/// "거리 관련 reason"의 식별 기준 — 백엔드 코드에 박혀있는 두 라벨 + 휴리스틱:
///   - '도보' 로 시작
///   - '가까운 거리' 정확 일치
///   - '차로' 로 시작
///   - '거리 ' 로 시작
List<String> reconcileDistanceReasons({
  required List<String> originalReasons,
  required String? distanceChip,
}) {
  // 원본 reasons 에 거리 관련 라벨이 있는지 표시
  bool isDistanceReason(String r) =>
      r.startsWith('도보') ||
      r == '가까운 거리' ||
      r.startsWith('차로') ||
      r.startsWith('거리 ');

  // ── 1) 거리 라벨이 아닌 reason 들만 골라냄 ───────────────
  // 백엔드가 박은 거리 칩은 일단 모두 제거. 이후 chip 가 있으면 첫 위치에 삽입.
  final filtered = originalReasons.where((r) => !isDistanceReason(r)).toList();

  // ── 2) chip 가 없으면(좌표 없음) 그대로 반환 ─────────────
  // 좌표를 모르는 상태에서 거리 칩을 만들어 줄 수 없음 — 잘못된 라벨보다 없는 게 낫다.
  if (distanceChip == null) {
    return filtered;
  }

  // ── 3) chip 을 reasons 맨 앞에 삽입 ──────────────────────
  // UX 상 거리 정보는 사용자가 가장 먼저 보는 게 의사결정에 도움.
  return [distanceChip, ...filtered];
}
