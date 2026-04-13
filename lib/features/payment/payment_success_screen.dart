import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/cart_provider.dart';
import '../../services/payments_api_service.dart';
import '../home/home_screen.dart';
import 'payment_web_bridge.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-19 결제 성공 화면 + 최종 승인 호출
//
// 진입 경로:
//   토스 결제위젯(web/toss-checkout.html) → successUrl 로
//   http://localhost:8080/?paymentStatus=success&paymentKey=...&orderId=...&amount=...
//   형태로 리다이렉트되어 Flutter 앱이 재기동됨.
//   main.dart 의 _RootNavigator 가 쿼리를 감지해 이 화면으로 진입.
//
// 하는 일:
//   1) sessionStorage 에서 JWT 복원 (userProvider 에 다시 주입)
//   2) /api/payments/confirm 호출 — 백엔드가 토스에 최종 승인 요청
//   3) 성공 시 장바구니 비우기 + "홈으로" 버튼 활성화
//   4) 실패 시 에러 메시지 노출 + "다시 시도" 버튼
//
// 주의:
//   결제 후 페이지가 완전히 새로 로드되므로 Riverpod 상태가 초기화됨.
//   JWT 는 sessionStorage 에서 복원, 그 외 상태는 홈 화면 다시 진입 시
//   일반 흐름대로 재조회.
// ══════════════════════════════════════════════════════════

class PaymentSuccessScreen extends ConsumerStatefulWidget {
  const PaymentSuccessScreen({
    super.key,
    required this.paymentKey,
    required this.orderId,
    required this.amount,
  });

  /// 토스가 발급한 결제 고유 키 (URL 쿼리에서 추출)
  final String paymentKey;

  /// 우리 서버의 주문 UUID (URL 쿼리에서 추출)
  final String orderId;

  /// 결제 금액 (URL 쿼리에서 추출)
  final int amount;

  @override
  ConsumerState<PaymentSuccessScreen> createState() =>
      _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends ConsumerState<PaymentSuccessScreen> {
  final PaymentsApiService _paymentsApi = const PaymentsApiService();

  // 승인 호출 상태
  bool _isConfirming = true;
  bool _confirmed = false;
  String? _errorMessage;
  String? _method;      // 토스가 알려준 결제수단
  String? _approvedAt;  // 승인 시각

  @override
  void initState() {
    super.initState();
    // 빌드 이후 호출 (setState 타이밍)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confirmPayment();
    });
  }

  // ── 백엔드 /api/payments/confirm 호출 ─────────────────
  Future<void> _confirmPayment() async {
    // sessionStorage 에서 JWT 복원
    // 정상 흐름: OrderReviewScreen 이 리다이렉트 직전에 저장해둔 값
    final savedJwt = PaymentWebBridge.getSessionItem('ls_jwt');
    if (savedJwt == null || savedJwt.isEmpty) {
      setState(() {
        _isConfirming = false;
        _errorMessage =
            '로그인 정보가 만료되었습니다.\n홈으로 돌아가 다시 로그인해주세요.';
      });
      return;
    }

    // userProvider 에 JWT 복원 (다른 API 호출이 뒤이어 일어날 경우 대비)
    // NOTE: setUser 는 AuthResponse 를 받으므로 여기서는 직접 주입 불가.
    //       confirm API 호출에만 accessToken 을 직접 넘긴다.

    final result = await _paymentsApi.confirmPayment(
      accessToken: savedJwt,
      paymentKey: widget.paymentKey,
      orderId: widget.orderId,
      amount: widget.amount,
    );

    if (result == null) {
      setState(() {
        _isConfirming = false;
        _errorMessage =
            '결제 승인에 실패했습니다.\n고객센터에 문의해주세요. (주문번호: ${widget.orderId})';
      });
      return;
    }

    // 승인 성공: 장바구니 비우기 + 주문 관련 sessionStorage 만 정리
    // ⚠️ ls_jwt / ls_user_* 는 그대로 유지 (로그인 상태 유지용).
    //    _RootNavigator 가 앱 재기동 시 이 값으로 userProvider 를 복원합니다.
    //    실제 로그아웃 시에만 이 값들을 제거합니다.
    ref.read(cartProvider.notifier).clear();
    PaymentWebBridge.removeSessionItem('ls_order_id');
    PaymentWebBridge.removeSessionItem('ls_order_amount');
    PaymentWebBridge.removeSessionItem('ls_order_name');
    // 주소창에서 결제 쿼리 제거 (뒤로가기 시 재호출 방지)
    PaymentWebBridge.clearQueryParams();

    setState(() {
      _isConfirming = false;
      _confirmed = true;
      _method = result.method;
      _approvedAt = result.approvedAt;
    });
  }

  // ── "홈으로" 버튼 핸들러 ─────────────────────────────
  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 상태 아이콘 ────────────────────────────
              Icon(
                _isConfirming
                    ? Icons.hourglass_empty_rounded
                    : (_confirmed
                        ? Icons.check_circle_rounded
                        : Icons.error_rounded),
                size: 96,
                color: _isConfirming
                    ? AppColors.textSecondary
                    : (_confirmed ? primary : const Color(0xFFD4351C)),
              ),
              const SizedBox(height: 24),

              // ── 상태 텍스트 ────────────────────────────
              Text(
                _isConfirming
                    ? '결제를 확인하는 중입니다...'
                    : (_confirmed ? '결제가 완료되었습니다' : '결제 승인 실패'),
                textAlign: TextAlign.center,
                style: AppTextStyles.heading2,
              ),

              if (_confirmed) ...[
                const SizedBox(height: 12),
                Text(
                  '${_formatPrice(widget.amount)}원 결제 완료',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (_method != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '결제수단: $_method',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                if (_approvedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '승인시각: $_approvedAt',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color(0xFFD4351C),
                  ),
                ),
              ],

              const SizedBox(height: 40),

              // ── 액션 버튼 ──────────────────────────────
              if (!_isConfirming)
                AppPrimaryButton(
                  label: _confirmed ? '홈으로' : '홈으로 돌아가기',
                  onPressed: _goHome,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPrice(int price) {
    final parts = <String>[];
    var n = price;
    while (n >= 1000) {
      parts.insert(0, (n % 1000).toString().padLeft(3, '0'));
      n ~/= 1000;
    }
    parts.insert(0, n.toString());
    return parts.join(',');
  }
}
