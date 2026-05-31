import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/components/components.dart';
import '../../core/theme/theme.dart';
import '../../providers/user_provider.dart';
import '../../services/pos_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 사장님 "결제 내역" 화면 (OW-10)
//
// 진입:
//   사장 홈 → "결제 내역" 빠른실행 카드 또는 "내정보" 탭 → 결제 내역.
//
// 데이터:
//   GET /api/pos/restaurants/:id/payment-history?dateFrom=&dateTo=
//   (날짜 필터 칩에 따라 dateFrom/dateTo 를 클라이언트에서 계산해 전달)
//
// UI 구성:
//   1) AppBar — "결제 내역" + 새로고침
//   2) 날짜 필터 칩 가로 스크롤 — 오늘 / 어제 / 주간 / 월간
//   3) 합계 카드 — 누적 매출 (환불 차감 반영) + 결제수단별 mini breakdown
//   4) 결제 내역 리스트
//      · 주문번호 + 시각(HH:mm) + 손님명
//      · 금액(우측 상단) + 결제수단 칩(TOSS/CARD/CASH/SIMULATE)
//      · 상태 칩 (PAID/REFUNDED/...)
//      · 환불 토글 버튼 (REFUNDED 가 아닌 항목에만 노출)
//
// 환불 토글:
//   POST /api/pos/orders/:id/refund-sim — 실제 토스 cancel API 호출 없이
//   status 만 REFUNDED 로 변경. 시연/데모 용도.
//   확인 다이얼로그 → 호출 → 성공 시 _fetch() 로 즉시 갱신 + SnackBar.
//
// 폴링 X — 사장 홈은 10초 폴링이지만 결제 내역은 회고성 화면이라 새로고침 only.
// ══════════════════════════════════════════════════════════

/// 날짜 필터 칩 종류.
enum _DateRangeOption { today, yesterday, week, month }

extension _DateRangeOptionExt on _DateRangeOption {
  /// 칩에 표시할 한국어 라벨.
  String get label {
    switch (this) {
      case _DateRangeOption.today:
        return '오늘';
      case _DateRangeOption.yesterday:
        return '어제';
      case _DateRangeOption.week:
        return '최근 7일';
      case _DateRangeOption.month:
        return '최근 30일';
    }
  }

  /// 이 옵션이 의미하는 [dateFrom, dateTo] 쌍을 현재 시각 기준으로 계산.
  /// - 오늘     : 자정 00:00 ~ 현재
  /// - 어제     : 어제 00:00 ~ 오늘 00:00
  /// - 최근 7일 : 7일 전 자정 ~ 현재
  /// - 최근 30일: 30일 전 자정 ~ 현재
  ({DateTime from, DateTime to}) computeRange(DateTime now) {
    final todayStart = DateTime(now.year, now.month, now.day);
    switch (this) {
      case _DateRangeOption.today:
        return (from: todayStart, to: now);
      case _DateRangeOption.yesterday:
        final yStart = todayStart.subtract(const Duration(days: 1));
        return (from: yStart, to: todayStart);
      case _DateRangeOption.week:
        return (from: todayStart.subtract(const Duration(days: 7)), to: now);
      case _DateRangeOption.month:
        return (from: todayStart.subtract(const Duration(days: 30)), to: now);
    }
  }
}

class OwnerPaymentsScreen extends ConsumerStatefulWidget {
  const OwnerPaymentsScreen({super.key});

  @override
  ConsumerState<OwnerPaymentsScreen> createState() =>
      _OwnerPaymentsScreenState();
}

class _OwnerPaymentsScreenState extends ConsumerState<OwnerPaymentsScreen> {
  static const _api = PosApiService();

  /// 현재 선택된 날짜 필터 칩 — 기본 "오늘".
  _DateRangeOption _selectedRange = _DateRangeOption.today;

  /// API 응답 — null = 아직 조회 전. 빈 리스트 = 응답은 왔지만 내역 없음.
  List<PosOrder>? _orders;
  bool _isLoading = false;
  String? _loadError;

  /// 환불 시뮬 진행 중인 주문 ID — 중복 클릭 방지 + 버튼 로딩 표시.
  String? _processingOrderId;

