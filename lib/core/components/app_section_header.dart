import 'package:flutter/material.dart';
import '../theme/theme.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 섹션 헤더 위젯 (heading3 + 부제목 + 우측 액션)
//
// 사용처:
//   - 홈: "오늘의 세션", "AI 추천 식당"
//   - 세션 로비: "초대 코드", "참여한 멤버"
//   - 사장 홈: "오늘 주문", "매출 요약"
//
// 디자인 원칙:
//   - 제목 heading3 (18px, w600) — 모든 섹션 동일
//   - 부제목 caption (선택) — 가벼운 보조 정보
//   - 우측 trailing — "더보기", 카운트, 토글 등
// ══════════════════════════════════════════════════════════

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  /// subtitle 이 있을 때만 렌더링되는 컬럼 행 (null-aware spread 용)
  Widget? _subtitleWidget() {
    if (subtitle == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        subtitle!,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
            vertical: AppSpacing.sm,
          ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.heading3.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                ?_subtitleWidget(),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
