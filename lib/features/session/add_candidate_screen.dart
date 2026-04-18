import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/user_provider.dart';
import '../../services/restaurants_api_service.dart';
import '../../services/votes_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 투표 후보 식당 추가 화면
//
// 진입 경로: 투표 화면(CU-14) → "식당 후보 추가" 버튼
//
// 주요 기능:
//   - 식당 이름 검색 (GET /restaurants?search=...)
//   - 전체 식당 목록 (반경 내) 브라우징
//   - 선택한 식당을 투표 후보에 추가
//
// 이미 후보에 있는 식당은 "추가됨" 표시로 중복 방지
// ══════════════════════════════════════════════════════════

class AddCandidateScreen extends ConsumerStatefulWidget {
  const AddCandidateScreen({
    super.key,
    required this.sessionId,
    required this.existingCandidateIds,
  });

  final String sessionId;
  final Set<String> existingCandidateIds;

  @override
  ConsumerState<AddCandidateScreen> createState() => _AddCandidateScreenState();
}

class _AddCandidateScreenState extends ConsumerState<AddCandidateScreen> {
  static const _restaurantsApi = RestaurantsApiService();
  static const _votesApi = VotesApiService();

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  List<RestaurantDto> _restaurants = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final Set<String> _addedIds = {};
  bool _anyAdded = false;

  @override
  void initState() {
    super.initState();
    _addedIds.addAll(widget.existingCandidateIds);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRestaurants();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── 식당 목록 로드 ────────────────────────────────────
  Future<void> _loadRestaurants({String? search}) async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    setState(() => _isSearching = search != null);

    final list = await _restaurantsApi.getRestaurants(
      accessToken: token,
      search: search,
      limit: 50,
    );

    if (!mounted) return;
    setState(() {
      _restaurants = list;
      _isLoading = false;
      _isSearching = false;
    });
  }

  // ── 검색 디바운스 ─────────────────────────────────────
  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _loadRestaurants(search: query.isEmpty ? null : query);
    });
  }

  // ── 후보 추가 ─────────────────────────────────────────
  Future<void> _addCandidate(RestaurantDto restaurant) async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    final success = await _votesApi.addCandidate(
      accessToken: token,
      sessionId: widget.sessionId,
      restaurantId: restaurant.id,
      source: 'MANUAL',
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        _addedIds.add(restaurant.id);
        _anyAdded = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${restaurant.name} 후보에 추가됨')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('추가에 실패했습니다. 이미 추가된 식당일 수 있어요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppCustomBar(
          showBack: true,
          title: '식당 후보 추가',
          onBack: () => Navigator.pop(context, _anyAdded),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // ── 검색바 ────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenHorizontal,
                  AppSpacing.md,
                  AppSpacing.screenHorizontal,
                  AppSpacing.sm,
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: '식당 이름으로 검색',
                    hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
                    prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: AppColors.textHint),
                            onPressed: () {
                              _searchController.clear();
                              _loadRestaurants();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.backgroundGrey,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                ),
              ),

              // ── 로딩/검색중 ───────────────────────────
              if (_isLoading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_isSearching)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_restaurants.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search_off_rounded, size: 48, color: AppColors.iconInactive),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          '검색 결과가 없어요',
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // ── 식당 목록 ───────────────────────────
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenHorizontal,
                      0,
                      AppSpacing.screenHorizontal,
                      AppSpacing.xl,
                    ),
                    physics: const BouncingScrollPhysics(),
                    itemCount: _restaurants.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) => _buildRestaurantCard(_restaurants[i]),
                  ),
                ),
            ],
          ),
        ),
    );
  }

  // ── 식당 카드 ─────────────────────────────────────────
  Widget _buildRestaurantCard(RestaurantDto restaurant) {
    final primary = Theme.of(context).colorScheme.primary;
    final isAdded = _addedIds.contains(restaurant.id);

    final priceLabel = restaurant.priceRange != null
        ? '${_formatWithComma(restaurant.priceRange!)}원대'
        : '가격 미정';

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          // 식당 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  restaurant.name,
                  style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (restaurant.category != null) ...[
                      const Icon(Icons.restaurant_rounded, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(restaurant.category!, style: AppTextStyles.bodySmall),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    const Icon(Icons.payments_outlined, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(priceLabel, style: AppTextStyles.bodySmall),
                  ],
                ),
                if (restaurant.address != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          restaurant.address!,
                          style: AppTextStyles.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

          // 추가 버튼
          if (isAdded)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.backgroundGrey,
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              child: Text(
                '추가됨',
                style: AppTextStyles.buttonMedium.copyWith(color: AppColors.textHint),
              ),
            )
          else
            GestureDetector(
              onTap: () => _addCandidate(restaurant),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                child: Text(
                  '추가',
                  style: AppTextStyles.buttonMedium.copyWith(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatWithComma(int value) {
    final s = value.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}
