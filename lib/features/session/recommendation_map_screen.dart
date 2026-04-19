import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/theme/theme.dart';
import '../../core/debug/debug_toast.dart';
import '../../core/widgets/kakao_map/kakao_map_widget.dart';
import '../../core/config/app_config.dart';
import '../../services/geolocation_service.dart';
import '../../services/recommendations_api_service.dart';
import '../restaurant/restaurant_detail_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-15 추천 식당 지도 화면 (리스트/지도 토글의 "지도 모드")
//
// 구성:
//   - 카카오맵 (전체 화면 크기)
//   - 추천 식당 핀 + 내 위치 파란 원
//   - 상단에 "리스트 보기" 토글 버튼 (뒤로 가기와 동일 동작)
//   - 핀 클릭 시 말풍선, 하단 mini 카드에 식당 요약 (추후 확장)
//
// 진입 경로:
//   CU-11 AI 추천 리스트 → "지도 보기" 토글 버튼 → 이 화면
//
// 단순화 결정:
//   와이어프레임의 CU-15는 "리스트/지도 토글" 하나의 화면이지만,
//   Flutter 구현 편의상 별도 화면으로 분리. 토글 동작은 Navigator pop/push로 처리.
// ══════════════════════════════════════════════════════════

class RecommendationMapScreen extends ConsumerStatefulWidget {
  const RecommendationMapScreen({
    super.key,
    required this.recommendations,
    required this.sessionName,
  });

  final List<RecommendationDto> recommendations;
  final String sessionName;

  @override
  ConsumerState<RecommendationMapScreen> createState() =>
      _RecommendationMapScreenState();
}

class _RecommendationMapScreenState
    extends ConsumerState<RecommendationMapScreen> {
  // ── 내 위치 상태 ──────────────────────────────────────
  // 스트림에서 새 좌표가 올 때마다 갱신되어 지도 파란 원이 따라 움직임.
  KakaoMapPin? _myLocationPin;

  // ── 실시간 위치 스트림 구독 핸들 ───────────────────────
  // 화면 dispose 시 반드시 cancel() — 누락 시 백그라운드에서 GPS가 계속 돌아
  // 배터리/권한 UI가 이상해질 수 있음.
  StreamSubscription<Position>? _positionSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-15');
      // 1) 즉시 한 번 스냅샷 조회 — 지도 진입 직후 바로 파란 원을 띄우기 위함
      //    (스트림 첫 이벤트까지 수 초 걸릴 수 있어 UX 공백 방지)
      _loadInitialLocation();
      // 2) 이후 이동 시마다 실시간 갱신
      _subscribeLocationUpdates();
    });
  }

  @override
  void dispose() {
    // 스트림 구독 해제 — Flutter 프레임워크가 위젯을 제거할 때 호출됨.
    _positionSub?.cancel();
    super.dispose();
  }

  // ── 초기 1회 스냅샷 ─────────────────────────────────────
  // 스트림은 이동 감지(distanceFilter)에 의존하므로, 책상 위처럼 움직임이 없으면
  // 첫 이벤트가 한참 뒤에야 오는 경우가 있음. 진입 직후 한 번 직접 조회해 즉시 표시.
  Future<void> _loadInitialLocation() async {
    final pos = await const GeolocationService().getCurrentPosition();
    if (!mounted || pos == null) return;
    _applyPosition(pos);
  }

  // ── 실시간 위치 스트림 구독 ────────────────────────────
  // GeolocationService가 권한/서비스 상태를 내부에서 검증하고, 실패 시 빈 스트림을
  // 돌려주므로 여기서는 onData만 처리하면 됨.
  void _subscribeLocationUpdates() {
    _positionSub = const GeolocationService()
        .positionStream(distanceFilterMeters: 10)
        .listen(
          (pos) {
            if (!mounted) return;
            _applyPosition(pos);
          },
          onError: (_) {
            // 스트림 에러는 서비스 레이어에서 이미 로깅됨 — UI는 무시
          },
        );
  }

  // ── 좌표 → 내 위치 핀 반영 공통 처리 ──────────────────
  void _applyPosition(Position pos) {
    setState(() {
      _myLocationPin = KakaoMapPin(
        name: '내 위치',
        lat: pos.latitude,
        lng: pos.longitude,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // 추천 결과에서 좌표 있는 것만 지도 핀으로
    final pins = widget.recommendations
        .where((r) => r.lat != null && r.lng != null)
        .map((r) => KakaoMapPin(name: r.name, lat: r.lat!, lng: r.lng!))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── 전체 화면 지도 ──────────────────────────────
          Positioned.fill(
            child: KakaoMapWidget(
              pins: pins,
              myLocation: _myLocationPin,
              jsAppKey: AppConfig.kakaoJavaScriptAppKey,
              height: double.infinity,
              zoomLevel: 4,
            ),
          ),

          // ── 상단 바 (뒤로 + 세션 이름 + "리스트 보기" 토글) ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    // 뒤로 가기 = 리스트 모드로 복귀
                    Material(
                      color: AppColors.surface,
                      shape: const CircleBorder(),
                      elevation: 2,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(30),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          widget.sessionName,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 하단 추천 식당 미니 카드 리스트 (가로 스크롤) ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  itemCount: widget.recommendations.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) =>
                      _buildMiniCard(widget.recommendations[i], i + 1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 하단 미니 카드 하나 — 탭 시 식당 상세로 이동
  Widget _buildMiniCard(RecommendationDto rec, int rank) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RestaurantDetailScreen(
              restaurantId: rec.restaurantId,
              initialName: rec.name,
            ),
          ),
        );
      },
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(30),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rank <= 3 ? primary : AppColors.backgroundGrey,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank',
                    style: AppTextStyles.caption.copyWith(
                      color: rank <= 3 ? Colors.white : AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    rec.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              rec.category ?? '',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            Text(
              '점수 ${rec.score}',
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
