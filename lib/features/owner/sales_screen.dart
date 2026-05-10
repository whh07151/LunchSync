import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../providers/user_provider.dart';
import '../../services/pos_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 사장 매출 통계 화면
//
// 데이터:
//   PosApiService.getStats — GET /api/pos/restaurants/:id/stats
//   현재는 누적 통계 (PosStats) 만 표시. 일/주/월 분리 + 결제수단별은
//   POS_DEV_LOG 백엔드 협의 #9b 추가 후 보강.
//
// 갱신:
//   30초 폴링 + pull-to-refresh.
// ══════════════════════════════════════════════════════════

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  static const _api = PosApiService();
  static const Duration _pollInterval = Duration(seconds: 30);

  PosStats? _stats;
  bool _isLoading = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _pollTimer = Timer.periodic(_pollInterval, (_) => _load());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final user = ref.read(userProvider);
    final token = user.accessToken;
    final restaurantId = user.restaurantId;
    if (token == null || restaurantId == null) return;

    setState(() => _isLoading = true);
    final stats = await _api.getStats(
      accessToken: token,
      restaurantId: restaurantId,
    );
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final hasRestaurant =
        user.restaurantId != null && user.restaurantId!.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      appBar: AppBar(
        title: const Text('매출 통계'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: !hasRestaurant
          ? _buildPending()
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildRevenueCard(),
                    const SizedBox(height: AppSpacing.md),
                    _buildStatusGrid(),
                    const SizedBox(height: AppSpacing.md),
                    _buildHint(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPending() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          '매장 매핑이 완료되면 매출 통계를 볼 수 있어요.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildRevenueCard() {
    final primary = Theme.of(context).colorScheme.primary;
    final s = _stats;
    final revenue = s?.totalRevenue ?? 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, primary.withAlpha(180)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                '누적 매출',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.white.withAlpha(220),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_isLoading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatWon(revenue)}원',
            style: AppTextStyles.heading1.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 32,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${s?.completedCount ?? 0}건 완료 · ${s?.cancelledCount ?? 0}건 취소',
            style: AppTextStyles.caption
                .copyWith(color: Colors.white.withAlpha(200)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusGrid() {
    final s = _stats;
    final cells = [
      _StatusCell('결제 대기', s?.pendingCount ?? 0,
          Icons.hourglass_top_rounded, AppColors.textSecondary),
      _StatusCell('신규 주문', s?.paidCount ?? 0,
          Icons.notifications_active_rounded, AppColors.warning),
      _StatusCell('조리 중', s?.preparingCount ?? 0,
          Icons.local_fire_department_rounded,
          Theme.of(context).colorScheme.primary),
      _StatusCell('조리 완료', s?.readyCount ?? 0,
          Icons.check_circle_rounded, AppColors.success),
      _StatusCell('서빙 완료', s?.completedCount ?? 0,
          Icons.task_alt_rounded, AppColors.textSecondary),
      _StatusCell('취소됨', s?.cancelledCount ?? 0,
          Icons.cancel_rounded, AppColors.error),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.05,
      children: cells.map(_buildStatusTile).toList(),
    );
  }

  Widget _buildStatusTile(_StatusCell cell) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(cell.icon, color: cell.color, size: 22),
          const SizedBox(height: 4),
          Text(
            '${cell.count}',
            style: AppTextStyles.heading2.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            cell.label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHint() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '일/주/월 분리 + 결제수단별 매출은 다음 단계에서 추가됩니다.',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  String _formatWon(int amount) {
    final s = amount.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _StatusCell {
  const _StatusCell(this.label, this.count, this.icon, this.color);
  final String label;
  final int count;
  final IconData icon;
  final Color color;
}
