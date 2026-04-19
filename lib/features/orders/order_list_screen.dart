import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../providers/user_provider.dart';
import '../../services/orders_api_service.dart';
import 'order_tracking_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 홈 화면 "주문현황" 탭의 내용 — 오늘 내 주문 목록
//
// 연동: GET /api/orders/today
//
// 동작:
//   - 최초 진입 시 한 번 조회
//   - "새로고침" 버튼으로 수동 갱신
//   - 카드 탭 → CU-20 주문 추적 화면으로 이동
// ══════════════════════════════════════════════════════════

class OrderListScreen extends ConsumerStatefulWidget {
  const OrderListScreen({super.key});

  @override
  ConsumerState<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends ConsumerState<OrderListScreen> {
  static const _api = OrdersApiService();

  List<OrderSummaryDto>? _orders;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, '주문현황');
      _load();
    });
  }

  Future<void> _load() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final list = await _api.getTodayOrders(accessToken: token);
    if (!mounted) return;
    setState(() {
      _orders = list;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildList(),
    );
  }

  Widget _buildList() {
    final orders = _orders ?? const <OrderSummaryDto>[];

    if (orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: AppColors.iconInactive,
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text(
              '오늘 주문 내역이 없어요',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) => _buildCard(orders[i]),
    );
  }

  Widget _buildCard(OrderSummaryDto order) {
    final (label, color) = _statusLabel(order.status);
    return AppCard(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderTrackingScreen(orderId: order.id),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  label,
                  style: AppTextStyles.label.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatTime(order.createdAt),
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '주문번호 ${order.id.substring(0, 8)}',
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatComma(order.totalPrice)}원',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  (String, Color) _statusLabel(String status) {
    switch (status) {
      case 'PENDING':
        return ('결제 대기', Colors.grey);
      case 'PAID':
        return ('결제 완료', Colors.blue);
      case 'PREPARING':
        return ('준비 중', Colors.orange);
      case 'READY':
        return ('픽업 가능', Colors.green);
      case 'COMPLETED':
        return ('완료', Colors.teal);
      case 'CANCELLED':
        return ('취소됨', Colors.red);
      default:
        return (status, Colors.grey);
    }
  }

  // ISO 8601 → "HH:mm" (하루치만 보는 목록이라 시간만 표시)
  String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
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
