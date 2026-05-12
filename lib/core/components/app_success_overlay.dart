import 'dart:math' as math;
import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 결제/주문 성공 시 표시하는 체크마크 + 광선 애니메이션
//
// 디자이너 가이드 #5순위 시연 임팩트:
//   "결제 성공 시 폭죽 또는 체크 애니메이션"
//
// 모션 구성 (1.5초):
//   0.0~0.4s — primary 원형이 0에서 100%로 scale + 회전 살짝
//   0.3~0.7s — 안쪽 체크마크가 0에서 1.2배로 튀어나옴 (elasticOut)
//   0.5~1.5s — 8방향 광선이 바깥으로 fade out (성공의 시각적 폭발)
//
// 사용:
//   AppSuccessOverlay(size: 120) — Stack/Column 안에 배치
//   외부 패키지(confetti 등) 의존성 없이 순수 Flutter 위젯으로 구현
// ══════════════════════════════════════════════════════════

class AppSuccessOverlay extends StatefulWidget {
  const AppSuccessOverlay({
    super.key,
    this.size = 120,
    this.duration = const Duration(milliseconds: 1500),
    this.color,
  });

  /// 전체 영역 크기 (정사각형). 체크 원은 size의 60% 정도 차지.
  final double size;
  final Duration duration;

  /// null 이면 Theme.colorScheme.primary 사용
  final Color? color;

  @override
  State<AppSuccessOverlay> createState() => _AppSuccessOverlayState();
}

class _AppSuccessOverlayState extends State<AppSuccessOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _circleScale;
  late final Animation<double> _checkScale;
  late final Animation<double> _raysProgress;
  late final Animation<double> _raysFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    // 원형 등장 (0~40%)
    _circleScale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
    );

    // 체크마크 등장 (30~70%) — elasticOut 으로 "탕!" 하고 튀어나오는 느낌
    _checkScale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 0.7, curve: Curves.elasticOut),
    );

    // 광선 외곽 진행 (50~100%)
    _raysProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
    );

    // 광선 페이드 아웃 (60~100%)
    _raysFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.6, 1.0, curve: Curves.easeIn),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final size = widget.size;
    final circleSize = size * 0.6;

    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (ctx, _) {
          return CustomPaint(
            painter: _RaysPainter(
              progress: _raysProgress.value,
              fade: 1 - _raysFade.value,
              color: color,
            ),
            child: Center(
              child: Transform.scale(
                scale: _circleScale.value,
                child: Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withAlpha(80),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Transform.scale(
                      scale: _checkScale.value,
                      child: Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: circleSize * 0.55,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── 8방향 광선 페인터 — 원 바깥으로 짧은 선이 퍼짐 ────────
// progress 0→1 진행됨에 따라 광선이 바깥쪽으로 이동
// fade 1→0 으로 점차 사라짐
class _RaysPainter extends CustomPainter {
  _RaysPainter({
    required this.progress,
    required this.fade,
    required this.color,
  });

  final double progress;
  final double fade;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || fade <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final innerRadius = size.width * 0.32; // 원 외곽
    final outerRadius = size.width * 0.5 * progress; // 광선 끝점
    final paint = Paint()
      ..color = color.withAlpha((fade * 255).toInt())
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // 8방향
    for (int i = 0; i < 8; i++) {
      final angle = (math.pi * 2 * i) / 8;
      final start = Offset(
        center.dx + math.cos(angle) * innerRadius,
        center.dy + math.sin(angle) * innerRadius,
      );
      final end = Offset(
        center.dx + math.cos(angle) * outerRadius,
        center.dy + math.sin(angle) * outerRadius,
      );
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.fade != fade ||
      oldDelegate.color != color;
}
