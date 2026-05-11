import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../providers/user_provider.dart';
import '../../services/restaurants_api_service.dart';
import '../../services/external_map_launcher.dart';
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
  static const _mapLauncher = ExternalMapLauncher();

  RestaurantDto? _restaurant;
  List<MenuItemDto>? _menuPreview;
  bool _isRestaurantLoading = true;
  bool _isMenuLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-13');
      _loadDetail();
      _loadMenus();
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
  void _goToFullMenu() {
    final name = _restaurant?.name ?? widget.initialName ?? '식당';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MenuScreen(restaurantName: name),
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
    final priceLabel =
        r.priceRange != null ? '${_formatComma(r.priceRange!)}원대' : '가격 미정';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      color: primary.withAlpha(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
          vertical: AppSpacing.md,
        ),
        child: Text(
          '등록된 메뉴가 없어요',
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
