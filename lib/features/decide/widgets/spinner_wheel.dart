// ══════════════════════════════════════════════════════════
// 파일 역할: 미니게임 결정 화면(decide_screen)의 "룰렛(스피너 휠)" 위젯
//
// 무엇을 하는가?
//   - 후보 식당 N개를 원형으로 N등분하여 화면에 그립니다
//   - "돌리기" 버튼을 누르면 1.5초간 빠르게 돌다가 ease-out 으로 멈춥니다
//   - 멈춘 위치(상단 화살표가 가리키는 sector)에 해당하는 식당을
//     onResult 콜백으로 부모(DecideScreen)에 알려줍니다
//
// 왜 CustomPainter 인가?
//   - 사다리/룰렛 같은 게임은 Flutter 기본 위젯으로 그릴 수 없는
//     원형 도넛/부채꼴 그래픽이 필요합니다
//   - asset(이미지/SVG) 추가 없이 코드만으로 그리기 위해 CustomPainter 사용
//
// 색상은 모두 디자인 토큰(CustomerColors / AppColors)에서만 가져옵니다.
// → 캡스톤 가이드라인: "색상 변경 금지, 토큰만 사용"
//
// 의존성: dart:math (랜덤 각도, 회전 보간), 외부 패키지 없음
// ══════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';

/// 스피너 휠 위젯
///
/// 부모(DecideScreen)는 후보 라벨 리스트(`labels`)만 넘겨주면 됩니다.
/// 위젯 외부에서 "다시 돌리기"를 요청할 수 있도록 [SpinnerWheelController] 를
/// 선택적으로 받을 수 있습니다.
class SpinnerWheel extends StatefulWidget {
  const SpinnerWheel({
    super.key,
    required this.labels,
    required this.onResult,
    this.controller,
  });

  /// 룰렛에 표시할 식당 이름(또는 짧은 라벨) 목록
  ///
  /// - 1개 이하면 의미가 없으므로 부모가 미리 2개 이상으로 걸러서 넘긴다고 가정
  /// - 너무 많으면(7개 초과) 글자가 겹칠 수 있으므로 부모에서 6개로 잘라 넘기길 권장
  final List<String> labels;

  /// 회전이 완전히 멈췄을 때 호출되는 콜백
  ///
  /// [winnerIndex] 는 [labels] 리스트 안에서의 당첨 인덱스입니다.
  final ValueChanged<int> onResult;

  /// 외부에서 "다시 돌리기" 를 트리거할 때 사용하는 컨트롤러(선택)
  final SpinnerWheelController? controller;

  @override
  State<SpinnerWheel> createState() => _SpinnerWheelState();
}

/// 룰렛 외부 제어용 컨트롤러
///
/// DecideScreen 에서 "다시 돌리기" 버튼을 눌렀을 때 위젯 내부 함수를
/// 직접 호출할 수 있도록 메서드 핸들만 보관합니다.
class SpinnerWheelController {
  VoidCallback? _spinHandler;

  /// State 가 자기 자신을 등록할 때 사용 (외부에서는 호출하지 말 것)
  void _attach(VoidCallback handler) {
    _spinHandler = handler;
  }

  /// State 가 dispose 될 때 연결 해제
  void _detach() {
    _spinHandler = null;
  }

  /// "다시 돌리기" — 부모(DecideScreen) 가 호출
  void spin() => _spinHandler?.call();
}

