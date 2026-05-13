// ══════════════════════════════════════════════════════════
// 파일 역할: AI 추천 식당을 지도에 표시하는 범용 진입 화면
//
// 진입 경로:
//   - 홈/추천 화면의 지도 아이콘 버튼 → 이 화면 push
//   - sessionTitle 이 있으면 AppBar 에 세션 이름 부제 표기
//   - sessionTitle 이 없으면 단순히 "지도로 보기" 만 표기
//
// 기존 RecommendationMapScreen(session 폴더)과의 관계:
//   - 그 화면은 RecommendationDto 기반 + Stack 풀스크린 + 좌측 상단 뒤로가기 버튼.
//   - 본 화면은 사장님 피드백(지도 아이콘 동작 안 함)에 대응하는 신규 진입점으로,
//     일반 Restaurant + 좌표 페어(`RestaurantMapPoint`)를 받아 동작.
//     홈 카드, 즐겨찾기, 검색 결과 등 다양한 진입점에서 재사용 가능.
//
// 화면 구성:
//   1) AppBar — 뒤로가기 + "지도로 보기" 타이틀 + 세션 부제(optional)
//   2) Body 상단(약 70%) — KakaoMapWidget (식당 핀 + 내 위치 파란 원)
//   3) Body 하단(약 30%) — 식당 미니 카드 가로 스크롤
//   4) 빈 상태 — 좌표가 있는 식당이 0개면 안내 + 뒤로가기 유도
//
// 위치 권한:
//   - GeolocationService 가 내부에서 권한/서비스 상태를 검증.
//   - 권한 거부/GPS 꺼짐 시 _myLocationPin 이 null 로 유지 → 지도는 식당 핀만 표시.
//   - 권한 거부 시에는 한 번만 토스트로 안내 (다른 화면 패턴과 동일).
//
// ⚠️ 색상/타이포 변경 없음. 디자인 토큰(AppColors, AppTextStyles, AppSpacing) 그대로.
// ══════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/kakao_map/kakao_map_widget.dart';
import '../../models/restaurant.dart';
import '../../services/geolocation_service.dart';

/// 지도에 표시할 단일 식당 + 좌표 페어.
///
/// Restaurant 모델 자체에는 lat/lng 필드가 없어(현재 백엔드 응답 의존),
/// 호출자가 좌표를 별도로 채워 전달하도록 한 의도적 분리.
///
/// 사용 예 (홈 화면):
///   final points = recommendations
///     .where((r) => r.lat != null && r.lng != null)
///     .map((r) => RestaurantMapPoint(
///           restaurant: convertToRestaurant(r),
///           lat: r.lat!,
///           lng: r.lng!,
///         ))
///     .toList();
///   Navigator.of(context).push(MaterialPageRoute(
///     builder: (_) => RecommendationMapScreen(
///       points: points,
///       sessionTitle: '오늘 점심 함께!',
///     ),
///   ));
class RestaurantMapPoint {
  const RestaurantMapPoint({
    required this.restaurant,
    required this.lat,
    required this.lng,
  });

  /// 카드/리스트 표시용 식당 모델
  final Restaurant restaurant;

  /// 카카오맵 핀 위도
  final double lat;

  /// 카카오맵 핀 경도
  final double lng;
}

/// AI 추천 식당을 지도에 표시하는 범용 진입 화면.
class RecommendationMapScreen extends StatefulWidget {
  const RecommendationMapScreen({
    super.key,
    required this.points,
    this.sessionTitle,
  });

  /// 지도에 표시할 식당 + 좌표 리스트
  final List<RestaurantMapPoint> points;

  /// 세션 이름 (있으면 AppBar 부제로 표기, 없으면 생략)
  final String? sessionTitle;

  @override
  State<RecommendationMapScreen> createState() =>
      _RecommendationMapScreenState();
}

class _RecommendationMapScreenState extends State<RecommendationMapScreen> {
  // ── 내 위치 핀 상태 ──────────────────────────────────────
  // 스트림에서 새 좌표가 올 때마다 갱신. 초기엔 null → 파란 원 미표시.
  KakaoMapPin? _myLocationPin;

  // ── 위치 스트림 구독 핸들 ────────────────────────────────
  // dispose 시 반드시 cancel — 누락 시 백그라운드 GPS가 계속 도는 버그 가능.
  StreamSubscription<Position>? _positionSub;

  // ── 권한 거부 토스트 1회 가드 ────────────────────────────
  // 같은 화면에서 토스트가 여러 번 떠 사용자를 괴롭히지 않도록 플래그.
  bool _permissionToastShown = false;

