import 'package:flutter/material.dart';
import '../theme/theme.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 로딩 / 에러 / 빈 / 정상 4 상태를 한 위젯에서 분기
//
// 사용 패턴:
//   AppStateView(
//     isLoading: _isLoading,
//     errorMessage: _errorMessage,
//     isEmpty: _orders.isEmpty,
//     onRetry: _load,
//     emptyState: const AppEmptyState(
//       icon: Icons.receipt_long_outlined,
//       title: '주문 내역이 없어요',
//       description: '첫 점심 주문을 만들어볼까요?',
//     ),
//     child: _buildOrderList(),
//   )
//
// 디자인 원칙 (디자이너+프론트 에이전트 통합):
//   - 로딩: 스피너 + 라벨
//   - 에러: 친근체 메시지 + "다시 시도" 버튼
//   - 빈: AppEmptyState (호출 측 정의)
//   - 정상: child 위젯 그대로
// ══════════════════════════════════════════════════════════

class AppStateView extends StatelessWidget {
  const AppStateView({
    super.key,
    required this.isLoading,
    this.errorMessage,
    this.isEmpty = false,
    this.onRetry,
    this.emptyState,
    required this.child,
    this.loadingLabel,
  });

  final bool isLoading;
  final String? errorMessage;
  final bool isEmpty;
  final VoidCallback? onRetry;

  /// 빈 상태일 때 표시할 위젯 (보통 AppEmptyState)
  final Widget? emptyState;

  /// 정상 상태 콘텐츠
  final Widget child;

  /// 로딩 중일 때 스피너 아래 표시할 라벨 (예: '주문을 불러오는 중...')
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    // 1) 로딩 (콘텐츠가 아직 없는 첫 진입)
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2.5),
            if (loadingLabel != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                loadingLabel!,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      );
    }

    // 2) 에러
    if (errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 36,
                color: AppColors.error.withAlpha(180),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              errorMessage!,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('다시 시도'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // 3) 빈 상태
    if (isEmpty && emptyState != null) {
      return emptyState!;
    }

    // 4) 정상 콘텐츠
    return child;
  }
}
