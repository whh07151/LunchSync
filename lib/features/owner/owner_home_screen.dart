import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/components/components.dart';
import '../../core/theme/theme.dart';
import '../../providers/user_provider.dart';
import '../../services/pos_api_service.dart';
import '../auth/login_screen.dart';
import 'menu_management_screen.dart';
import 'owner_profile_edit_screen.dart';
import 'sales_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 사장님 홈 화면 (OWNER_HOME)
//
// 진입 조건:
//   - users.role == 'OWNER' AND users.status == 'APPROVED'
//   - main.dart 라우터에서 자동 진입
//
// 데이터 흐름 (2026-05-11):
//   - users.restaurant_id 가 NULL 이면 → "매장 매핑 대기" 안내 카드만 표시.
//     운영자(우현호)가 Supabase 콘솔에서 UPDATE users SET restaurant_id=...
//     수동 매핑한 뒤 다음 로그인/새로고침 시 실제 데이터 진입.
//   - restaurantId 가 있으면 → GET /api/pos/restaurants/:id/stats 와
//     GET /api/pos/restaurants/:id/orders 호출. 10초 폴링.
//
// 테마:
//   - 청록색 (AppType.owner) — main.dart에서 user role에 따라 자동 적용됨
//
// 추후 (2단계+):
//   - 주문 상태 변경 (PATCH /api/pos/orders/:id/status) — 카드 액션 버튼
//   - 메뉴 관리 / 매출 통계 화면
//   - POS 단말 연동 (LSPOS)
// ══════════════════════════════════════════════════════════

/// 사장 홈 폴링 주기 — POS 단말과 동일하게 짧게 잡으면 백엔드 부하가 늘어
/// 손님앱(3초)보다 길게 10초로 설정. 사장은 손님과 달리 즉시성보다 안정성이 중요.
const Duration _kOwnerPollInterval = Duration(seconds: 10);

class OwnerHomeScreen extends ConsumerStatefulWidget {
  const OwnerHomeScreen({super.key});

