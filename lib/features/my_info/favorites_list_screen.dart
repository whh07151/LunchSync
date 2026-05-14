import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/user_provider.dart';
import '../../services/favorites_api_service.dart';
import '../restaurant/restaurant_detail_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 내정보 > 즐겨찾기 식당 목록 화면 (배민 "찜한 가게" 패턴)
//
// 진입 경로:
//   - 내정보 탭(MyInfoScreen) > "내 즐겨찾기" 활동 카드 탭
//   - (향후) 홈 화면 즐겨찾기 위젯 우측 "전체 보기" 진입
//
// 연동 API:
//   GET /api/users/me/favorites — FavoritesApiService.list()
//   반환: List<FavoriteDto> (이름·카테고리·주소·이미지·평점 포함)
//
// 상태:
//   - 로딩 : 중앙 스피너
//   - 빈   : 안내 박스 + "둘러보기" CTA(홈으로 pop)
//   - 정상 : 카드 세로 리스트, 탭 → CU-13 RestaurantDetailScreen
//
// 디자인 토큰만 사용 — 새 색상/그라디언트 정의하지 않음.
// ══════════════════════════════════════════════════════════

class FavoritesListScreen extends ConsumerStatefulWidget {
  const FavoritesListScreen({super.key});

  @override
  ConsumerState<FavoritesListScreen> createState() =>
      _FavoritesListScreenState();
}

class _FavoritesListScreenState extends ConsumerState<FavoritesListScreen> {
  // FavoritesApiService 는 const 생성자 — 매 빌드 신규 인스턴스 생성 비용 0.
  static const _api = FavoritesApiService();

  // 화면 상태:
  //   - _isLoading: 첫 진입 또는 새로고침 중
  //   - _favorites: 마지막 성공 응답. 빈 리스트면 "빈 상태" 분기.
  bool _isLoading = true;
  List<FavoriteDto> _favorites = const [];

  @override
  void initState() {
    super.initState();
    // 첫 프레임 이후 API 호출 — initState 안에서 ref.read 안전 시점.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  // ── 즐겨찾기 목록 조회 ─────────────────────────────────
  // accessToken 이 없으면(로그아웃 가드) 빈 리스트로 폴백.
  Future<void> _load() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final list = await _api.list(accessToken: token);
    if (!mounted) return;
    setState(() {
      _favorites = list;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          '내 즐겨찾기',
          style: AppTextStyles.heading3.copyWith(color: AppColors.textPrimary),
        ),
        // 새로고침 액션 — 식당 상세에서 토글 후 돌아왔을 때 빠르게 동기화.
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() => _isLoading = true);
              _load();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  // ── 본문 분기 ──────────────────────────────────────────
  // 로딩 / 빈 / 정상 — RefreshIndicator 로 끌어내려 새로고침도 지원.
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_favorites.isEmpty) {
      return _buildEmptyState();
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics:
            const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        itemCount: _favorites.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (_, index) => _buildFavoriteCard(_favorites[index]),
      ),
    );
  }

  // ── 빈 상태 ────────────────────────────────────────────
  // 카피: 다음 액션을 분명히("자주 가는 식당을 즐겨찾기 해보세요").
  // CTA: "둘러보기" → 홈 탭으로 pop. 별도 탭 전환 로직 없이 단순.
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite_outline_rounded,
              size: 48,
              color: AppColors.iconInactive,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '아직 즐겨찾기한 식당이 없어요',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '자주 가는 식당의 하트를 눌러보세요',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.restaurant_rounded, size: 16),
              label: const Text('식당 둘러보기'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.border),
                foregroundColor: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 즐겨찾기 카드 한 장 ────────────────────────────────
  // 이미지(있으면) + 이름 + 카테고리 + 평점(있으면).
  // 탭 → RestaurantDetailScreen 으로 이동 (즐겨찾기 UI 이미 구현됨).
  Widget _buildFavoriteCard(FavoriteDto fav) {
    return AppCard(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RestaurantDetailScreen(
              restaurantId: fav.id,
              initialName: fav.name,
            ),
          ),
        );
        // 상세에서 하트 해제 후 돌아왔을 때 카운트 동기화.
        if (!mounted) return;
        _load();
      },
      child: Row(
        children: [
          // 이미지 썸네일 — FoodImage 가 빈 URL 안전 처리.
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: FoodImage(
              // 2026-05-15 자율 E2E 회귀 fix: categoryLabel required 누락.
              imageUrl: fav.imageUrl,
              categoryLabel: fav.category,
              width: 56,
              height: 56,
              emojiSize: 26,
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fav.name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  fav.category,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                // 평점이 있으면 한 줄 더 — 디자인 토큰만 사용.
                if (fav.rating != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        fav.rating!.toStringAsFixed(1),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.iconInactive,
          ),
        ],
      ),
    );
  }
}