  @override
  void initState() {
    super.initState();
    // 첫 진입 시 즉시 1회 조회. 폴링은 안 함 (회고성 화면).
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  // ── 데이터 조회 ──────────────────────────────────────────
  // _selectedRange 가 계산한 [from, to] 를 dateFrom/dateTo 로 전달.
  Future<void> _fetch() async {
    final user = ref.read(userProvider);
    final token = user.accessToken;
    final restaurantId = user.restaurantId;

    // 토큰/매장 매핑 둘 다 있어야 호출 가능. 없으면 빈 상태 표시.
    if (token == null || restaurantId == null || restaurantId.isEmpty) {
      if (mounted) {
        setState(() {
          _orders = const [];
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    final range = _selectedRange.computeRange(DateTime.now());
    try {
      final result = await _api.getPaymentHistory(
        accessToken: token,
        restaurantId: restaurantId,
        dateFrom: range.from,
        dateTo: range.to,
      );
      if (!mounted) return;
      setState(() {
        _orders = result;
        _loadError = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // 폴링 화면이 아니라 한 번 실패하면 그대로 에러 배너 노출.
      setState(() {
        _loadError = '결제 내역을 불러오지 못했어요';
        _isLoading = false;
      });
    }
  }

  // ── 날짜 칩 선택 변경 ───────────────────────────────────
  // 같은 칩 다시 누르면 새로고침 효과로 동작.
  void _onRangeChanged(_DateRangeOption next) {
    setState(() => _selectedRange = next);
    _fetch();
  }

  // ── 환불 토글 액션 ───────────────────────────────────────
  // 확인 다이얼로그 → POST refund-sim → 성공 시 리스트 즉시 갱신.
  Future<void> _onRefundTap(PosOrder order) async {
    final confirmed = await _showRefundConfirmDialog(order);
    if (confirmed != true) return;

    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    setState(() => _processingOrderId = order.id);

    final ok = await _api.refundSim(accessToken: token, orderId: order.id);

    if (!mounted) return;
    setState(() => _processingOrderId = null);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('환불 시뮬을 처리했어요'),
          duration: Duration(seconds: 1),
        ),
      );
      await _fetch();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('환불 시뮬에 실패했어요. 다시 시도해 주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// 환불 토글 확인 다이얼로그.
  /// 사장님이 실수로 누르는 것을 막기 위한 1단계 확인.
  Future<bool?> _showRefundConfirmDialog(PosOrder order) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('환불 시뮬'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 안내 박스 — 실제 환불이 아님을 명확히 안내.
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.info.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.info.withAlpha(60)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      color: AppColors.info, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '실제 토스 환불은 발생하지 않습니다. 매출 차감 시연용입니다.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.info,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '주문 ${order.orderNumber ?? "#${order.id.substring(0, order.id.length.clamp(0, 6))}"}'
              ' (${_formatWon(order.totalAmount)}원)을 환불 처리할까요?',
              style: AppTextStyles.bodyMedium,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('환불 처리'),
          ),
        ],
      ),
    );
  }

  // ── 매출 합계 계산 ───────────────────────────────────────
  // 백엔드 응답에 합계를 따로 받지 않으므로 클라이언트 사이드 합산.
  // - paidTotal : PAID/PREPARING/READY/COMPLETED 의 totalAmount 합
  // - refunded  : REFUNDED + CANCELLED 의 totalAmount 합 (차감 표시)
  // - net       : paidTotal - refunded
  ({int paidTotal, int refunded, int net, Map<String, int> byMethod})
      _computeTotals(List<PosOrder> orders) {
    var paidTotal = 0;
    var refunded = 0;
    final byMethod = <String, int>{};
    for (final o in orders) {
      final isRefund = o.status == 'REFUNDED' || o.status == 'CANCELLED';
      if (isRefund) {
        refunded += o.totalAmount;
      } else {
        paidTotal += o.totalAmount;
        final key = (o.paymentMethod ?? 'SIMULATE').toUpperCase();
        byMethod[key] = (byMethod[key] ?? 0) + o.totalAmount;
      }
    }
    return (
      paidTotal: paidTotal,
      refunded: refunded,
      net: paidTotal - refunded,
      byMethod: byMethod,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      appBar: AppBar(
        title: const Text('결제 내역'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetch,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: _buildRangeChips()),
            SliverToBoxAdapter(child: _buildSummaryCard()),
            if (_loadError != null)
              SliverToBoxAdapter(child: _buildErrorBanner()),
            _buildListSliver(),
          ],
        ),
      ),
    );
  }

  // ── 날짜 필터 칩 가로 스크롤 ────────────────────────────
  Widget _buildRangeChips() {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _DateRangeOption.values.map((opt) {
            final isSelected = _selectedRange == opt;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(opt.label),
                selected: isSelected,
                onSelected: (_) => _onRangeChanged(opt),
                selectedColor: primary.withAlpha(40),
                labelStyle: AppTextStyles.bodySmall.copyWith(
                  color: isSelected ? primary : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  side: BorderSide(
                    color: isSelected ? primary : AppColors.border,
                  ),
                ),
                backgroundColor: AppColors.surface,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── 합계 카드 ────────────────────────────────────────────
  // 누적 매출 (net) 큰 폰트 + 환불 차감 작게 + 결제수단별 mini breakdown.
  Widget _buildSummaryCard() {
    final orders = _orders ?? const [];
    final totals = _computeTotals(orders);
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Container(
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
                Icon(Icons.account_balance_wallet_rounded,
                    color: primary, size: 20),
                const SizedBox(width: 6),
                Text(
                  '${_selectedRange.label} 누적 매출',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 큰 매출 숫자 — 환불 차감 반영된 net 값.
            Text(
              '${_formatWon(totals.net)}원',
              style: AppTextStyles.heading2.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            // 환불 차감 안내 — 0 이면 숨김.
            if (totals.refunded > 0)
              Text(
                '환불 차감 -${_formatWon(totals.refunded)}원',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),

            if (totals.byMethod.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: AppSpacing.sm),
              // 결제수단별 mini breakdown — 한 줄 가로 스크롤.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: totals.byMethod.entries
                      .map((e) => Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: _miniMethodChip(e.key, e.value),
                          ))
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniMethodChip(String method, int amount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _methodLabel(method),
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${_formatWon(amount)}원',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.error.withAlpha(20),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _loadError!,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 리스트 (Sliver) ─────────────────────────────────────
  Widget _buildListSliver() {
    final orders = _orders;

    // 로딩 중 + 데이터 없음 → 로딩 인디케이터.
    if (_isLoading && (orders == null || orders.isEmpty)) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (orders == null || orders.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 80),
          child: AppEmptyState(
            icon: Icons.receipt_long_rounded,
            title: '결제 내역이 없어요',
            description: '선택한 기간에 결제된 주문이 없어요',
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      sliver: SliverList.separated(
        itemCount: orders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _buildPaymentCard(orders[i]),
      ),
    );
  }

  // ── 결제 카드 ────────────────────────────────────────────
  Widget _buildPaymentCard(PosOrder order) {
    final isRefunded =
        order.status == 'REFUNDED' || order.status == 'CANCELLED';
    final statusColor = _statusColor(order.status);
    final statusLabel = _statusLabel(order.status);
    final methodColor = _methodColor(order.paymentMethod);
    final timeLabel = _formatTime(order.createdAt);
    final isProcessing = _processingOrderId == order.id;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isRefunded
              ? AppColors.error.withAlpha(60)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 상단 행: 주문번호 + 시각 + 금액
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          order.orderNumber ??
                              '#${order.id.substring(0, order.id.length.clamp(0, 6))}',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (timeLabel != null)
                          Text(
                            timeLabel,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
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
                  ],
                ),
              ),
              // 금액 (환불이면 취소선 + 회색)
              Text(
                '${_formatWon(order.totalAmount)}원',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: isRefunded
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  decoration: isRefunded ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 칩 행: 결제수단 + 상태 + 환불 버튼
          Row(
            children: [
              // 결제수단 칩
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: methodColor.withAlpha(28),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _methodLabel(order.paymentMethod),
                  style: AppTextStyles.caption.copyWith(
                    color: methodColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // 상태 칩
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              const Spacer(),
              // 환불 버튼 — REFUNDED/CANCELLED 가 아닌 항목에만 노출.
              if (!isRefunded)
                OutlinedButton.icon(
                  onPressed: isProcessing ? null : () => _onRefundTap(order),
                  icon: isProcessing
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.undo_rounded, size: 14),
                  label: const Text('환불 시뮬'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: AppColors.error.withAlpha(80)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 0,
                    ),
                    minimumSize: const Size(0, 30),
                    textStyle: AppTextStyles.caption,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 결제수단 라벨/색상 ──────────────────────────────────
  String _methodLabel(String? method) {
    switch ((method ?? '').toUpperCase()) {
      case 'TOSS':
        return '토스';
      case 'CARD':
        return '카드';
      case 'CASH':
        return '현금';
      case 'SIMULATE':
        return '시뮬';
      default:
        return '기타';
    }
  }

  Color _methodColor(String? method) {
    switch ((method ?? '').toUpperCase()) {
      case 'TOSS':
        return AppColors.info;
      case 'CARD':
        return Theme.of(context).colorScheme.primary;
      case 'CASH':
        return AppColors.success;
      case 'SIMULATE':
        return AppColors.textSecondary;
      default:
        return AppColors.textSecondary;
    }
  }

  // ── 상태 라벨/색상 (owner_home_screen 의 라벨링과 일관) ──
  String _statusLabel(String status) {
    switch (status) {
      case 'PAID':
        return '결제 완료';
      case 'PREPARING':
        return '조리 중';
      case 'READY':
        return '조리 완료';
      case 'COMPLETED':
        return '서빙 완료';
      case 'REFUNDED':
        return '환불';
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
      case 'REFUNDED':
      case 'CANCELLED':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  // ── 포맷 헬퍼 ───────────────────────────────────────────
  // ISO 8601 → "HH:mm" (KST 가정, 단순 substring 으로 시각만 추출).
  // null/파싱실패 시 null 반환.
  String? _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int n) => n < 10 ? '0$n' : '$n';
      return '${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return null;
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
}
