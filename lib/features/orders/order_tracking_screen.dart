import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../providers/user_provider.dart';
import '../../services/orders_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-20 주문 추적 화면
//
// 폴링 3초 간격으로 주문 상태를 새로고침하여 변화 감지.
// 앱이 백그라운드로 가면 폴링 중단, 포그라운드 복귀 시 재시작.
//
// 주문 상태 흐름:
//   PENDING → PAID → PREPARING → READY → COMPLETED
//   CANCELLED (어느 상태에서든 전이 가능)
//
// 단계별 UI:
//   진행 중 상태(PREPARING, READY 등)는 진행 스텝 바로 표시
//   COMPLETED / CANCELLED는 최종 상태 배지만 표시
// ══════════════════════════════════════════════════════════

class OrderTrackingScreen extends ConsumerStatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen>
    with WidgetsBindingObserver {
  static const _api = OrdersApiService();
  static const _pollInterval = Duration(seconds: 3);

  // 주문 상태 단계 순서 (진행 스텝 바의 인덱스로 사용)
  static const _steps = <String>['PENDING', 'PAID', 'PREPARING', 'READY', 'COMPLETED'];

  OrderDetailDto? _order;
  bool _isLoading = true;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-20');
      _load();
      _startPolling();
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── 앱 생명주기: 백그라운드 진입 시 폴링 중단 (배터리 보호) ──
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _poller?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _load();
      _startPolling();
    }
  }

  // ── 폴링 시작 (기존 타이머가 있으면 재시작) ────────────
  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(_pollInterval, (_) => _load());
  }

  // ── 주문 상세 조회 ─────────────────────────────────────
  Future<void> _load() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    final detail = await _api.getOrderById(
      accessToken: token,
      orderId: widget.orderId,
    );
    if (!mounted) return;
    setState(() {
      _order = detail;
      _isLoading = false;
    });

    // 주문이 최종 상태에 도달하면 폴링 중단 (불필요한 API 호출 회피)
    if (detail != null &&
        (detail.status == 'COMPLETED' || detail.status == 'CANCELLED')) {
      _poller?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(showBack: true, title: '주문 추적'),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _order == null
                ? _buildNotFound()
                : _buildContent(_order!),
      ),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Text(
        '주문 정보를 찾을 수 없어요',
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildContent(OrderDetailDto order) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 현재 상태 배지 + 주문 ID ────────────────────
          _buildStatusHeader(order),
          const SizedBox(height: AppSpacing.md),

          // ── 진행 스텝 바 (CANCELLED 아닐 때만) ──────────
          if (order.status != 'CANCELLED') _buildStepBar(order.status),
          if (order.status != 'CANCELLED')
            const SizedBox(height: AppSpacing.lg),

          // ── 주문 항목 리스트 ────────────────────────────
          Text('주문 내역', style: AppTextStyles.heading3),
          const SizedBox(height: AppSpacing.sm),
          ...order.items.map(_buildItemRow),

          const Divider(height: 32),

          // ── 합계 ────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('합계', style: AppTextStyles.bodyMedium),
              Text(
                '${_formatComma(order.totalPrice)}원',
                style: AppTextStyles.heading3,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // ── 자동 갱신 안내 ─────────────────────────────
          if (order.status != 'COMPLETED' && order.status != 'CANCELLED')
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sync_rounded,
                    size: 14, color: AppColors.textHint),
                const SizedBox(width: 4),
                Text(
                  '3초마다 자동 갱신 중',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── 상태 배지 + 주문 ID ──────────────────────────────
  Widget _buildStatusHeader(OrderDetailDto order) {
    final (label, color) = _statusLabel(order.status);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withAlpha(80)),
      ),
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
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '주문번호 ${order.id.substring(0, 8)}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_statusMessage(order.status), style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }

  // ── 진행 스텝 바 (5단계) ──────────────────────────────
  // 현재 상태의 인덱스까지 주황색, 그 이후는 회색.
  Widget _buildStepBar(String currentStatus) {
    final primary = Theme.of(context).colorScheme.primary;
    final currentIdx = _steps.indexOf(currentStatus);

    return Row(
      children: List.generate(_steps.length, (i) {
        final isDone = i <= currentIdx;
        final isLast = i == _steps.length - 1;

        return Expanded(
          child: Row(
            children: [
              // 스텝 원
              Column(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDone ? primary : AppColors.backgroundGrey,
                      shape: BoxShape.circle,
                    ),
                    child: isDone
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _stepShortLabel(_steps[i]),
                    style: AppTextStyles.caption.copyWith(
                      color: isDone ? primary : AppColors.textHint,
                      fontWeight: isDone ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
              // 연결선
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 18),
                    color: isDone ? primary : AppColors.divider,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  // ── 주문 항목 한 줄 ──────────────────────────────────
  Widget _buildItemRow(OrderItemDetailDto item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.menuName ?? '메뉴',
              style: AppTextStyles.bodyMedium,
            ),
          ),
          Text(
            '× ${item.quantity}',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${_formatComma(item.price * item.quantity)}원',
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── 상태 → 한글 레이블 + 색 ──────────────────────────
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
        return ('주문 완료', Colors.teal);
      case 'CANCELLED':
        return ('취소됨', Colors.red);
      default:
        return (status, Colors.grey);
    }
  }

  // ── 상태 → 안내 메시지 ───────────────────────────────
  String _statusMessage(String status) {
    switch (status) {
      case 'PENDING':
        return '결제가 진행 중이에요.';
      case 'PAID':
        return '결제가 완료됐어요. 식당이 준비를 시작할 거예요.';
      case 'PREPARING':
        return '식당에서 조리 중이에요.';
      case 'READY':
        return '픽업 준비가 끝났어요. 매장에서 받아 가세요!';
      case 'COMPLETED':
        return '주문이 완료됐어요. 맛있게 드셨길 바랄게요!';
      case 'CANCELLED':
        return '주문이 취소됐어요.';
      default:
        return '';
    }
  }

  // 스텝 바에서 보여줄 짧은 레이블
  String _stepShortLabel(String s) {
    switch (s) {
      case 'PENDING':
        return '결제';
      case 'PAID':
        return '결제완료';
      case 'PREPARING':
        return '준비중';
      case 'READY':
        return '픽업';
      case 'COMPLETED':
        return '완료';
      default:
        return s;
    }
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