class _SpinnerWheelState extends State<SpinnerWheel>
    with SingleTickerProviderStateMixin {
  // 회전 애니메이션 컨트롤러
  //   - 1500ms 동안 ease-out curve 로 회전각이 보간됨
  //   - 0.0 → 1.0 의 값이 _totalRotation 라디안으로 매핑됨
  late final AnimationController _controller;

  // 누적 회전 각도(라디안). 매 spin 마다 누적되어 자연스러운 연속 회전을 만듭니다.
  double _rotation = 0.0;

  // 한 번 돌릴 때 추가될 총 회전 각도(라디안)
  // - 기본 4~7바퀴 사이를 무작위로 정해 "어디서 멈출지 예측이 어렵게" 합니다
  double _spinDelta = 0.0;

  // 회전 중인지 여부 (UI 에서 버튼 잠금에 사용)
  bool _isSpinning = false;

  // 회전 결과를 결정할 때 사용하는 난수 생성기
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..addStatusListener(_handleAnimationStatus);

    // 외부 컨트롤러(있는 경우) 와 spin 핸들러 연결
    widget.controller?._attach(_spin);
  }

  @override
  void didUpdateWidget(covariant SpinnerWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 컨트롤러 인스턴스가 바뀌었으면 다시 연결
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(_spin);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _controller.dispose();
    super.dispose();
  }

  // 애니메이션 상태가 "완료" 로 바뀌면 결과 계산 후 부모에게 통보
  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    // 회전이 끝난 시점에 누적 각도를 먼저 확정한다.
    // (빌더의 _rotation 갱신은 setState 기반이라 다음 프레임에 일어나므로,
    //  여기서 직접 더해주지 않으면 _computeWinnerIndex 가 이번 회전(_spinDelta)이
    //  반영되지 않은 "이전 각도"를 읽어 → 휠 그림과 다른 식당이 당첨으로 통보된다.
    //  첫 회전은 항상 index 0 으로 찍히던 버그의 원인.)
    _rotation = (_rotation + _spinDelta) % (2 * math.pi);
    _spinDelta = 0;
    setState(() => _isSpinning = false);
    widget.onResult(_computeWinnerIndex());
  }

  // 현재 회전각으로부터 상단 화살표가 가리키는 sector index 계산
  //
  // 화살표는 위쪽(12시 방향)에 고정. 휠은 시계방향으로 회전한다고 가정.
  // sector 0 의 중심이 처음에는 12시 방향에 있다고 정의하고, 회전한 만큼
  // 거꾸로 보정하여 어느 sector 가 현재 12시에 위치하는지 계산합니다.
  int _computeWinnerIndex() {
    final n = widget.labels.length;
    if (n == 0) return 0;
    final sectorAngle = (2 * math.pi) / n;

    // 0 ~ 2π 범위로 정규화
    final normalized = _rotation % (2 * math.pi);

    // 회전 방향과 반대로 보정한 후 sector 인덱스로 변환
    // (휠이 시계방향으로 θ 만큼 돌면, 12시 방향에 도달하는 sector 는
    //  시작점에서 시계반대방향으로 θ 만큼 이동한 위치의 sector)
    final pointer = (2 * math.pi - normalized) % (2 * math.pi);
    final idx = (pointer / sectorAngle).floor() % n;
    return idx;
  }

  // 룰렛 돌리기 시작
  void _spin() {
    if (_isSpinning) return; // 이미 회전 중이면 무시
    if (widget.labels.isEmpty) return;

    // 4~7바퀴(=8π~14π) 사이 + 부분 회전 0~2π 의 무작위 추가 각도
    final fullTurns = 4 + _random.nextInt(4); // 4, 5, 6, 7
    final extra = _random.nextDouble() * 2 * math.pi;
    _spinDelta = fullTurns * 2 * math.pi + extra;

    setState(() => _isSpinning = true);
    _controller
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 휠 본체 + 상단 고정 화살표 ──────────────────────
        // Stack 으로 휠 위에 화살표를 겹쳐 놓고, 휠만 회전시킵니다
        SizedBox(
          width: 280,
          height: 280,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  // ease-out curve 로 자연스럽게 멈추도록 보간
                  final t = Curves.easeOut.transform(_controller.value);
                  // 누적값(_rotation) 확정은 _handleAnimationStatus 에서 처리한다.
                  // 여기서 갱신하면 당첨 계산보다 한 프레임 늦게 반영돼
                  // 결과가 한 박자 밀리므로 의도적으로 하지 않는다.
                  final currentAngle = _rotation + _spinDelta * t;
                  return Transform.rotate(
                    angle: currentAngle,
                    child: CustomPaint(
                      size: const Size(280, 280),
                      painter: _WheelPainter(labels: widget.labels),
                    ),
                  );
                },
              ),
              // 상단 화살표(▼) — 12시 방향에 고정
              Positioned(
                top: 0,
                child: _PointerArrow(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // ── 돌리기 버튼 ────────────────────────────────────
        // 회전 중에는 비활성화하여 중복 호출 방지
        SizedBox(
          width: 200,
          height: 52,
          child: ElevatedButton(
            onPressed: _isSpinning ? null : _spin,
            style: ElevatedButton.styleFrom(
              backgroundColor: CustomerColors.primary,
              foregroundColor: AppColors.background,
              disabledBackgroundColor: AppColors.disabled,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
            child: Text(
              _isSpinning ? '돌리는 중…' : '돌리기!',
              style: AppTextStyles.buttonLarge.copyWith(
                color: AppColors.background,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// 휠 본체를 캔버스에 그리는 Painter
//
// 각 sector 의 색상은 디자인 토큰 4종(primary/primaryDark/primaryLight/
// secondary) 을 순환 사용합니다. 사장님이 추가로 토큰을 더 정의하면
// 이 리스트에 추가하기만 하면 됩니다.
// ─────────────────────────────────────────────────────────
class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.labels});

  final List<String> labels;

  // 디자인 토큰에서만 가져온 sector 색상 팔레트
  // (사장님 가이드: 색상 변경 금지)
  static const List<Color> _sectorColors = <Color>[
    CustomerColors.primary,
    CustomerColors.primaryLight,
    CustomerColors.secondary,
    CustomerColors.primaryDark,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n == 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final sectorAngle = (2 * math.pi) / n;

    // sector 별로 부채꼴(arc) + 라벨 그리기
    for (var i = 0; i < n; i++) {
      // 시작각: -π/2 + i * sectorAngle (12시 방향이 sector 0 의 시작점)
      final startAngle = -math.pi / 2 + i * sectorAngle;
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = _sectorColors[i % _sectorColors.length];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sectorAngle,
        true, // useCenter: true 면 부채꼴
        paint,
      );

      // sector 경계선(살짝 진하게)
      final divider = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.surface;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sectorAngle,
        true,
        divider,
      );

      // 라벨 그리기 — sector 중심 각도 위치에 글자 배치
      final labelAngle = startAngle + sectorAngle / 2;
      final labelRadius = radius * 0.62; // 중심에서 약간 바깥쪽에 위치
      final labelOffset = Offset(
        center.dx + labelRadius * math.cos(labelAngle),
        center.dy + labelRadius * math.sin(labelAngle),
      );

      // 글자가 너무 길면 잘라서 표기(겹침 방지)
      final raw = labels[i];
      final display = raw.length > 6 ? '${raw.substring(0, 5)}…' : raw;

      final tp = TextPainter(
        text: TextSpan(
          text: display,
          style: const TextStyle(
            color: AppColors.background, // 흰색 → 가독성
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: radius * 0.7);

      // 글자가 라벨 위치 중앙에 오도록 보정
      canvas.save();
      canvas.translate(labelOffset.dx, labelOffset.dy);
      // 각 sector 의 중심 각도에 맞춰 회전시키면 더 자연스러운 느낌
      // (12시 방향에 가까운 sector 는 글자가 거꾸로 뒤집히지 않도록 보정)
      var rot = labelAngle + math.pi / 2;
      // 글자가 거꾸로 보이는 각도(=하단 sector)면 180도 더 돌려 정방향으로
      if (labelAngle > 0 && labelAngle < math.pi) {
        rot += math.pi;
      }
      canvas.rotate(rot);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    // 가운데 흰 원 — 깔끔한 마감
    final hub = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.surface;
    canvas.drawCircle(center, radius * 0.18, hub);

    // 외곽 테두리
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = CustomerColors.primaryDark;
    canvas.drawCircle(center, radius, outline);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.labels != labels;
}

// ─────────────────────────────────────────────────────────
// 상단 고정 화살표(▼)
//
// 휠은 회전하지만 화살표는 12시 방향에 고정되어 있어
// "어느 sector 가 화살표 아래에 멈췄는지" 가 결과가 됩니다.
// ─────────────────────────────────────────────────────────
class _PointerArrow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: CustomPaint(
        painter: _ArrowPainter(),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 아래를 향하는 삼각형(▼) 모양
    final path = Path()
      ..moveTo(size.width / 2, size.height) // 아래 꼭짓점
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.textPrimary;
    canvas.drawPath(path, paint);

    // 살짝 흰 테두리로 강조
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.background;
    canvas.drawPath(path, outline);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
