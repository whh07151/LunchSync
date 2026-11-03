import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';

/// 홈 첫 화면에서 오늘 해야 할 일과 보조 동작의 우선순위를 유지한다.
///
/// 휴대전화에서는 세션을 먼저 보여 주고, 넓은 웹 화면에서는 세션과
/// 바로가기를 나란히 배치한다. 실제 데이터와 동작은 부모 화면이 주입한다.
class HomePrimaryLayout extends StatelessWidget {
  const HomePrimaryLayout({
    super.key,
    required this.todaySession,
    required this.quickActions,
  });

  static const double wideBreakpoint = 760;

  final Widget todaySession;
  final Widget quickActions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sessionSection = _HomePrimarySection(
          title: '오늘의 점심 세션',
          child: todaySession,
        );
        final actionSection = _HomePrimarySection(
          title: '바로가기',
          child: quickActions,
        );

        if (constraints.maxWidth >= wideBreakpoint) {
          return Row(
            key: const ValueKey('home-primary-wide'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: sessionSection),
              const SizedBox(width: AppSpacing.xl),
              Expanded(flex: 3, child: actionSection),
            ],
          );
        }

        return Column(
          key: const ValueKey('home-primary-compact'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sessionSection,
            const SizedBox(height: AppSpacing.lg),
            actionSection,
          ],
        );
      },
    );
  }
}

class _HomePrimarySection extends StatelessWidget {
  const _HomePrimarySection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: CustomerColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(title, style: AppTextStyles.heading3),
          ],
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        child,
      ],
    );
  }
}
