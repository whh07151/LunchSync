import 'package:flutter/material.dart';
import '../theme/theme.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 공통 배지 위젯 (상태/카운트 표시)
//
// 사용처:
//   - 세션 상태 ("대기중", "투표중", "주문완료")
//   - 알림 카운트 ("9+")
//   - 추천 카드 점수 배지
//
// 디자인 원칙:
//   - 둥근 모서리 (chip 반경)
//   - 작은 폰트(caption) + w600
//   - tone 으로 색상 분기 (primary/success/warning/error/neutral)
// ══════════════════════════════════════════════════════════

enum AppBadgeTone {
  primary,
  success,
  warning,
  error,
  neutral,
}

class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.tone = AppBadgeTone.primary,
    this.icon,
    this.filled = false,
  });

  final String label;
  final AppBadgeTone tone;
  final IconData? icon;

  /// true 면 배경이 진한 색 + 흰 텍스트, false 면 배경 옅음 + 진한 텍스트
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final (bg, fg) = _resolveColors(primary);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  (Color background, Color foreground) _resolveColors(Color primary) {
    switch (tone) {
      case AppBadgeTone.primary:
        return filled
            ? (primary, Colors.white)
            : (primary.withAlpha(28), primary);
      case AppBadgeTone.success:
        return filled
            ? (AppColors.success, Colors.white)
            : (AppColors.success.withAlpha(28), AppColors.success);
      case AppBadgeTone.warning:
        return filled
            ? (AppColors.warning, Colors.white)
            : (AppColors.warning.withAlpha(28), AppColors.warning);
      case AppBadgeTone.error:
        return filled
            ? (AppColors.error, Colors.white)
            : (AppColors.error.withAlpha(28), AppColors.error);
      case AppBadgeTone.neutral:
        return filled
            ? (AppColors.textSecondary, Colors.white)
            : (AppColors.backgroundGrey, AppColors.textSecondary);
    }
  }
}