  @override
  void initState() {
    super.initState();
    // 첫 프레임 이후에 비동기 위치 조회 시작 — initState 안에서 직접 await 금지.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialLocation();
      _subscribeLocationUpdates();
    });
  }

  @override
  void dispose() {
    // 스트림 구독 정리 — 화면이 사라질 때 GPS 콜백이 계속 살아있으면 안 됨.
    _positionSub?.cancel();
    super.dispose();
  }

  // ── 진입 직후 1회 스냅샷 조회 ──────────────────────────
  // 스트림은 distanceFilter에 의해 사용자가 움직여야만 첫 이벤트가 옴.
  // 책상에서 가만히 있는 경우 첫 표시까지 공백이 생겨 즉시 조회로 메움.
  Future<void> _loadInitialLocation() async {
    final pos = await const GeolocationService().getCurrentPosition();
    if (!mounted) return;
    if (pos == null) {
      // 권한 거부/GPS 꺼짐 등 — 안내 토스트 1회.
      _showPermissionToastOnce();
      return;
    }
    _applyPosition(pos);
  }

  // ── 위치 실시간 스트림 구독 ────────────────────────────
  // GeolocationService 가 권한 검증을 내부에서 처리하므로 onData만 신경 쓰면 됨.
  void _subscribeLocationUpdates() {
    _positionSub = const GeolocationService()
        .positionStream(distanceFilterMeters: 10)
        .listen(
          (pos) {
            if (!mounted) return;
            _applyPosition(pos);
          },
          onError: (_) {
            // 스트림 에러는 서비스 레이어에서 이미 로깅 — UI는 추가 처리 없음.
          },
        );
  }

  // ── 좌표 → 내 위치 핀 공통 반영 ───────────────────────
  // setState 로 지도 위젯에 즉시 반영. 동일 좌표가 반복 들어와도 안전 (단순 교체).
  void _applyPosition(Position pos) {
    setState(() {
      _myLocationPin = KakaoMapPin(
        name: '내 위치',
        lat: pos.latitude,
        lng: pos.longitude,
      );
    });
  }

  // ── 권한 거부 안내 토스트 (1회만) ───────────────────────
  // 다른 화면 패턴과 동일하게 SnackBar 사용. 디자인 토큰 변경 없음.
  void _showPermissionToastOnce() {
    if (_permissionToastShown) return;
    _permissionToastShown = true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('내 위치 권한이 없어 식당 위치만 표시합니다'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final pins = points
        .map((p) => KakaoMapPin(
              name: p.restaurant.name,
              lat: p.lat,
              lng: p.lng,
            ))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '지도로 보기',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            // 세션 부제(optional) — 있으면 작게 회색으로 표기.
            if (widget.sessionTitle != null &&
                widget.sessionTitle!.isNotEmpty)
              Text(
                widget.sessionTitle!,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
      body: pins.isEmpty
          // ── 빈 상태 (좌표 있는 식당 0개) ───────────────
          // 단순 카피 + 뒤로가기 유도. 디자인 토큰 그대로.
          ? _buildEmptyState()
          : _buildMapBody(pins, points),
    );
  }

  // 좌표 있는 식당이 0개일 때 표시. 사장님 피드백 기준 카피 톤 유지.
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map_outlined,
              size: 56,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '지도에 표시할 식당이 없어요',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '좌표 정보가 없는 식당은 지도에 표시되지 않아요.\n뒤로 가서 다른 추천을 확인해 보세요.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
              label: const Text('리스트로 돌아가기'),
            ),
          ],
        ),
      ),
    );
  }

  // 지도 + 하단 미니 카드 본문.
  // 비율: 지도 70% / 미니 카드 30% — 작은 폰에서도 두 영역 모두 식별 가능하도록.
  Widget _buildMapBody(
      List<KakaoMapPin> pins, List<RestaurantMapPoint> points) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 화면 높이의 70%를 지도에 — 최소 240px 보장 (작은 폰 폴드 모드 대응).
        final mapHeight =
            (constraints.maxHeight * 0.7).clamp(240.0, constraints.maxHeight);
        return Column(
          children: [
            // ── 상단 지도 영역 ───────────────────────────
            SizedBox(
              height: mapHeight,
              child: KakaoMapWidget(
                pins: pins,
                myLocation: _myLocationPin,
                jsAppKey: AppConfig.kakaoJavaScriptAppKey,
                height: mapHeight,
                // 줌 레벨 4 — 식당이 1~2km 반경에 흩어진 케이스 평균에 적합.
                zoomLevel: 4,
              ),
            ),

            // ── 하단 미니 카드 가로 스크롤 ────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.sm,
                ),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  itemCount: points.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => _buildMiniCard(points[i], i + 1),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // 하단 미니 카드 한 장 — 이름/카테고리/가격대 요약.
  // 탭 시: 카메라가 해당 핀으로 이동되면 좋겠지만, 현재 KakaoMapWidget 이
  // 외부 카메라 제어 API를 제공하지 않아 미구현(별도 티켓으로 분리 권장).
  // 대신 탭 시 추후 식당 상세 라우팅을 붙일 수 있게 GestureDetector 만 준비.
  Widget _buildMiniCard(RestaurantMapPoint point, int rank) {
    final primary = Theme.of(context).colorScheme.primary;
    final r = point.restaurant;
    return GestureDetector(
      // onTap 비워둠 — 카메라 이동 API 부재. 추후 라우팅 확장 포인트.
      onTap: () {},
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 순위 + 이름 ─────────────────────────────
            Row(
              children: [
                // 순위 배지(1~3등 강조색, 그 이하 회색) — 다른 카드 컴포넌트와 톤 통일.
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        rank <= 3 ? primary : AppColors.backgroundGrey,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank',
                    style: AppTextStyles.caption.copyWith(
                      color: rank <= 3
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // ── 카테고리 + 가격대 한 줄 ──────────────────
            Text(
              '${r.category.label} · ${r.priceDisplay}',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            // 평점이 있으면 짧게 노출(가독성 우선 — 별 아이콘은 생략).
            if (r.rating != null)
              Text(
                '평점 ${r.rating!.toStringAsFixed(1)}',
                style: AppTextStyles.caption.copyWith(
                  color: primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
