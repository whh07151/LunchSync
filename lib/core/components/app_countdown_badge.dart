import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/theme.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 카운트다운 배지 위젯 (시간 임박 시 강조)
//
// 사용처:
//   - 세션 로비: 점심시간까지 남은 시간
//   - 주문 추적: 예상 완료 시간까지
//
// 디자인 원칙 (디자이너 가이드):
//   - 평상시: primarySurface 배경 + primary 텍스트
//   - 5분 이내(urgent): primary 배경 + 흰 텍스트 + 굵게 + 미세 펄스 모션
//   - 지난 시점: success 배경 + "지금이에요!" 메시지
//
// 사용 예:
//   AppCountdownBadge(targetTime: DateTime.parse('2026-05-11T12:30'))
// ══════════════════════════════════════════════════════════

class AppCountdownBadge extends StatefulWidget {
  const AppCountdownBadge({
    super.key,
    required this.targetTime,
    this.icon = Icons.schedule_rounded,
    this.urgentThresholdMinutes = 5,
    this.passedLabel = '지금이에요!',
  });

  /// 카운트다운 대상 시각 (예: 점심시간 12:30)
  final DateTime targetTime;

  /// 표시 아이콘
  final IconData icon;

  /// 이 분 이내일 때 urgent 스타일 적용
  final int urgentThresholdMinutes;

  /// 시간이 지난 후 표시할 라벨
  final String passedLabel;

  @override
  State<AppCountdownBadge> createState() => _AppCountdownBadgeState();
}

class _AppCountdownBadgeState extends State<AppCountdownBadge>
    with SingleTickerProviderStateMixin {
  Timer? _ticker;
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    // 1초마다 갱신
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // 임박 시 펄스 애니메이션 (1초 주기)
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = widget.targetTime.difference(now);
    final primary = Theme.of(context).colorScheme.primary;

    // 시간 지남 → 성공 톤
    if (diff.isNegative) {
      return _buildBadge(
        background: AppColors.success.withAlpha(30),
        foreground: AppColors.success,
        icon: Icons.check_circle_rounded,
        text: widget.passedLabel,
        bold: true,
      );
    }

    final totalSeconds = diff.inSeconds;
    final mm = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (totalSeconds % 60).toString().padLeft(2, '0');
    final hours = diff.inHours;

    final label = hours > 0
        ? '$hours시간 ${diff.inMinutes % 60}분 남음'
        : '$mm:$ss 남음';

    final isUrgent = totalSeconds <= widget.urgentThresholdMinutes * 60;

    if (isUrgent) {
      return AnimatedBuilder(
        animation: _pulse,
        builder: (ctx, child) {
          // 0.85~1.0 범위로 펄스 — 너무 과하지 않게
          final scale = 0.97 + 0.03 * _pulse.value;
          return Transform.scale(
            scale: scale,
            child: _buildBadge(
              background: primary,
              foreground: Colors.white,
              icon: widget.icon,
              text: label,
              bold: true,
            ),
          );
        },
      );
    }

    return _buildBadge(
      background: CustomerColors.primarySurface,
      foreground: primary,
      icon: widget.icon,
      text: label,
      bold: false,
    );
  }

  Widget _buildBadge({
    required Color background,
    required Color foreground,
    required IconData icon,
    required String text,
    required bool bold,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: AppSpacing.xs + 2),
          Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              color: foreground,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
