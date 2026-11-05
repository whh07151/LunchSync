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
import '../../services/favorites_api_service.dart';
import '../../services/reviews_api_service.dart';
import 'restaurant_reviews_screen.dart';
import 'menu_price_estimator.dart';

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

  // 2026-05-15 즐겨찾기 (배민 패턴):
  //   진입 시 GET /favorites 로 현재 식당이 즐겨찾기인지 확인 → 하트 아이콘 상태 결정.
  //   탭 시 add / remove 토글.
  bool _isFavorite = false;
  bool _favoriteBusy = false; // 중복 클릭 방지
  static const _favoritesApi = FavoritesApiService();

  // 2026-05-15 별점/리뷰 (배민 패턴):
  //   GET /restaurants/:id/reviews 로 평균 평점 + 리뷰 개수 1회 조회.
  //   헤더 칩에 ⭐ 4.3 (12) 형식으로 표시 + 칩 탭 → RestaurantReviewsScreen.
  //   네이버 rating (RestaurantDto.rating) 과는 다른 출처(주문 후 손님 직접 입력).
  RestaurantReviewsResult? _reviewSummary;
  static const _reviewsApi = ReviewsApiService();

  // 2026-05-31 단골 랭킹 (WOW#5):
  //   GET /restaurants/:id/loyalty?userId=:userId 로 해당 손님의 이 식당
  //   누적 픽업 횟수 + 등급 1회 조회. 헤더에 영구 뱃지로 표시
  //   ("단골 #4" / "VIP 단골" 등). null = 미조회/실패 → 뱃지 미표시.
  LoyaltyDto? _loyalty;
  RestaurantSeatSummaryDto? _seatSummary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-13');
      _loadDetail();
      _loadMenus();
      _loadUserLocation();
      _loadActiveSession();
      _loadFavoriteStatus();
      _loadReviewSummary();
      _loadLoyalty();
      _loadSeatSummary();
    });
  }

  Future<void> _loadSeatSummary() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null || token.isEmpty) return;
    final result = await _restaurantsApi.getSeatSummary(
      accessToken: token,
      restaurantId: widget.restaurantId,
    );
    if (!mounted) return;
    setState(() => _seatSummary = result);
  }

  // ── 단골 등급 1회 조회 (2026-05-31 WOW#5) ────────────────
  // 실패해도 화면 흐름 영향 없음. userId 없으면 비로그인 — 뱃지 미표시.
  Future<void> _loadLoyalty() async {
    final user = ref.read(userProvider);
    final token = user.accessToken;
    if (token == null || token.isEmpty) return;
    final result = await _restaurantsApi.getLoyalty(
      accessToken: token,
      restaurantId: widget.restaurantId,
    );
    if (!mounted) return;
    setState(() => _loyalty = result);
  }

  // ── 별점 요약 1회 조회 (2026-05-15 배민 패턴) ──────────
  // 실패해도 화면 흐름 영향 없음 (ReviewsApiService 가 empty 반환).
  Future<void> _loadReviewSummary() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;
    final result = await _reviewsApi.getReviewsByRestaurant(
      accessToken: token,
      restaurantId: widget.restaurantId,
    );
    if (!mounted) return;
    setState(() => _reviewSummary = result);
  }

  // ── 리뷰 리스트 화면 진입 (평점 칩 탭 시) ────────────────
  void _openReviewsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RestaurantReviewsScreen(
          restaurantId: widget.restaurantId,
          restaurantName: _restaurant?.name ?? widget.initialName,
        ),
      ),
    );
  }

  // 2026-05-15 즐겨찾기 상태 진입 시 1회 조회
  Future<void> _loadFavoriteStatus() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;
    final list = await _favoritesApi.list(accessToken: token);
    if (!mounted) return;
    setState(() {
      _isFavorite = list.any((f) => f.id == widget.restaurantId);
    });
  }

  // 하트 탭 → 토글 (add/remove)
  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인이 필요해요')));
      return;
    }

    setState(() => _favoriteBusy = true);
    final prev = _isFavorite;
    // Optimistic UI — 즉시 토글 후 실패 시 롤백
    setState(() => _isFavorite = !prev);

    final result = prev
        ? await _favoritesApi.remove(
            accessToken: token,
            restaurantId: widget.restaurantId,
          )
        : await _favoritesApi.add(
            accessToken: token,
            restaurantId: widget.restaurantId,
          );

    if (!mounted) return;
    setState(() => _favoriteBusy = false);

    if (result == null) {
      // 실패 → 롤백 + 안내
      setState(() => _isFavorite = prev);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            prev
                ? '즐겨찾기 해제에 실패했어요. 잠시 후 다시 시도해봐요'
                : '즐겨찾기 추가에 실패했어요 (한도 100개 초과 가능성)',
          ),
        ),
      );
      return;
    }

    // 성공 토스트
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(prev ? '즐겨찾기에서 뺐어요' : '즐겨찾기에 추가했어요'),
        duration: const Duration(seconds: 2),
      ),
    );
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
    final matched = active.where(
      (s) =>
          s.status == 'ORDERED' && s.winnerRestaurantId == widget.restaurantId,
    );
    final chosen = matched.isNotEmpty ? matched.first : active.first;
    setState(() {
      _activeSessionId = chosen.id;
      _activeSessionStatus = chosen.status;
      _activeWinnerRestaurantId = chosen.winnerRestaurantId;
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
  // 도보 예상 거리·소요시간·점심시간 여유도 요약 + 주소 복사 + 카카오맵/네이버 지도 연결
  Future<void> _showRouteSheet() async {
    final r = _restaurant;
    if (r == null || r.lat == null || r.lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이 식당은 위치 정보가 없어 길찾기를 제공할 수 없어요.')),
      );
      return;
    }

    // 사용자 위치(또는 기본 한성대입구 기준점 37.5885, 127.0062) 대비 도보 거리/소요시간 계산
    final baseLat = _userLat ?? 37.5885;
    final baseLng = _userLng ?? 127.0062;
    final distMeters = haversineMeters(
      lat1: baseLat,
      lng1: baseLng,
      lat2: r.lat!,
      lng2: r.lng!,
    ).round();
    final walkMeters = (distMeters * 1.25).round().clamp(80, 15000);
    final walkMinutes = (walkMeters / 67).ceil().clamp(2, 120);
    final roundTripMinutes = walkMinutes * 2;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final primary = Theme.of(ctx).colorScheme.primary;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${r.name} 길찾기 안내',
                  style: AppTextStyles.heading3,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primary.withAlpha(15),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: primary.withAlpha(60)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.directions_walk_rounded,
                            size: 18,
                            color: primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '예상 도보 약 ${walkMeters}m · 편도 약 $walkMinutes분 (왕복 약 $roundTripMinutes분)',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (r.address != null && r.address!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '주소: ${r.address}',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _RouteOption(
                  label: '카카오맵 도보 길찾기 열기',
                  icon: Icons.map_rounded,
                  color: const Color(0xFFFFE812),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _mapLauncher.openKakaoRoute(
                      destLat: r.lat!,
                      destLng: r.lng!,
                      destName: r.name,
                      mode: 'FOOT',
                    );
                  },
                ),
                _RouteOption(
                  label: '네이버 지도 길찾기 열기',
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
  // 현재 식당으로 확정된 ORDERED 세션이 있을 때만 그 세션을 재사용하고,
  // 그렇지 않으면 null 을 전달해 MenuScreen 에서 동일 식당 세션을 조회하거나 새로 생성하게 한다.
  void _goToFullMenu() {
    final canReuseActiveSession =
        _activeSessionId != null &&
        _activeSessionStatus == 'ORDERED' &&
        _activeWinnerRestaurantId == widget.restaurantId;
    final name = _restaurant?.name ?? widget.initialName ?? '식당';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MenuScreen(
          restaurantId: widget.restaurantId,
          restaurantName: name,
          sessionId: canReuseActiveSession ? _activeSessionId : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(
        showBack: true,
        title: _restaurant?.name ?? widget.initialName ?? '식당',
        actions: [
          // 2026-05-15 즐겨찾기 토글 (배민 패턴) — AppBar 우측 하트 아이콘.
          // 진입 시 _loadFavoriteStatus 가 GET /favorites 조회.
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: primary,
            ),
            tooltip: _isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가',
            onPressed: _favoriteBusy ? null : _toggleFavorite,
          ),
        ],
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
          const Icon(
            Icons.error_outline,
            size: 48,
            color: AppColors.iconInactive,
          ),
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

          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.md,
              AppSpacing.screenHorizontal,
              0,
            ),
            child: RestaurantDataNotice(),
          ),

          // ── 길찾기 버튼 (지도는 없음, 외부 앱으로 길찾기만) ──
          if (r.lat != null && r.lng != null) ...[
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
              ),
              child: AppPrimaryButton(label: '길찾기', onPressed: _showRouteSheet),
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

    // 2026-05-31 WOW#1: 사장님 "오늘의 한 줄" — 헤더 최상단 노란 띠.
    //   추천 카드 노란 띠와 같은 #FFF3CD 톤이지만 상세는 가로폭이 넉넉하므로
    //   3줄까지 허용하고 폰트 크기를 키워 가독성 강화.
    final todaysNote = r.todaysNote;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      color: primary.withAlpha(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 사장님 한 줄 (있을 때만) ────────────────────
          if (todaysNote != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm + 2,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(AppRadius.small),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '👨‍🍳',
                    style: TextStyle(fontSize: 18, height: 1.2),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          height: 1.4,
                        ),
                        children: [
                          TextSpan(
                            text: '사장님 한마디  ',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          // 따옴표로 인용구 느낌 강조.
                          TextSpan(text: '"$todaysNote"'),
                        ],
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

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
                Icon(
                  Icons.restaurant_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(r.category!, style: AppTextStyles.bodySmall),
                const SizedBox(width: AppSpacing.sm),
              ],
              Icon(
                Icons.payments_outlined,
                size: 14,
                color: AppColors.textSecondary,
              ),
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
                Icon(
                  Icons.star_rounded,
                  size: 14,
                  color: Colors.amber.shade600,
                ),
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
                Icon(
                  Icons.place_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
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
                Icon(
                  Icons.directions_walk_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(distance, style: AppTextStyles.bodySmall),
              ],
            ),
          ],

          // ── 손님 리뷰 평점 (2026-05-15 배민 패턴) ──────────
          // 네이버 rating(상단 별 칩)과 분리된 별도 표시 — 손님 직접 작성.
          // _reviewSummary == null  → 로딩 중(생략)
          // count == 0              → "리뷰 0개 — 첫 후기를 남겨봐요"
          // count > 0               → "⭐ 4.3 (12) 리뷰 보기 →"
          // 한 줄 전체가 InkWell 로 RestaurantReviewsScreen 진입.
          if (_reviewSummary != null) ...[
            const SizedBox(height: 6),
            _buildCustomerReviewLine(),
          ],

          // ── 단골 뱃지 (WOW#5, 2026-05-31) ─────────────────
          //   - visitCount == 0 (한 번도 안 옴) → 뱃지 미표시
          //   - 1~2회 NORMAL: 흰배경 + 회색 외곽선, "단골 #N"
          //   - 3~4회 REGULAR: 주황 배경, "단골 #N"
          //   - 5회+ VIP: 금색 그라데이션, "VIP 단골 (N회)"
          if (_loyalty != null && _loyalty!.visitCount > 0) ...[
            const SizedBox(height: 8),
            _buildLoyaltyBadge(_loyalty!),
          ],
          if (_seatSummary != null && _seatSummary!.totalSeats > 0) ...[
            const SizedBox(height: 8),
            _buildSeatAvailabilityBanner(_seatSummary!),
          ],
        ],
      ),
    );
  }

  Widget _buildSeatAvailabilityBanner(RestaurantSeatSummaryDto summary) {
    final hasEmpty = summary.emptySeats > 0;
    final color = hasEmpty ? AppColors.success : AppColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        children: [
          Icon(
            hasEmpty ? Icons.event_seat_rounded : Icons.access_time_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              hasEmpty
                  ? 'POS 조회 기준: 빈 테이블 ${summary.emptySeats}개 / 총 ${summary.totalSeats}개 · 좌석 배정은 매장 확인 필요'
                  : 'POS 조회 기준: 빈 테이블 없음 (${summary.totalSeats}개 사용 중 · 매장 확인 필요)',
              style: AppTextStyles.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _openCustomerReservationDialog,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            child: Text(hasEmpty ? '사전예약 신청' : '웨이팅 신청'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCustomerReservationDialog() async {
    final user = ref.read(userProvider);
    final token = user.accessToken;
    if (token == null || token.isEmpty) return;

    final nameCtrl = TextEditingController(text: user.name ?? '점심싱크 고객');
    final sizeCtrl = TextEditingController(text: '4');
    final noteCtrl = TextEditingController(text: '12:10 방문 예정');
    String kind = (_seatSummary != null && _seatSummary!.emptySeats > 0)
        ? 'RESERVATION'
        : 'WAITING';

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('방문 예약 · 웨이팅 신청'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'RESERVATION', label: Text('사전 예약')),
                    ButtonSegment(value: 'WAITING', label: Text('현장 웨이팅')),
                  ],
                  selected: {kind},
                  onSelectionChanged: (s) => setState(() => kind = s.first),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '예약자명 / 팀명',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: sizeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '방문 인원 수 (명)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: '요청 메모 (도착 예정 시각 등)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('신청하기'),
            ),
          ],
        ),
      ),
    );

    if (submitted != true || !mounted) return;
    final ok = await _restaurantsApi.createReservation(
      accessToken: token,
      restaurantId: widget.restaurantId,
      kind: kind,
      customerName: nameCtrl.text.trim().isEmpty
          ? '점심싱크 고객'
          : nameCtrl.text.trim(),
      partySize: (int.tryParse(sizeCtrl.text.trim()) ?? 2).clamp(1, 30),
      note: noteCtrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '사장님 앱으로 예약·웨이팅 신청이 접수됐어요!' : '예약 신청에 실패했어요. 잠시 후 다시 시도해 주세요.',
        ),
      ),
    );
  }

  // ── 단골 뱃지 위젯 (WOW#5) ──────────────────────────────
  // 등급별 색 토큰만 변경 — AppRadius/AppSpacing/Text 토큰 그대로 사용.
  // NORMAL(흰), REGULAR(주황), VIP(금색). 한 줄 칩 형태.
  Widget _buildLoyaltyBadge(LoyaltyDto loyalty) {
    final rank = loyalty.rank;
    final n = loyalty.visitCount;

    // 등급별 배경/외곽선/글자 색 (디자인 토큰 + 표준 색).
    Color bg;
    Color border;
    Color textColor;
    IconData icon;
    String label;

    switch (rank) {
      case 'VIP':
        bg = const Color(0xFFFFF7D6); // 옅은 금색 배경
        border = const Color(0xFFD4AF37); // 금색 외곽
        textColor = const Color(0xFF8A6D00); // 진한 골드 텍스트
        icon = Icons.workspace_premium_rounded;
        label = 'VIP 단골 · $n회 방문';
        break;
      case 'REGULAR':
        bg = const Color(0xFFFFE6CC); // 옅은 주황
        border = const Color(0xFFFF8A3D);
        textColor = const Color(0xFFB95B00);
        icon = Icons.local_fire_department_rounded;
        label = '단골 #$n';
        break;
      case 'NORMAL':
      default:
        bg = Colors.white;
        border = AppColors.divider;
        textColor = AppColors.textSecondary;
        icon = Icons.favorite_outline_rounded;
        label = '단골 #$n';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ── 손님 리뷰 요약 라인 (탭 가능) ────────────────────────
  // 디자인 토큰: amber 600 (별점 표준), AppTextStyles.bodySmall.
  // 새 색상/폰트 추가 X — 기존 토큰만 사용.
  Widget _buildCustomerReviewLine() {
    final amber = Colors.amber.shade600;
    final summary = _reviewSummary!;
    final hasReviews = summary.count > 0;

    return InkWell(
      onTap: _openReviewsScreen,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              Icons.rate_review_outlined,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            if (hasReviews) ...[
              Icon(Icons.star_rounded, size: 14, color: amber),
              const SizedBox(width: 2),
              Text(
                summary.averageScore.toStringAsFixed(1),
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${summary.count}) 리뷰 보기',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ] else ...[
              Text(
                '리뷰 0개 — 첫 후기를 남겨봐요',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 14,
              color: AppColors.iconInactive,
            ),
          ],
        ),
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
      child: Column(children: menus.map(_buildMenuRow).toList()),
    );
  }

  Widget _buildMenuRow(MenuItemDto m) {
    final estimate = estimateMenuPrice(
      target: m,
      restaurantMenus: _menuPreview ?? const [],
      restaurantPriceRange: _restaurant?.priceRange,
    );
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
                if (m.source != 'MANUAL')
                  Text(
                    m.source == 'AI_GEMINI'
                        ? 'AI 참고 · 판매가 미확인'
                        : '외부 참고 · 판매가 미확인',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (estimate != null)
                  Text(
                    '${estimate.basis} · 주문 불가',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                if (m.source == 'MANUAL')
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      m.ingredients.isNotEmpty
                          ? '조리 약 ${m.prepTimeMinutes}분 · 재료: ${m.ingredients.join(", ")}'
                          : '조리 약 ${m.prepTimeMinutes}분',
                      style: AppTextStyles.caption.copyWith(
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
            m.source == 'MANUAL'
                ? '${_formatComma(m.price)}원'
                : estimate == null
                ? '가격 확인 필요'
                : '예상 ${_formatComma(estimate.won)}원',
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
            Expanded(child: Text(label, style: AppTextStyles.bodyMedium)),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.iconInactive,
            ),
          ],
        ),
      ),
    );
  }
}