  @override
  ConsumerState<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends ConsumerState<OwnerHomeScreen>
    with WidgetsBindingObserver {
  int _currentTabIndex = 0;

  // 데이터 상태
  PosStats? _stats;
  List<PosOrder> _orders = const [];
  bool _isLoading = false;
  String? _loadError;

  /// 현재 PATCH 진행 중인 주문 ID — 중복 클릭 방지 + 버튼 로딩 표시.
  /// null 이면 아무 주문도 처리 중이 아님.
  String? _processingOrderId;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // 라이프사이클 옵저버 — 백그라운드 진입 시 폴링 일시 중단해 배터리/네트워크 절약.
    WidgetsBinding.instance.addObserver(this);
    // 첫 진입 시 즉시 1회 조회 + 폴링 타이머 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchAll();
      _startPolling();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── 폴링 타이머 시작/중단 헬퍼 ─────────────────────────
  // 라이프사이클에 따라 짧게 켜고 끄도록 분리. 중복 실행 가드 포함.
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_kOwnerPollInterval, (_) => _fetchAll());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 포그라운드 복귀: 즉시 1회 + 폴링 재개. 백그라운드/일시정지: 폴링 중단.
    switch (state) {
      case AppLifecycleState.resumed:
        _fetchAll();
        _startPolling();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _stopPolling();
        break;
    }
  }

  // ── 데이터 조회 (stats + orders 병렬) ─────────────────
  // restaurantId 가 없으면 호출 자체를 건너뜀.
  Future<void> _fetchAll() async {
    final user = ref.read(userProvider);
    final token = user.accessToken;
    final restaurantId = user.restaurantId;

    if (token == null || restaurantId == null || restaurantId.isEmpty) {
      // 매장 매핑 안 됨 → 데이터 호출 스킵
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      const api = PosApiService();
      final results = await Future.wait([
        api.getStats(accessToken: token, restaurantId: restaurantId),
        api.getOrders(accessToken: token, restaurantId: restaurantId),
      ]);

      if (!mounted) return;
      setState(() {
        _stats = results[0] as PosStats;
        _orders = results[1] as List<PosOrder>;
        _loadError = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // 실패 시 이전 데이터(_stats/_orders) 유지 — 폴링 1회 실패로 화면이
      // 빈 상태로 돌아가 깜빡거리는 인상이 컸음(사장님 피드백 2026-05-14).
      // 에러 배너만 노출하고 마지막 성공 데이터 그대로 보여준다.
      setState(() {
        _loadError = '데이터를 불러오지 못했어요';
        _isLoading = false;
      });
    }
  }

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
          tooltip: '새로고침',
          icon: const Icon(Icons.refresh_rounded, color: AppColors.textPrimary),
          onPressed: _fetchAll,
        ),
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
        _buildOrdersTab(),
        const MenuManagementScreen(),
        _buildOwnerInfoTab(),
      ],
    );
  }

  // ── 4번 탭: 사장 내정보 ─────────────────────────────────
  // 사장 계정 정보 + 매장 매핑 상태 + 매출/메뉴 진입 + 로그아웃.
  // 손님 MyInfoScreen 은 소속/예산/속도 칩이라 사장에 부적합 → 별도 페이지로 구성.
  Widget _buildOwnerInfoTab() {
    final user = ref.watch(userProvider);
    final primary = Theme.of(context).colorScheme.primary;
    final hasRestaurant =
        user.restaurantId != null && user.restaurantId!.isNotEmpty;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),

          // 프로필 박스 — 상호 + 사업자번호 + 매장 매핑 상태
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: primary.withAlpha(30),
                  child: Icon(
                    Icons.storefront_rounded,
                    color: primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // 상호가 있으면 상호를 메인 타이틀로, 없으면 이름.
                        (user.businessName != null &&
                                user.businessName!.isNotEmpty)
                            ? user.businessName!
                            : (user.name ?? '사장님'),
                        style: AppTextStyles.bodyLarge
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${user.name ?? "사장님"} · ${hasRestaurant ? "매장 연동됨" : "매장 매핑 대기"}',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      if (user.businessNumber != null &&
                          user.businessNumber!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '사업자번호 ${user.businessNumber}',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // 메뉴 리스트
          _ownerInfoRow(
            icon: Icons.edit_rounded,
            label: '정보 수정',
            onTap: () async {
              // 수정 후 상태가 setFromProfile 로 동기화되므로 별도 처리 불필요
              await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => const OwnerProfileEditScreen(),
                ),
              );
              if (mounted) setState(() {}); // 표시값 즉시 갱신
            },
          ),
          _ownerInfoRow(
            icon: Icons.bar_chart_rounded,
            label: '매출 보기',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SalesScreen()),
            ),
          ),
          _ownerInfoRow(
            icon: Icons.menu_book_rounded,
            label: '메뉴 관리',
            onTap: () => setState(() => _currentTabIndex = 2),
          ),
          _ownerInfoRow(
            icon: Icons.refresh_rounded,
            label: '주문 새로고침',
            onTap: _fetchAll,
          ),

          const SizedBox(height: AppSpacing.xl),

          OutlinedButton.icon(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('로그아웃'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(color: AppColors.error.withAlpha(80)),
              minimumSize: const Size.fromHeight(48),
            ),
          ),

          const SizedBox(height: AppSpacing.md),
          Center(
            child: Text(
              'LunchSync 사장님 v1.0',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ownerInfoRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(label, style: AppTextStyles.bodyMedium),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.iconInactive,
        ),
        onTap: onTap,
      ),
    );
  }

  // ── 홈 탭 ────────────────────────────────────────────
  Widget _buildHomeTab() {
    final user = ref.watch(userProvider);
    final primary = Theme.of(context).colorScheme.primary;
    final ownerName = user.name ?? '사장님';
    final hasRestaurant =
        user.restaurantId != null && user.restaurantId!.isNotEmpty;

    return RefreshIndicator(
      onRefresh: _fetchAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
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
                    hasRestaurant
                        ? '오늘 들어온 주문을 확인해보세요'
                        : '매장 매핑이 완료되면 주문 정보가 표시돼요',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── 매장 매핑 안 됐으면 안내 카드, 됐으면 요약 카드 ─
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
              ),
              child: hasRestaurant
                  ? _buildTodaySummaryCard()
                  : _buildRestaurantPendingCard(),
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
      ),
    );
  }

  // ── 매장 미매핑 안내 카드 ───────────────────────────────
  // businessName 같은 추가 정보는 UserState 에 들어있지 않아서 표시하지 않음.
  // 필요해지면 UsersApiService.getMe() 결과의 businessName 을 별도 state 로 보관.
  Widget _buildRestaurantPendingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppColors.warning, size: 20),
              const SizedBox(width: 6),
              Text(
                '매장 매핑 대기 중',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '운영자가 가게 정보를 매장 데이터와 연결하면 주문이 표시돼요. '
            '잠시만 기다려 주세요.',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ── 오늘 요약 카드 (실제 PosStats 사용) ────────────────
  Widget _buildTodaySummaryCard() {
    final s = _stats;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _summaryItem(
                  '대기 중',
                  s == null ? '-' : '${s.waitingCount}',
                  Icons.pending_actions_rounded,
                ),
              ),
              Container(width: 1, height: 40, color: AppColors.divider),
              Expanded(
                child: _summaryItem(
                  '조리 중',
                  s == null ? '-' : '${s.cookingCount}',
                  Icons.local_fire_department_rounded,
                ),
              ),
              Container(width: 1, height: 40, color: AppColors.divider),
              Expanded(
                child: _summaryItem(
                  '완료',
                  s == null ? '-' : '${s.doneCount}',
                  Icons.check_circle_rounded,
                ),
              ),
            ],
          ),
          if (_loadError != null) ...[
            const SizedBox(height: 10),
            Text(
              _loadError!,
              style: AppTextStyles.caption.copyWith(color: AppColors.error),
            ),
          ],
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
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SalesScreen()),
        ),
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

  // ── 주문 탭 — 간단 리스트 (1단계) ────────────────────────
  // 상태 전이 액션은 다음 단계에서 추가 (PATCH /pos/orders/:id/status).
  Widget _buildOrdersTab() {
    final user = ref.watch(userProvider);
    final hasRestaurant =
        user.restaurantId != null && user.restaurantId!.isNotEmpty;

    if (!hasRestaurant) {
      return _buildEmptyOrders('매장 매핑이 완료되면 주문이 표시돼요');
    }

    if (_isLoading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            // 빈 상태 — 사장님 대기 화면, 곧 들어올 거라는 기대치 형성
            _buildEmptyOrders('새 주문을 기다리는 중이에요'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchAll,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _orders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _buildOrderCard(_orders[i]),
      ),
    );
  }

  // ── 빈 상태 위젯 — AppEmptyState 컴포넌트로 일관화 ────
  // 다른 빈 상태 화면(order_list/notification 등)이 모두 AppEmptyState 를 쓰는데
  // 사장 홈만 인라인이라 디자이너 가이드 P0(컴포넌트 일관화)와 어긋났음.
  // 카피는 사장 맥락에 맞춰 다듬되 톤(친근체)은 유지.
  // - title:       한 줄 핵심 메시지 (호출 측에서 넘김)
  // - description: 상태별 부연 설명 — 매장 매핑 대기 vs 새 주문 대기
  Widget _buildEmptyOrders(String message) {
    // 매핑 대기 케이스인지 메시지로 식별 — 두 케이스만 있어 단순 분기.
    final isAwaitingMapping = message.contains('매장 매핑');
    return AppEmptyState(
      icon: Icons.receipt_long_rounded,
      title: message,
      description: isAwaitingMapping
          ? '운영자가 매장을 연결하면 여기에 주문이 차근차근 쌓여요'
          : '새 주문이 들어오면 자동으로 이 자리에 표시돼요',
    );
  }

  Widget _buildOrderCard(PosOrder order) {
    final statusColor = _statusColor(order.status);
    final statusLabel = _statusLabel(order.status);
    final nextLabel = _nextStatusLabel(order.status);
    final canAdvance = _nextStatus(order.status) != null;
    final canCancel = _isCancellable(order.status);
    final isProcessing = _processingOrderId == order.id;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 상단: 상태 배지 + 주문 정보 + 합계 ─────────────
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(28),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusLabel,
                  style: AppTextStyles.caption.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.orderNumber ??
                          '#${order.id.substring(0, order.id.length.clamp(0, 6))}',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (order.customerName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        order.customerName!,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    if (order.itemsSummary != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        order.itemsSummary!,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                '${_formatWon(order.totalAmount)}원',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          // ── 하단: 액션 버튼 (전이 가능한 상태일 때만) ───────
          if (canAdvance || canCancel) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (canCancel)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isProcessing
                          ? null
                          : () => _onCancelOrderTap(order),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('취소'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(color: AppColors.error.withAlpha(80)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                if (canCancel && canAdvance) const SizedBox(width: 8),
                if (canAdvance)
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: isProcessing
                          ? null
                          : () => _onAdvanceStatusTap(order),
                      icon: isProcessing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: Text(nextLabel),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── 상태 전이 액션 ──────────────────────────────────────
  // PAID → PREPARING → READY → COMPLETED 단계만 허용.
  // PATCH /pos/orders/:id/status 호출 후 즉시 _fetchAll() 로 반영
  // (10초 폴링 사이클 기다리지 않도록).
  Future<void> _onAdvanceStatusTap(PosOrder order) async {
    final next = _nextStatus(order.status);
    if (next == null) return;

    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    setState(() => _processingOrderId = order.id);

    final ok = await const PosApiService().updateOrderStatus(
      accessToken: token,
      orderId: order.id,
      status: next,
    );

    if (!mounted) return;
    setState(() => _processingOrderId = null);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_statusLabel(next)} 처리됐어요'),
          duration: const Duration(seconds: 1),
        ),
      );
      await _fetchAll();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('상태 변경에 실패했어요. 다시 시도해 주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ── 주문 취소 액션 ──────────────────────────────────────
  // 사유는 선택. 사유 입력 다이얼로그 표시 → 확인 시 cancelOrder 호출.
  Future<void> _onCancelOrderTap(PosOrder order) async {
    final reason = await _showCancelReasonDialog();
    if (reason == null) return; // 사용자가 취소 다이얼로그 닫음

    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    setState(() => _processingOrderId = order.id);

    final ok = await const PosApiService().cancelOrder(
      accessToken: token,
      orderId: order.id,
      reason: reason.isEmpty ? null : reason,
    );

    if (!mounted) return;
    setState(() => _processingOrderId = null);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('주문이 취소됐어요'),
          duration: Duration(seconds: 1),
        ),
      );
      await _fetchAll();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('주문 취소에 실패했어요. 다시 시도해 주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ── 취소 사유 입력 다이얼로그 ────────────────────────────
  // 자주 쓰는 사유 4종 칩 + 자유 입력. 빈 사유도 허용 (선택 입력).
  // null 반환 = 사용자가 다이얼로그 닫음(작업 취소).
  //
  // controller dispose (2026-05-12 박검토B 긴급):
  //   TextEditingController 를 다이얼로그 안에서 만들고 dispose 안 하면 매 호출마다
  //   메모리 누수. try/finally 로 다이얼로그 종료 시 무조건 dispose 보장.
  Future<String?> _showCancelReasonDialog() async {
    final controller = TextEditingController();
    const presetReasons = ['재료 소진', '조리 불가', '잘못된 주문', '손님 요청'];

    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('주문 취소'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: presetReasons
                    .map((r) => ActionChip(
                          label: Text(r),
                          onPressed: () {
                            controller.text = r;
                          },
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: '취소 사유 (선택)',
                  hintText: '직접 입력하거나 위 버튼 선택',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('닫기'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('취소 처리'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  // ── 상태 전이 규칙 (LSPOS src/lib/utils/status.ts 의 nextStatus 와 동일) ───
  String? _nextStatus(String current) {
    switch (current) {
      case 'PAID':
        return 'PREPARING';
      case 'PREPARING':
        return 'READY';
      case 'READY':
        return 'COMPLETED';
      default:
        // PENDING(결제 전), COMPLETED(서빙 완료), CANCELLED 는 전이 불가
        return null;
    }
  }

  /// 다음 단계 버튼에 표시할 라벨 ("조리 시작", "조리 완료", "픽업 완료")
  String _nextStatusLabel(String current) {
    switch (current) {
      case 'PAID':
        return '조리 시작';
      case 'PREPARING':
        return '조리 완료';
      case 'READY':
        return '픽업 완료';
      default:
        return '';
    }
  }

  /// 취소 가능 여부 — PAID/PREPARING 만 취소 허용 (이미 픽업 완료된 주문은 환불 절차 별도)
  bool _isCancellable(String current) {
    return current == 'PAID' || current == 'PREPARING';
  }

  // ── 주문 상태 라벨/색상 (LSPOS의 STATUS_LABEL 한글 정렬과 동일) ───
  String _statusLabel(String status) {
    switch (status) {
      case 'PENDING':
        return '결제 대기';
      case 'PAID':
        return '신규 주문';
      case 'PREPARING':
        return '조리 중';
      case 'READY':
        return '조리 완료';
      case 'COMPLETED':
        return '서빙 완료';
      case 'CANCELLED':
        return '취소됨';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'PAID':
        return AppColors.warning;
      case 'PREPARING':
        return Theme.of(context).colorScheme.primary;
      case 'READY':
        return AppColors.success;
      case 'COMPLETED':
        return AppColors.textSecondary;
      case 'CANCELLED':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  // 1234567 → "1,234,567"
  String _formatWon(int amount) {
    final s = amount.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
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
