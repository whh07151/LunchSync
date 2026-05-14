import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/utils/normalizer.dart';
import '../../core/utils/distance_calculator.dart';
import '../../core/debug/debug_toast.dart';
import '../../providers/user_provider.dart';
import '../../services/restaurants_api_service.dart';
import '../../services/sessions_api_service.dart';
import '../../services/external_map_launcher.dart';
import '../../services/geolocation_service.dart';
import '../menu/menu_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-13 식당 상세 화면
//
// 구성 (와이어프레임 기준 — 지도 없음):
//   - 상단 앱바 (뒤로가기)
//   - 식당 기본 정보 (이름 / 카테고리 / 가격대 / 주소)
//   - 길찾기 버튼 → 카카오맵/네이버 선택 바텀시트 (외부 앱)
//   - 메뉴 미리보기 (GET /restaurants/:id/menus 상위 5개)
//   - "메뉴 전체 보기" 버튼 → CU-16 메뉴 스크린 진입
//
// 📌 지도는 이 화면에 없음. 전체 추천 식당 지도는 CU-15에서 토글로 표시.
//
// 진입 경로:
//   홈 / CU-11 AI 추천 리스트 → 이 화면
// ══════════════════════════════════════════════════════════

class RestaurantDetailScreen extends ConsumerStatefulWidget {
  const RestaurantDetailScreen({
    super.key,
    required this.restaurantId,
    this.initialName,
  });

  /// 상세 조회할 식당 ID
  final String restaurantId;

  /// 이전 화면에서 알고 있던 식당 이름 (로딩 중 임시 표시용, optional)
  final String? initialName;

