import 'package:flutter/material.dart';
import '../theme/theme.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 공통 빈 상태(empty state) 위젯
//
// 사용 시점:
//   - 데이터 0건일 때 사용자에게 친절한 안내 + 다음 행동 제안
//
// 디자인 원칙 (디자이너 가이드 P0):
//   - 단순한 아이콘 + heading3 제목 + bodySmall 설명 + 선택적 CTA
//   - 모든 픽셀/색상은 AppSpacing / AppColors / AppTextStyles 토큰만 사용
//   - 톤: 친근체("~해요", "~할까요?") — 행동 제안형
//
// 예시:
//   AppEmptyState(
//     icon: Icons.restaurant_menu,
//     title: '아직 점심 세션이 없어요',
//     description: '첫 점심을 함께할 친구를 초대해볼까요?',
//     actionLabel: '점심 만들기',
//     onAction: _createSession,
//   )
// ══════════════════════════════════════════════════════════

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.padding,
  });

  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.backgroundGrey,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 36,
              color: AppColors.iconInactive,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: AppTextStyles.heading3.copyWith(
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          if (description != null) ...[
            const SizedBox(height: AppSpacing.xs + 2),
            Text(
              description!,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
