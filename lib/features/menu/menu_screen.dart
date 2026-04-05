import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../models/menu_item.dart';
import '../../providers/cart_provider.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-16 메뉴 목록 / 장바구니 화면
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
//     → (CU-13 식당 상세, 장다연 담당 — 현재 생략)
//       → 이 화면 (메뉴 목록 + 장바구니 구성)
//         → "주문하기" 버튼
//           → CU-20 그룹 주문 검토 (안태환 담당 — 현재 Placeholder)
//
// 브레이크다운 v3 필수 버튼:
//   담기 / 수량+ / 수량- / 삭제
//   (옵션 버튼: 현재 Placeholder, 추후 옵션 선택 바텀시트로 구현 예정)
//
// Mock 데이터 사용 이유:
//   실제 메뉴 데이터는 안태환 씨가 담당하는
//   GET /restaurants/{id}/menus API에서 받아와야 합니다.
//   연동 전까지 코드 안에 직접 적힌 가짜 데이터(Mock)를 사용합니다.
//   → API 연동 시: _mockMenuItems 리스트를 API 응답으로 교체
//
// Riverpod 연동:
//   장바구니 상태(담기/수량변경/제거)는 cartProvider로 전역 관리합니다.
//   이 화면이 닫혀도 장바구니 내용이 유지되어
//   CU-20(그룹 주문 검토)에서 내용을 이어받을 수 있습니다.
// ══════════════════════════════════════════════════════════

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({
    super.key,
    required this.restaurantName, // 식당 이름 (앱바 제목으로 표시)
  });

  /// 상단에 표시할 식당 이름
  /// TODO: CU-13(식당 상세, 장다연 담당) 연동 시 Restaurant 모델로 교체
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

  // ── Mock 메뉴 데이터 ─────────────────────────────────────
  // TODO: API 연동 시 (안태환 씨) — GET /restaurants/{id}/menus 응답으로 교체
  // id는 API 연동 후 서버 ID로 교체될 예정
  static const List<MenuItem> _mockMenuItems = [
    // ── 추천 메뉴 ─────────────────────────────────────────
    MenuItem(
      id: 'm01',
      name: '불고기 덮밥',
      description: '달콤한 불고기 소스와 부드러운 소고기가 밥 위에 올려진 메뉴',
      price: 8900,
      category: MenuCategory.recommended,
    ),
    MenuItem(
      id: 'm02',
      name: '치즈 돈까스',
      description: '두툼한 돼지고기 커틀릿에 진한 치즈 소스',
      price: 9500,
      category: MenuCategory.recommended,
    ),

    // ── 밥류 ────────────────────────────────────────────
    MenuItem(
      id: 'm03',
      name: '제육볶음 정식',
      description: '매콤한 제육볶음 + 공깃밥 + 국 + 반찬 3종',
      price: 9000,
      category: MenuCategory.rice,
    ),
    MenuItem(
      id: 'm04',
      name: '김치찌개 정식',
      description: '묵은지로 끓인 진한 김치찌개 + 밥 + 반찬',
      price: 8500,
      category: MenuCategory.rice,
    ),
    MenuItem(
      id: 'm05',
      name: '비빔밥',
      description: '신선한 야채와 고추장으로 비벼 먹는 건강 한 끼',
      price: 8000,
      category: MenuCategory.rice,
    ),

    // ── 면류 ────────────────────────────────────────────
    MenuItem(
      id: 'm06',
      name: '잔치국수',
      description: '멸치 육수에 소면을 넣은 담백한 국수',
      price: 7000,
      category: MenuCategory.noodle,
    ),
    MenuItem(
      id: 'm07',
      name: '비빔국수',
      description: '새콤달콤한 양념장에 비벼 먹는 여름 별미',
      price: 7500,
      category: MenuCategory.noodle,
    ),

    // ── 분식 ────────────────────────────────────────────
    MenuItem(
      id: 'm08',
      name: '떡볶이',
      description: '쫄깃한 가래떡에 매콤달콤한 소스. 순한맛/매운맛 선택',
      price: 6000,
      category: MenuCategory.snack,
    ),
    MenuItem(
      id: 'm09',
      name: '김밥 (1줄)',
      description: '참기름 향 가득한 참치김밥. 야채·참치·계란 구성',
      price: 4000,
      category: MenuCategory.snack,
    ),
    MenuItem(
      id: 'm10',
      name: '순대볶음',
      description: '당면이 가득한 순대를 매콤하게 볶은 메뉴',
      price: 8000,
      category: MenuCategory.snack,
      isSoldOut: true, // 오늘 품절 예시
    ),

    // ── 음료 ────────────────────────────────────────────
    MenuItem(
      id: 'm11',
      name: '아이스 아메리카노',
      description: '깔끔한 에스프레소에 얼음을 가득 넣은 아이스 커피',
      price: 2500,
      category: MenuCategory.drink,
    ),
    MenuItem(
      id: 'm12',
      name: '식혜',
      description: '전통 발효 음료. 달달하고 시원한 맛',
      price: 2000,
      category: MenuCategory.drink,
    ),
  ];

  // ── 현재 카테고리에 맞게 필터링된 메뉴 목록 ─────────────
  // getter: 탭 선택 때마다 재계산
  List<MenuItem> get _filteredMenuItems {
    if (_selectedCategory == MenuCategory.all) return _mockMenuItems;
    return _mockMenuItems
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

    // 디버그 토스트: 현재 화면 CU 번호 표시 (릴리즈 빌드에서 자동 비활성)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-16');
    });
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

      // ── 본문: 카테고리별 메뉴 목록 ─────────────────────────
      body: Column(
        children: [

          // 메뉴 목록 (Expanded로 남은 공간 모두 차지)
          Expanded(
            child: _buildMenuList(cartItems),
          ),

          // ── 하단 장바구니 요약 바 ─────────────────────────
          // 담긴 항목이 1개 이상일 때만 표시
          if (totalCount > 0)
            _buildCartBottomBar(totalCount, totalPrice),
        ],
      ),
    );
  }

  // ── 앱바 + 탭바 위젯 ────────────────────────────────────
  // PreferredSizeWidget을 반환해야 Scaffold의 appBar에 사용 가능
  PreferredSizeWidget _buildAppBarWithTabs() {
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
            '메뉴 ${_mockMenuItems.length}개',
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

    // 해당 카테고리에 메뉴가 없을 때
    if (items.isEmpty) {
      return Center(
        child: Text(
          '해당 카테고리에 메뉴가 없어요',
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
          // TODO: API 연동 시 (안태환 씨) — item.imageUrl이 있으면 Image.network로 교체
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
          AppPrimaryButton(
            label: '주문하기 ($formattedTotal)',
            onPressed: () {
              // TODO: CU-20 그룹 주문 검토 화면 (안태환 담당) 완성 후 연결
              // 현재는 탭 시 스낵바로 임시 안내
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'CU-20 그룹 주문 검토 화면 연결 예정 (안태환 담당)',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  backgroundColor: AppColors.textPrimary,
                  duration: const Duration(seconds: 2),
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