  @override
  ConsumerState<RestaurantDetailScreen> createState() =>
      _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState
    extends ConsumerState<RestaurantDetailScreen> {
  static const _restaurantsApi = RestaurantsApiService();
  static const _sessionsApi = SessionsApiService();
  static const _mapLauncher = ExternalMapLauncher();

  RestaurantDto? _restaurant;
  List<MenuItemDto>? _menuPreview;
  bool _isRestaurantLoading = true;
  bool _isMenuLoading = true;

  // ── 사용자 현재 위치(거리 표시용) ──────────────────────
  // 헤더에 "거리 320m" 한 줄을 띄우기 위해 1회 조회.
  // 권한 거부/타임아웃 시 null → 거리 라인 자동 숨김.
  double? _userLat;
  double? _userLng;

  // ── 활성 점심 세션 ID 캐시 (C1 수정) ─────────────────────
  // CU-16 메뉴 화면으로 넘어갈 때 "어느 세션에 주문을 박을지" 결정해야
  // 한다. 이전엔 메뉴 화면이 시드 UUID 를 하드코딩해 사용했지만, 이제는
  // 상세 화면에서 sessions/today 를 한 번 조회해 활성 세션 ID 를 미리
  // 들고 있다가 MenuScreen 생성자에 넘겨주는 것이 기본이다.
  //
  // null 이면 MenuScreen 이 한 번 더 조회하지만, 호출부에서 미리 넘기면
  // 사용자 체감 지연이 줄어든다.
  String? _activeSessionId;

  // 2026-05-15 사장님 비즈니스 흐름 게이팅:
  //   투표 완료(ORDERED) + 이 식당이 winner 일 때만 메뉴 주문 가능.
  //   투표 전인데 메뉴를 담을 수 있는 회귀 발견 → status + winner 캐싱.
  String? _activeSessionStatus;
  String? _activeWinnerRestaurantId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-13');
      _loadDetail();
      _loadMenus();
      _loadUserLocation();
      _loadActiveSession();
    });
  }

  // ── 활성 점심 세션 1회 조회 ────────────────────────────
  // GET /api/sessions/today 응답 중 DONE 이 아닌 첫 세션을 채택.
  // 결과는 _activeSessionId 에 캐시되어 _goToFullMenu 에서 전달된다.
  // 활성 세션이 없으면 null 그대로 두고, MenuScreen 이 가드로 처리.
  Future<void> _loadActiveSession() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    final sessions = await _sessionsApi.getTodaySessions(accessToken: token);
    if (!mounted) return;

    final active = sessions.where((s) => s.status != 'DONE').toList();
    if (active.isEmpty) return;
    setState(() {
      _activeSessionId = active.first.id;
      _activeSessionStatus = active.first.status;
      _activeWinnerRestaurantId = active.first.winnerRestaurantId;
    });
  }

  // ── 사용자 위치 1회 조회 ──────────────────────────────
  // GPS 1 스냅샷만 얻어 거리 표기에 사용.
  // 권한 거부/타임아웃 시 null 그대로 두어 거리 라인은 그리지 않음.
  Future<void> _loadUserLocation() async {
    final pos = await const GeolocationService().getCurrentPosition();
    if (!mounted || pos == null) return;
    setState(() {
      _userLat = pos.latitude;
      _userLng = pos.longitude;
    });
  }

  // ── 식당 기본 정보 조회 ────────────────────────────────
  // getRestaurantById 단건 조회 — 이전엔 전체 목록 받아 필터링했지만
  // restaurants 테이블이 커지면 비효율이라 백엔드 :id 라우트를 사용.
  Future<void> _loadDetail() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      if (mounted) setState(() => _isRestaurantLoading = false);
      return;
    }

    final found = await _restaurantsApi.getRestaurantById(
      accessToken: token,
      restaurantId: widget.restaurantId,
    );

    if (!mounted) return;
    setState(() {
      _restaurant = found;
      _isRestaurantLoading = false;
    });
  }

  // ── 메뉴 미리보기 조회 (상위 5개만 표시) ───────────────
  Future<void> _loadMenus() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      if (mounted) setState(() => _isMenuLoading = false);
      return;
    }

    final menus = await _restaurantsApi.getMenus(
      accessToken: token,
      restaurantId: widget.restaurantId,
    );

    if (!mounted) return;
    setState(() {
      _menuPreview = menus.take(5).toList();
      _isMenuLoading = false;
    });
  }

  // ── 길찾기 바텀시트 ────────────────────────────────────
  // 카카오맵 / 네이버 지도 선택 시 해당 앱 실행 (없으면 웹)
  Future<void> _showRouteSheet() async {
    final r = _restaurant;
    if (r == null || r.lat == null || r.lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이 식당은 위치 정보가 없어 길찾기를 제공할 수 없어요.')),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('길찾기 앱 선택', style: AppTextStyles.heading3),
                const SizedBox(height: AppSpacing.md),
                _RouteOption(
                  label: '카카오맵으로 길찾기',
                  icon: Icons.map_rounded,
                  color: const Color(0xFFFFE812),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _mapLauncher.openKakaoRoute(
                      destLat: r.lat!,
                      destLng: r.lng!,
                      destName: r.name,
                    );
                  },
                ),
                _RouteOption(
                  label: '네이버 지도로 길찾기',
                  icon: Icons.map_outlined,
                  color: const Color(0xFF03C75A),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _mapLauncher.openNaverRoute(
                      destLat: r.lat!,
                      destLng: r.lng!,
                      destName: r.name,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 메뉴 전체 화면 진입 ────────────────────────────────
  // ⚠️ 반드시 widget.restaurantId 를 함께 넘겨야 한다.
  //   - 미전달 시 MenuScreen 이 어느 식당을 조회해야 할지 모르고
  //     예전엔 시드 식당(11111111-...) 의 mock 메뉴만 보이는 버그가 있었음.
  //
  // [C1 수정] sessionId 도 함께 전달.
  //   - 활성 세션 ID 를 미리 조회해 둔 _activeSessionId 를 그대로 넘기면
  //     메뉴 화면 진입 직후 "주문하기" 버튼이 바로 활성화된다.
  //   - 아직 조회가 끝나지 않았거나 활성 세션이 없으면 null 로 두고,
  //     MenuScreen 이 자체 가드로 처리(시드 UUID 사용 금지).
  void _goToFullMenu() {
    // 2026-05-15 사장님 비즈니스 흐름 게이팅:
    //   투표가 끝난 후(ORDERED) + 이 식당이 선택된 winner 일 때만 메뉴 주문 가능.
    //   투표 전인데 메뉴 담을 수 있는 회귀 차단.
    //
    // 예외: 활성 세션이 없는 케이스(개별 식당 탐색)에는 게이팅 안 함 — 메뉴 미리보기는 자유.
    if (_activeSessionId != null) {
      // 활성 세션 있음 — 게이팅 적용
      if (_activeSessionStatus != 'ORDERED') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '투표가 끝난 후에 메뉴를 주문할 수 있어요. 친구들과 함께 결정해봐요',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      if (_activeWinnerRestaurantId != null &&
          _activeWinnerRestaurantId!.isNotEmpty &&
          _activeWinnerRestaurantId != widget.restaurantId) {
        // 다른 식당이 winner 로 결정됨 — 이 식당 주문 차단
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '이번 점심 세션은 다른 식당이 선택됐어요. 그 식당으로 이동해봐요',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
    }
    // 통과 — MenuScreen 으로 진입
    final name = _restaurant?.name ?? widget.initialName ?? '식당';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MenuScreen(
          restaurantId: widget.restaurantId,
          restaurantName: name,
          sessionId: _activeSessionId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(
        showBack: true,
        title: _restaurant?.name ?? widget.initialName ?? '식당',
      ),
      body: _isRestaurantLoading
          ? const Center(child: CircularProgressIndicator())
          : _restaurant == null
              ? _buildNotFound()
              : _buildContent(_restaurant!),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.iconInactive),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '식당 정보를 찾을 수 없어요',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(RestaurantDto r) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 식당 헤더 ───────────────────────────────────
          _buildHeader(r),

          // ── 길찾기 버튼 (지도는 없음, 외부 앱으로 길찾기만) ──
          if (r.lat != null && r.lng != null) ...[
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
              ),
              child: AppPrimaryButton(
                label: '길찾기',
                onPressed: _showRouteSheet,
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.lg),

          // ── 메뉴 미리보기 ───────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('메뉴', style: AppTextStyles.heading3),
                TextButton(
                  onPressed: _goToFullMenu,
                  child: const Text('전체 보기 →'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildMenuPreview(),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildHeader(RestaurantDto r) {
    final primary = Theme.of(context).colorScheme.primary;
    // 가격대 표시는 공통 헬퍼로 통일.
    // 백엔드 price_range 값이 시드(원)·크롤(1000원 단위)·Gemini(1~5 척도)로
    // 혼재되어 있어 단순 "${n}원대" 출력 시 "2원대" 같은 버그가 발생했음.
    // formatRestaurantPriceRange가 값의 크기로 의미를 추정해 한국식 라벨로 변환.
    final priceLabel = formatRestaurantPriceRange(r.priceRange);

    // 거리 라벨 — 사용자 위치/식당 좌표 둘 다 있을 때만 표기.
    // null이면 거리 줄을 그리지 않음(디자인 유지 원칙).
    final distance = distanceLabel(
      userLat: _userLat,
      userLng: _userLng,
      targetLat: r.lat,
      targetLng: r.lng,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      color: primary.withAlpha(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 식당 대표 이미지 (와이드 배너) ───────────────
          // [사장님 피드백 대응 — 2026-05-13]
          //   기존엔 식당 상세에 사진이 한 장도 없어서 사장/손님 모두 어느
          //   식당인지 시각적으로 가늠하기 어려웠다. FoodImage 공용 위젯을
          //   사용해 화면 폭 100% × 160 높이 배너로 표시한다.
          //   imageUrl 이 없는 식당(대부분)은 카테고리 이모지 fallback 으로
          //   디자인 일관성을 유지(색상 토큰 그대로).
          FoodImage(
            imageUrl: r.imageUrl,
            categoryLabel: r.category,
            // 화면 폭에 맞추기 위해 무한대를 전달 — 부모 Container 가 폭을
            // 제한해 주므로 실제 렌더링 시엔 화면 폭(- 패딩) 으로 확장됨.
            width: double.infinity,
            height: 160,
            emojiSize: 72,
            borderRadius: BorderRadius.circular(AppRadius.card),
            semanticLabel: '${r.name} 식당 사진',
          ),
          const SizedBox(height: AppSpacing.md),

          Text(r.name, style: AppTextStyles.heading1),
          const SizedBox(height: 4),
          Row(
            children: [
              if (r.category != null) ...[
                Icon(Icons.restaurant_rounded,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(r.category!, style: AppTextStyles.bodySmall),
                const SizedBox(width: AppSpacing.sm),
              ],
              Icon(Icons.payments_outlined,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(priceLabel, style: AppTextStyles.bodySmall),
              // ── 평점 칩 (사장님 피드백 — 2026-05-14) ─────────
              //   "네이버나 구글로 식당 평점 조사한 거 맞아?" 대응.
              //   네이버 plac reviewScore 수집값을 ⭐ 4.2 형식으로 표시.
              //   - rating == null 이면(평점 미수집 식당) 칩 자체를 생략.
              //   - 색상 토큰 변경 없음: amber 600 은 표준 별점 색이라 안전.
              //   - toStringAsFixed(1) 로 항상 소수점 1자리 통일.
              if (r.rating != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.star_rounded,
                    size: 14, color: Colors.amber.shade600),
                const SizedBox(width: 2),
                Text(
                  r.rating!.toStringAsFixed(1),
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ],
          ),
          if (r.address != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.place_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    r.address!,
                    style: AppTextStyles.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // ── 거리(distance) ───────────────────────────
          // 위치 권한 + 식당 좌표가 모두 있을 때만 표기.
          // 디자인 토큰 변경 없이 directions_walk 아이콘 + bodySmall.
          if (distance != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.directions_walk_rounded,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(distance, style: AppTextStyles.bodySmall),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuPreview() {
    if (_isMenuLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final menus = _menuPreview ?? const <MenuItemDto>[];
    if (menus.isEmpty) {
      // 빈 상태 — 메뉴는 사장님이 등록하는 영역이므로 "곧 올라올 예정"이라는 기대치 설정
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
          vertical: AppSpacing.md,
        ),
        child: Text(
          '메뉴는 사장님이 곧 올려주실 거예요',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
      ),
      child: Column(
        children: menus.map(_buildMenuRow).toList(),
      ),
    );
  }

  Widget _buildMenuRow(MenuItemDto m) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 메뉴 썸네일 (사장님 피드백 — 2026-05-13) ─────
          //   미리보기 5개 행 좌측에 56px 정사각형 썸네일을 추가.
          //   imageUrl 없으면 카테고리 이모지 fallback (FoodImage 내장 처리).
          //   목록형이라 메뉴 카드(88px) 보다는 살짝 작게.
          FoodImage(
            imageUrl: m.imageUrl,
            categoryLabel: m.category,
            width: 56,
            height: 56,
            emojiSize: 28,
            semanticLabel: '${m.name} 사진',
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (m.description != null && m.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      m.description!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${_formatComma(m.price)}원',
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _formatComma(int value) {
    final s = value.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}

// ── 바텀시트용 길찾기 앱 선택 항목 ──────────────────────
class _RouteOption extends StatelessWidget {
  const _RouteOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withAlpha(50),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(label, style: AppTextStyles.bodyMedium),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.iconInactive),
          ],
        ),
      ),
    );
  }
}
