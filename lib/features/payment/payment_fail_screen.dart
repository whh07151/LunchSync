import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../home/home_screen.dart';
import 'payment_web_bridge.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-19 결제 실패 화면
//
// 진입 경로:
//   토스 결제위젯이 failUrl 로 리다이렉트:
//     http://localhost:8080/?paymentStatus=fail&code=...&message=...&orderId=...
//   main.dart 의 _RootNavigator 가 쿼리를 감지해 이 화면으로 진입.
//
// 하는 일:
//   - 토스가 내려준 실패 사유(code/message) 를 그대로 노출
//   - sessionStorage 에 남은 임시 상태(JWT/orderId 등) 정리
//   - "홈으로 돌아가기" 버튼으로 복귀
//
// 주의:
//   결제 실패는 서버 주문 레코드가 PENDING 상태로 남아있을 수 있음.
//   (토스 승인이 안 되었으므로 PAID 가 되지 않은 상태)
//   운영 시에는 cron 이나 cleanup job 으로 PENDING 주문을 정리해야 함.
// ══════════════════════════════════════════════════════════

class PaymentFailScreen extends StatelessWidget {
  const PaymentFailScreen({
    super.key,
    this.code,
    this.message,
    this.orderId,
  });

  /// 토스가 내려준 실패 코드 (예: PAY_PROCESS_CANCELED)
  final String? code;

  /// 토스가 내려준 실패 메시지 (한국어)
  final String? message;

  /// 우리 서버 주문 UUID (있을 경우)
  final String? orderId;

  // ── "홈으로 돌아가기" 핸들러 ──────────────────────────
  void _goHome(BuildContext context) {
    // 주문 관련 sessionStorage 만 정리
    // ⚠️ ls_jwt / ls_user_* 는 그대로 유지 (로그인 상태 유지).
    PaymentWebBridge.removeSessionItem('ls_order_id');
    PaymentWebBridge.removeSessionItem('ls_order_amount');
    PaymentWebBridge.removeSessionItem('ls_order_name');
    PaymentWebBridge.clearQueryParams();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.cancel_rounded,
                size: 96,
                color: Color(0xFFD4351C),
              ),
              const SizedBox(height: 24),

              Text(
                '결제가 취소되었습니다',
                textAlign: TextAlign.center,
                style: AppTextStyles.heading2,
              ),

              const SizedBox(height: 12),

              Text(
                message ?? '결제가 완료되지 않았습니다. 다시 시도해주세요.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),

              if (code != null) ...[
                const SizedBox(height: 8),
                Text(
                  '(사유 코드: $code)',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],

              if (orderId != null) ...[
                const SizedBox(height: 4),
                Text(
                  '주문번호: $orderId',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],

              const SizedBox(height: 40),

              AppPrimaryButton(
                label: '홈으로 돌아가기',
                onPressed: () => _goHome(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
