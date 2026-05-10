import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../providers/user_provider.dart';
import 'login_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 사장님 가입 후 운영자 승인 대기 안내 화면
//
// 진입 조건:
//   - 로그인/가입 응답의 nextStep == 'OWNER_PENDING'
//   - 또는 OWNER 계정으로 로그인했는데 status == PENDING|REJECTED
//
// 사용자가 할 수 있는 액션:
//   - 로그아웃 (다른 계정으로 다시 로그인)
//
// 운영자가 Supabase 콘솔에서 status='APPROVED'로 변경 후
// 사용자가 다시 로그인하면 OWNER_HOME으로 진입.
// ══════════════════════════════════════════════════════════

class OwnerPendingScreen extends ConsumerWidget {
  const OwnerPendingScreen({super.key});

  // ── 로그아웃 후 로그인 화면으로 ──
  Future<void> _handleLogout(BuildContext context, WidgetRef ref) async {
    await ref.read(userProvider.notifier).clear();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (ctx) => LoginScreen(
          onLoginSuccess: ({required String nextStep}) {
            // 다시 로그인 후의 라우팅은 main.dart의 _handleLoginSuccess가 담당해야 하나,
            // 여기에선 안전한 폴백으로 화면을 다시 그리는 정도만 처리.
            Navigator.of(ctx).pop();
          },
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final primary = Theme.of(context).colorScheme.primary;
    final status = user.status ?? 'PENDING';

    // 거부 상태와 대기 상태에 따라 메시지 분리
    final isRejected = status == 'REJECTED';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          child: Column(
            children: [
              const Spacer(),

              // ── 안내 아이콘 ────────────────────────────
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: (isRejected ? AppColors.error : primary).withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isRejected
                      ? Icons.block_rounded
                      : Icons.hourglass_top_rounded,
                  size: 50,
                  color: isRejected ? AppColors.error : primary,
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              Text(
                isRejected ? '가입이 거부되었어요' : '승인 대기 중이에요',
                style: AppTextStyles.heading2.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                isRejected
                    ? '입력하신 정보로는 사장님 가입이 승인되지 않았어요.\n관리자에게 문의해주세요.'
                    : '사장님 계정은 운영자 승인이 끝나야 활성화돼요.\n승인이 완료되면 다음 로그인부터 사장 화면이 열립니다.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── 가입 정보 요약 카드 ─────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.backgroundGrey,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('이름', user.name ?? '-'),
                    const SizedBox(height: 6),
                    _infoRow('상태', _statusLabel(status)),
                  ],
                ),
              ),

              const Spacer(),

              // ── 로그아웃 버튼 ───────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _handleLogout(context, ref),
                  child: const Text('로그아웃'),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'PENDING':
        return '승인 대기';
      case 'APPROVED':
        return '승인 완료';
      case 'REJECTED':
        return '승인 거부';
      default:
        return status;
    }
  }
}
