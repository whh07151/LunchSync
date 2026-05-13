import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../models/menu_item.dart';
import '../../providers/cart_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/restaurants_api_service.dart';
import '../payment/order_review_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-16 메뉴 목록 / 장바구니 화면
//
// [데이터 소스]
//   - 진입 시 받은 widget.restaurantId 로
//     GET /api/restaurants/:id/menus 호출 → MenuItemDto 리스트 수신
//   - 백엔드 응답을 MenuItem 모델로 매핑해서 _menuItems 상태에 저장
//   - 카테고리 탭 변경 시 _filteredMenuItems getter 로 필터링
//
// [버그 히스토리]
//   - 2026-05-13 이전: 어느 식당에 들어가도 항상 시드 RESTAURANT_ID
//     ('11111111-...') 의 하드코딩된 12개 mock 메뉴만 보였음.
//     restaurant_detail_screen.dart 가 restaurantId 를 안 넘기고,
//     이 화면이 _mockMenuItems 만 그려서 발생.
//   - 2026-05-13 수정: restaurantId 인자 추가 + 실 API 연동 + 빈 상태 처리.
//
// 와이어프레임 기준 구성 요소 (브레이크다운 v3 CU-16):
//   - 상단 앱바: 식당 이름 + 뒤로가기
//   - 카테고리 탭바: 전체 / 추천 / 밥류 / 면류 / 분식 / 음료
//   - 메뉴 항목 목록:
//       이미지 영역 + 이름 + 설명 + 가격 + 담기/수량 조절 버튼
//   - 하단 고정 바:
//       총 담긴 수량 + 총 금액 + "주문하기" 버튼
//
// 동작 흐름:
//   홈(CU-06) 식당 카드 탭
//     → CU-13 식당 상세 (전체 보기 버튼)
//       → 이 화면 (restaurantId 로 메뉴 조회 + 장바구니 구성)
//         → "주문하기" 버튼
//           → CU-17 그룹 주문 검토 (OrderReviewScreen)
//
// Riverpod 연동:
//   장바구니 상태(담기/수량변경/제거)는 cartProvider로 전역 관리합니다.
//   이 화면이 닫혀도 장바구니 내용이 유지되어
//   CU-20(그룹 주문 검토)에서 내용을 이어받을 수 있습니다.
// ══════════════════════════════════════════════════════════

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({
    super.key,
    required this.restaurantId,   // 현재 진입한 식당의 UUID
    required this.restaurantName, // 식당 이름 (앱바 제목으로 표시)
  });

  /// 메뉴를 조회할 식당의 UUID
  /// (restaurant_detail_screen.dart 에서 widget.restaurantId 전달)
  final String restaurantId;

  /// 상단에 표시할 식당 이름
  final String restaurantName;

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen>
    with SingleTickerProviderStateMixin {

  // ── 카테고리 탭 컨트롤러 ────────────────────────────────
  // SingleTickerProviderStateMixin: TabController 애니메이션에 필요한 Ticker 제공
  late final TabController _tabController;

  // ── 현재 선택된 카테고리 ─────────────────────────────────
  // 탭 변경 시 이 값을 기준으로 메뉴 목록을 필터링합니다.
  MenuCategory _selectedCategory = MenuCategory.all;

  // ── 식당/메뉴 API 서비스 ─────────────────────────────────
  static const _restaurantsApi = RestaurantsApiService();

  // ── 메뉴 상태 ────────────────────────────────────────────
  // null = 아직 로딩 중, [] = 빈 응답(메뉴 없음), [..] = 정상 응답
  List<MenuItem>? _menuItems;
  bool _isLoading = true;
  String? _loadError;

  // ── 현재 카테고리에 맞게 필터링된 메뉴 목록 ─────────────
  // getter: 탭 선택 때마다 재계산
  List<MenuItem> get _filteredMenuItems {
    final items = _menuItems ?? const <MenuItem>[];
    if (_selectedCategory == MenuCategory.all) return items;
    return items
        .where((item) => item.category == _selectedCategory)
        .toList();
  }

  // ── 생명주기: 화면 초기화 ───────────────────────────────
  @override
  void initState() {
    super.initState();

    // TabController 초기화
    // length: 탭 수 = MenuCategory의 값 수
    // vsync: 애니메이션 타이밍을 위해 this(Ticker) 전달
    _tabController = TabController(
      length: MenuCategory.values.length,
      vsync: this,
    );

    // 탭이 바뀔 때마다 _selectedCategory 업데이트 → UI 재빌드
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return; // 애니메이션 중엔 무시
      setState(() {
        _selectedCategory = MenuCategory.values[_tabController.index];
      });
    });

    // 첫 프레임 이후 토스트 + 메뉴 로딩 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-16');
      _loadMenus();
    });
  }

  // ── 메뉴 목록 로딩 ──────────────────────────────────────
  // 백엔드의 GET /api/restaurants/:id/menus 를 호출해서
  // 현재 진입한 식당의 실제 메뉴를 받아옵니다.
  // - JWT 없으면 로그인 안내 상태로 종료
  // - 응답 카테고리 문자열을 MenuCategory enum 으로 매핑
  Future<void> _loadMenus() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = '로그인 정보가 없어 메뉴를 불러올 수 없어요.';
      });
      return;
    }

    final dtoList = await _restaurantsApi.getMenus(
      accessToken: token,
      restaurantId: widget.restaurantId,
    );

    if (!mounted) return;

    // DTO → 화면용 MenuItem 모델 변환
    // - 백엔드 category 문자열을 enum 으로 매핑
    // - description 누락 시 빈 문자열로 폴백
    final mapped = dtoList
        .map((dto) => MenuItem(
              id: dto.id,
              restaurantId: widget.restaurantId,
              name: dto.name,
              description: dto.description ?? '',
              price: dto.price,
              category: _mapCategory(dto.category),
              imageUrl: dto.imageUrl,
            ))
        .toList();

    setState(() {
      _menuItems = mapped;
      _isLoading = false;
      _loadError = null;
    });
  }

  // ── 백엔드 카테고리 문자열 → MenuCategory enum 매핑 ─────
  // 백엔드에서 어떤 키워드로 카테고리를 내려주는지에 따라
  // 적절한 enum 으로 변환. 매칭 안 되면 "전체" 로 표시되지 않게
  // recommended(추천) 로 떨어뜨려 사용자에게는 보이도록 한다.
  //
  // 매핑 규칙(우리 시드/팀 네이밍 컨벤션 기준):
  //   "추천" / "recommended"  → MenuCategory.recommended
  //   "밥" 또는 "정식" 포함     → MenuCategory.rice
  //   "면" 또는 "국수" 포함     → MenuCategory.noodle
  //   "분식"                    → MenuCategory.snack
  //   "음료" / "디저트"         → MenuCategory.drink
  //   그 외 / null              → MenuCategory.recommended (보이게)
  MenuCategory _mapCategory(String? raw) {
    if (raw == null || raw.isEmpty) return MenuCategory.recommended;
    final lower = raw.toLowerCase();

    if (raw.contains('추천') || lower.contains('recommend')) {
      return MenuCategory.recommended;
    }
    if (raw.contains('밥') || raw.contains('정식') || lower.contains('rice')) {
      return MenuCategory.rice;
    }
    if (raw.contains('면') || raw.contains('국수') || lower.contains('noodle')) {
      return MenuCategory.noodle;
    }
    if (raw.contains('분식') || lower.contains('snack')) {
      return MenuCategory.snack;
    }
    if (raw.contains('음료') ||
        raw.contains('디저트') ||
        lower.contains('drink') ||
        lower.contains('beverage')) {
      return MenuCategory.drink;
    }
    // 알 수 없는 카테고리는 일단 "추천" 탭에 묶어 노출 (전체 탭에서도 보임)
    return MenuCategory.recommended;
  }

  // ── 생명주기: TabController 메모리 해제 ─────────────────
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── UI 최상위 구성 ──────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // cartProvider 감시: 장바구니가 바뀔 때마다 하단 바 및 버튼 UI 갱신
    final cartNotifier = ref.watch(cartProvider.notifier);
    final cartItems = ref.watch(cartProvider);

    // 총 담긴 수량과 총 금액 계산
    final totalCount = cartNotifier.totalCount;
    final totalPrice = cartNotifier.totalPrice;

    return Scaffold(
      backgroundColor: AppColors.background,

      // ── 상단 앱바 + 카테고리 탭바 ─────────────────────────
      appBar: _buildAppBarWithTabs(),

      // ── 본문: 로딩 / 에러 / 빈 상태 / 카테고리별 메뉴 목록 ─
      body: Column(
        children: [

          // 메뉴 목록 (Expanded로 남은 공간 모두 차지)
          Expanded(
            child: _buildBody(cartItems),
          ),

          // ── 하단 장바구니 요약 바 ─────────────────────────
          // 담긴 항목이 1개 이상일 때만 표시
          if (totalCount > 0)
            _buildCartBottomBar(totalCount, totalPrice),
        ],
      ),
    );
  }

  // ── 본문 분기 위젯 ──────────────────────────────────────
  // 로딩 / 에러 / 빈 / 정상 4가지 상태 처리
  Widget _buildBody(List<CartItem> cartItems) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            _loadError!,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }
    final allItems = _menuItems ?? const <MenuItem>[];
    if (allItems.isEmpty) {
      // 식당 자체에 메뉴가 1개도 없는 경우 (등록 전 식당 등)
      // 빈 상태 — 사장님 메뉴 등록 대기 안내, 친근한 톤
      return Center(
        child: Text(
          '메뉴는 사장님이 곧 올려주실 거예요',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }
    return _buildMenuList(cartItems);
  }

  // ── 앱바 + 탭바 위젯 ────────────────────────────────────
  // PreferredSizeWidget을 반환해야 Scaffold의 appBar에 사용 가능
  PreferredSizeWidget _buildAppBarWithTabs() {
    // 메뉴 개수: 로딩 중이면 "..." 로 표시
    final countLabel = _isLoading
        ? '메뉴 불러오는 중...'
        : '메뉴 ${(_menuItems ?? const []).length}개';

    return AppBar(
      // 뒤로가기 버튼 자동 추가 (이전 화면으로 돌아갈 수 있음)
      leading: const BackButton(),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 식당 이름
          Text(
            widget.restaurantName,
            style: AppTextStyles.heading3,
          ),
          // 메뉴 개수 안내
          Text(
            countLabel,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),

      // 탭바: 카테고리 분류 탭 (앱바 하단에 붙음)
      bottom: TabBar(
        controller: _tabController,

        // 탭이 많으면 가로 스크롤 가능
        isScrollable: true,
        tabAlignment: TabAlignment.start, // 왼쪽 정렬

        // 선택된 탭 강조 색상
        labelColor: Theme.of(context).colorScheme.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: Theme.of(context).colorScheme.primary,
        indicatorWeight: 2.5,

        labelStyle: AppTextStyles.bodyMedium.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: AppTextStyles.bodyMedium,

        // MenuCategory enum의 모든 값을 탭으로 생성
        tabs: MenuCategory.values
            .map((cat) => Tab(text: cat.label))
            .toList(),
      ),
    );
  }

  // ── 메뉴 목록 위젯 ──────────────────────────────────────
  // 현재 카테고리에 해당하는 메뉴만 필터링하여 세로 목록으로 표시
  Widget _buildMenuList(List<CartItem> cartItems) {
    final items = _filteredMenuItems;

    // 해당 카테고리에 메뉴가 없을 때 (전체 식당에는 메뉴 있지만 탭 필터로 0개)
    if (items.isEmpty) {
      // 빈 상태 — 다른 탭에는 있을 수 있다는 점을 안내해 다음 액션 유도
      return Center(
        child: Text(
          '이 카테고리는 비어있어요. 다른 탭을 둘러보세요',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
        vertical: AppSpacing.md,
      ),
      itemCount: items.length,
      // 항목 사이 구분선
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        color: AppColors.divider,
      ),
      itemBuilder: (context, index) {
        // 이 메뉴가 장바구니에 몇 개 담겨 있는지
        final qty = ref.read(cartProvider.notifier).quantityOf(items[index].id);
        return _buildMenuItemCard(items[index], qty);
      },
    );
  }

  // ── 메뉴 항목 카드 위젯 하나 ────────────────────────────
  // 이미지 영역 + 이름/설명/가격 + 담기/수량 조절 버튼
  Widget _buildMenuItemCard(MenuItem item, int cartQty) {
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── 메뉴 이미지 영역 ─────────────────────────────
          // item.imageUrl 이 있으면 Image.network, 없으면 음식 아이콘
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              // 이미지 없을 때: 연한 주황 배경 + 음식 아이콘
              color: item.isSoldOut
                  ? AppColors.backgroundGrey     // 품절: 회색 배경
                  : primary.withAlpha(15),        // 판매 중: 연한 주황 배경
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: item.isSoldOut
                ? Center(
                    child: Text(
                      '품절',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : Center(
                    child: Icon(
                      Icons.restaurant_rounded,
                      color: primary.withAlpha(100),
                      size: 36,
                    ),
                  ),
          ),

          const SizedBox(width: AppSpacing.md),

          // ── 메뉴 정보 + 버튼 영역 ────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── 메뉴 이름 ──────────────────────────────
                Text(
                  item.name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    // 품절이면 텍스트를 흐리게 표시
                    color: item.isSoldOut
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),

                const SizedBox(height: 4),

                // ── 메뉴 설명 ──────────────────────────────
                Text(
                  item.description,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis, // 2줄 초과 시 ... 처리
                ),

                const SizedBox(height: AppSpacing.sm),

                // ── 가격 + 담기 버튼 행 ───────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [

                    // 가격 표시
                    Text(
                      item.formattedPrice,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: item.isSoldOut
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),

                    // ── 장바구니 조작 버튼 영역 ───────────
                    // 품절이면 "품절" 뱃지, 담기지 않았으면 "담기" 버튼,
                    // 1개 이상 담겼으면 수량 조절(- / 수량 / +) 버튼
                    if (item.isSoldOut)
                      // 품절 상태 배지
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundGrey,
                          borderRadius:
                              BorderRadius.circular(AppRadius.chip),
                        ),
                        child: Text(
                          '품절',
                          style: AppTextStyles.label.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    else if (cartQty == 0)
                      // ── "담기" 버튼 (장바구니에 없을 때) ─
                      GestureDetector(
                        onTap: () {
                          // cartProvider에 이 메뉴를 1개 추가
                          ref.read(cartProvider.notifier).addItem(item);
                          // 담기 후 UI 갱신: setState로 이 항목의 cartQty가 반영됨
                          setState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: primary,
                            borderRadius:
                                BorderRadius.circular(AppRadius.chip),
                          ),
                          child: Text(
                            '담기',
                            style: AppTextStyles.label.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    else
                      // ── 수량 조절 버튼 (이미 담긴 경우) ──
                      // [ -  수량  + ] 형태의 인라인 컨트롤
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [

                          // 수량 감소 버튼 (0이 되면 항목 자동 제거)
                          _buildQuantityButton(
                            icon: Icons.remove_rounded,
                            onTap: () {
                              ref
                                  .read(cartProvider.notifier)
                                  .decreaseItem(item.id);
                              setState(() {}); // UI 즉시 갱신
                            },
                          ),

                          // 현재 수량 표시
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                            child: Text(
                              '$cartQty',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: primary,
                              ),
                            ),
                          ),

                          // 수량 증가 버튼
                          _buildQuantityButton(
                            icon: Icons.add_rounded,
                            onTap: () {
                              ref
                                  .read(cartProvider.notifier)
                                  .addItem(item);
                              setState(() {}); // UI 즉시 갱신
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 수량 조절 공통 버튼 위젯 ───────────────────────────────
  // - / + 버튼에 공통으로 사용하는 원형 아이콘 버튼
  Widget _buildQuantityButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: primary.withAlpha(20),   // 연한 주황 배경
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: primary),
      ),
    );
  }

  // ── 하단 장바구니 요약 바 위젯 ─────────────────────────────
  // 담긴 메뉴 수량 + 총 금액 + "주문하기" 버튼
  // 장바구니에 1개 이상 담겼을 때만 표시됨
  Widget _buildCartBottomBar(int totalCount, int totalPrice) {
    // 총 금액 포맷: MenuItem.formattedPrice와 동일한 방식
    final formattedTotal = _formatPrice(totalPrice);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        12,
        AppSpacing.screenHorizontal,
        32, // 하단 SafeArea 여백
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          // ── 총 수량 + 총 금액 요약 행 ─────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 담긴 총 메뉴 수
              Text(
                '총 $totalCount개',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),

              // 총 금액 (강조 표시)
              Text(
                '합계 $formattedTotal',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── "주문하기" 버튼 ───────────────────────────────
          // CU-17 주문 검토 화면으로 이동 → CU-18/19 토스 결제로 이어짐
          //
          // sessionId 는 아직 점심 세션 흐름과 직접 연결되어 있지 않아
          // seed-test-data.ts 의 고정 UUID 를 사용합니다.
          // TODO: sessionProvider 에 currentSessionId 가 들어오면 그걸 사용.
          AppPrimaryButton(
            label: '주문하기 ($formattedTotal)',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OrderReviewScreen(
                    sessionId: '22222222-2222-2222-2222-222222222222',
                    restaurantName: widget.restaurantName,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── 가격 포맷 헬퍼 ──────────────────────────────────────────
  // 세 자리마다 쉼표를 추가해 "14,500원" 형태로 반환
  String _formatPrice(int price) {
    final parts = <String>[];
    var n = price;
    while (n >= 1000) {
      parts.insert(0, (n % 1000).toString().padLeft(3, '0'));
      n ~/= 1000;
    }
    parts.insert(0, n.toString());
    return '${parts.join(',')}원';
  }
}
