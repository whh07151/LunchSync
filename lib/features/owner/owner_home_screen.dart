import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../providers/user_provider.dart';
import '../auth/login_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 사장님 홈 화면 (OWNER_HOME)
//
// 진입 조건:
//   - users.role == 'OWNER' AND users.status == 'APPROVED'
//   - main.dart 라우터에서 자동 진입
//
// 테마:
//   - 청록색 (AppType.owner) — main.dart에서 user role에 따라 자동 적용됨
//
// 현재 골격 (캡스톤 1단계 — 화면 구조만 잡아두고 추후 구현):
//   - 상단 앱바: "사장님 모드" + 알림 + 로그아웃
//   - 환영 헤더: 가게 이름 + 오늘 주문 요약(준비 중)
//   - 빠른 실행 4개: 주문 받기 / 메뉴 관리 / 매출 / POS 연동
//   - 하단 탭바: 홈 / 주문 / 메뉴 / 내정보
//
// 추후 (2단계+):
//   - GET /api/pos/restaurants/:id/orders 연동
//   - GET /api/pos/restaurants/:id/stats 연동
//   - 주문 상태 변경 (PATCH /api/pos/orders/:id/status)
//   - POS 단말 연동 화면
// ══════════════════════════════════════════════════════════

class OwnerHomeScreen extends ConsumerStatefulWidget {
  const OwnerHomeScreen({super.key});

  @override
  ConsumerState<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends ConsumerState<OwnerHomeScreen> {
  int _currentTabIndex = 0;

  // ── 로그아웃 처리 ─────────────────────────────────────
  Future<void> _handleLogout() async {
    await ref.read(userProvider.notifier).clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (ctx) => LoginScreen(
          onLoginSuccess: ({required String nextStep}) {
            // 재로그인 후의 라우팅은 main.dart의 _handleLoginSuccess가 담당
            Navigator.of(ctx).pop();
          },
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Icon(
            Icons.storefront_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            'LunchSync 사장님',
            style: AppTextStyles.heading3.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '로그아웃',
          icon: const Icon(Icons.logout_rounded, color: AppColors.textPrimary),
          onPressed: _handleLogout,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBody() {
    return IndexedStack(
      index: _currentTabIndex,
      children: [
        _buildHomeTab(),
        _buildPlaceholderTab('주문 관리', Icons.receipt_long_rounded),
        _buildPlaceholderTab('메뉴 관리', Icons.menu_book_rounded),
        _buildPlaceholderTab('내정보', Icons.person_rounded),
      ],
    );
  }

  // ── 홈 탭 ────────────────────────────────────────────
  Widget _buildHomeTab() {
    final user = ref.watch(userProvider);
    final primary = Theme.of(context).colorScheme.primary;
    final ownerName = user.name ?? '사장님';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 환영 헤더 (청록 그라디언트) ────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.md,
              AppSpacing.screenHorizontal,
              AppSpacing.xl,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [primary, primary.withAlpha(180)],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(AppRadius.bottomSheet),
                bottomRight: Radius.circular(AppRadius.bottomSheet),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$ownerName 사장님, 환영합니다 👋',
                  style: AppTextStyles.heading2.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  '오늘 들어온 주문을 확인해보세요',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Colors.white.withAlpha(200),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── 오늘 요약 카드 (자리잡기 — 데이터는 추후) ───
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
            ),
            child: _buildTodaySummaryCard(),
          ),

          const SizedBox(height: AppSpacing.lg),

          _buildSectionTitle('빠른 실행'),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
            ),
            child: _buildQuickActions(),
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildTodaySummaryCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(child: _summaryItem('대기 중', '-', Icons.pending_actions_rounded)),
          Container(
            width: 1,
            height: 40,
            color: AppColors.divider,
          ),
          Expanded(child: _summaryItem('조리 중', '-', Icons.local_fire_department_rounded)),
          Container(
            width: 1,
            height: 40,
            color: AppColors.divider,
          ),
          Expanded(child: _summaryItem('완료', '-', Icons.check_circle_rounded)),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, IconData icon) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Icon(icon, color: primary, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.heading3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
      ),
      child: Text(title, style: AppTextStyles.heading3),
    );
  }

  Widget _buildQuickActions() {
    final actions = <_OwnerAction>[
      _OwnerAction(
        icon: Icons.receipt_long_rounded,
        label: '주문 받기',
        onTap: () => setState(() => _currentTabIndex = 1),
      ),
      _OwnerAction(
        icon: Icons.menu_book_rounded,
        label: '메뉴 관리',
        onTap: () => setState(() => _currentTabIndex = 2),
      ),
      _OwnerAction(
        icon: Icons.bar_chart_rounded,
        label: '매출',
        onTap: () => _showComingSoon('매출 통계'),
      ),
      _OwnerAction(
        icon: Icons.point_of_sale_rounded,
        label: 'POS 연동',
        onTap: () => _showComingSoon('POS 연동'),
      ),
    ];

    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.9,
      children: actions.map(_buildQuickActionItem).toList(),
    );
  }

  Widget _buildQuickActionItem(_OwnerAction action) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: action.onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: primary.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(action.icon, color: primary, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            action.label,
            style: AppTextStyles.label.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature 기능은 준비 중이에요.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildBottomNav() {
    final tabs = [
      _NavTab(icon: Icons.home_rounded, label: '홈'),
      _NavTab(icon: Icons.receipt_long_rounded, label: '주문'),
      _NavTab(icon: Icons.menu_book_rounded, label: '메뉴'),
      _NavTab(icon: Icons.person_rounded, label: '내정보'),
    ];

    return BottomNavigationBar(
      currentIndex: _currentTabIndex,
      onTap: (index) => setState(() => _currentTabIndex = index),
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Theme.of(context).colorScheme.primary,
      unselectedItemColor: AppColors.iconInactive,
      selectedFontSize: 11,
      unselectedFontSize: 11,
      backgroundColor: AppColors.surface,
      items: tabs
          .map((t) => BottomNavigationBarItem(icon: Icon(t.icon), label: t.label))
          .toList(),
    );
  }

  Widget _buildPlaceholderTab(String label, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.iconInactive),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$label 화면 준비 중',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}


class _OwnerAction {
  const _OwnerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _NavTab {
  const _NavTab({required this.icon, required this.label});
  final IconData icon;
  final String label;
}
