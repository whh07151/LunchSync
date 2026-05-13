// ══════════════════════════════════════════════════════════
// 파일 역할: 미니게임 결정 화면의 "사다리 게임" 위젯
//
// 동작 방식:
//   1. 후보 N개를 사다리 윗줄에 배치(예: ① ② ③ ④)
//   2. 아래줄에는 ❌ N-1개 + ✅ 1개 가 무작위 위치에 배치됨
//   3. 사용자가 윗줄에서 한 칸을 탭하면, 사다리 가로선을 따라 내려가는
//      경로가 애니메이션으로 그려지고, 도달한 아래줄 칸이 결과가 됨
//   4. ✅ 칸에 도달한 윗줄 후보의 인덱스가 winner → 부모에게 통보
//
// 왜 간단하게 구현?
//   - 시연 시 5초 안에 결과가 나와야 임팩트가 좋음
//   - 4~6명 케이스(점심 자율 모임 평균)에 최적화
//
// 색상은 디자인 토큰만 사용. asset 추가 없음.
// 의존성: dart:math (가로선 랜덤 배치), 외부 패키지 없음
// ══════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';

/// 사다리 게임 위젯
///
/// [labels] 길이만큼 세로줄을 그리고, 그 중 winner 위치에 ✅를 둡니다.
class LadderGame extends StatefulWidget {
  const LadderGame({
    super.key,
    required this.labels,
    required this.onResult,
    this.controller,
  });

  /// 사다리 윗줄에 배치할 후보 라벨 목록
  final List<String> labels;

  /// 사다리가 내려가는 경로가 완료됐을 때 호출되는 콜백
  ///
  /// [winnerIndex] 는 [labels] 안에서의 당첨 인덱스입니다.
  final ValueChanged<int> onResult;

  /// 외부에서 "다시 시작" 을 트리거하는 컨트롤러(선택)
  final LadderGameController? controller;

  @override
  State<LadderGame> createState() => _LadderGameState();
}

/// 사다리 외부 제어용 컨트롤러
///
/// "다시 시작" 시 사다리 배치를 새로 무작위로 만들 때 사용.
class LadderGameController {
  VoidCallback? _resetHandler;

  void _attach(VoidCallback handler) {
    _resetHandler = handler;
  }

  void _detach() {
    _resetHandler = null;
  }

  /// 사다리를 다시 무작위로 생성
  void reset() => _resetHandler?.call();
}

class _LadderGameState extends State<LadderGame>
    with SingleTickerProviderStateMixin {
  // 가로선(rung) 데이터
  //   - 각 행(row) 마다 어느 열(column) 쌍 사이에 가로선이 있는지 저장
  //   - _rungs[row] = {col,  col+1 ... } 형태로 인접한 col 들의 집합
  //   - 한 행에서 같은 열에 가로선이 두 개 닿지 않도록 생성
  List<Set<int>> _rungs = const [];

  // 사다리 행(row) 개수 — 후보 수가 적어도 충분히 사다리 느낌이 나도록
  // 최소 6 ~ 최대 9 사이로 고정
  static const int _rowCount = 8;

  // 당첨 위치(아래줄에서 ✅ 가 있는 열 인덱스)
  int _winnerColumn = 0;

  // 사용자가 선택한 윗줄 열 인덱스 (-1: 미선택)
  int _selectedColumn = -1;

  // 추적 애니메이션 컨트롤러 — 사다리 따라 내려가는 점이 0.0 → 1.0 진행
  late final AnimationController _trace;

  // 추적 경로 (각 step 의 좌표 = 격자 좌표)
  // 각 좌표는 (col, row) 의 row 가 0.0 ~ _rowCount.toDouble() 범위
  List<Offset> _path = const [];

  final math.Random _random = math.Random();

  // 추적이 끝나서 결과가 표시되어야 하는지 여부
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _trace = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..addStatusListener(_handleTraceStatus);

    _generateBoard();
    widget.controller?._attach(_reset);
  }

  @override
  void didUpdateWidget(covariant LadderGame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(_reset);
    }
    // 후보 개수가 변하면 보드 재생성
    if (oldWidget.labels.length != widget.labels.length) {
      _reset();
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _trace.dispose();
    super.dispose();
  }

  // 사다리 보드(가로선) 무작위 생성
  //
  // - 각 행마다 인접 열 사이에 가로선을 둘지 0.45 확률로 결정
  // - 단, 같은 행에서 (col, col+1) 가로선과 (col+1, col+2) 가로선이
  //   동시에 존재하면 사다리 충돌이 일어나므로 후자는 스킵
  void _generateBoard() {
    final n = widget.labels.length;
    if (n < 2) {
      _rungs = const [];
      return;
    }
    final rungs = <Set<int>>[];
    for (var r = 0; r < _rowCount; r++) {
      final row = <int>{};
      var c = 0;
      while (c < n - 1) {
        // 0.45 확률로 (c, c+1) 가로선 추가
        if (_random.nextDouble() < 0.45) {
          row.add(c);
          c += 2; // 다음 가로선은 최소 한 칸 띄움(충돌 방지)
        } else {
          c += 1;
        }
      }
      rungs.add(row);
    }
    _rungs = rungs;
    _winnerColumn = _random.nextInt(n); // ✅ 위치 무작위
  }

  void _reset() {
    _trace.reset();
    setState(() {
      _generateBoard();
      _selectedColumn = -1;
      _path = const [];
      _isFinished = false;
    });
  }

  // 윗줄에서 한 열을 탭했을 때 호출
  void _onPickColumn(int col) {
    if (_trace.isAnimating) return;
    if (_isFinished) return;
    setState(() {
      _selectedColumn = col;
      _path = _computePath(col);
      _isFinished = false;
    });
    _trace.forward(from: 0);
  }

  // 사다리 추적 알고리즘
  //
  // 시작 열에서 출발해 행을 한 칸씩 내려가며,
  // 현재 행에 (col-1, col) 또는 (col, col+1) 가로선이 있으면
  // 좌/우 열로 이동(가로선 위를 가로지름) 후 다음 행으로 진행.
  // 마지막 행에 도달했을 때의 열이 종착지(아래줄 칸).
  List<Offset> _computePath(int startCol) {
    final points = <Offset>[];
    var col = startCol;
    points.add(Offset(col.toDouble(), 0));
    for (var row = 0; row < _rowCount; row++) {
      // 현재 행에서 좌/우 가로선 확인
      final hasLeftRung = col > 0 && _rungs[row].contains(col - 1);
      final hasRightRung = _rungs[row].contains(col);
      // 가로선이 있으면 가로 이동 후 아래로 내려감
      if (hasRightRung) {
        // 같은 행에서 오른쪽으로 가로 이동
        points.add(Offset(col + 1.0, row + 0.5));
        col += 1;
      } else if (hasLeftRung) {
        points.add(Offset(col - 1.0, row + 0.5));
        col -= 1;
      }
      // 다음 행 끝까지 내려옴
      points.add(Offset(col.toDouble(), (row + 1).toDouble()));
    }
    return points;
  }

  void _handleTraceStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_path.isEmpty) return;
    final lastCol = _path.last.dx.round();
    final isWinner = lastCol == _winnerColumn;
    setState(() => _isFinished = true);
    // 부모(DecideScreen)에는 윗줄 인덱스(=사용자가 고른 열) 와
    // 결과(당첨 여부)를 함께 보내야 사다리 특성을 살릴 수 있지만,
    // 캡스톤 시연용 단순화를 위해 "당첨자 윗줄 인덱스" 만 통보:
    //   - ✅ 도달한 윗줄 열 = winnerColumn 으로 도달한 윗줄(역추적)
    // 다만 사다리는 1:1 매핑이므로, ✅ 칸에 도달하는 윗줄은 단 하나.
    // 시연 흐름: 사용자가 직접 골랐을 때 도달한 열이 ✅ 면 그 사람의 식당이,
    //          ❌ 면 ✅ 가 있던 컬럼 인덱스 가 당첨 식당.
    // → 어느 쪽이든 결국 "✅ 가 가리키는 윗줄 후보" 를 결과로 통보합니다.
    final winnerTopIndex = _findTopIndexForBottom(_winnerColumn);
    widget.onResult(winnerTopIndex);
    // (isWinner 값은 향후 UX 분기에 사용할 수 있도록 보존)
    debugPrint('[LadderGame] picked=$_selectedColumn '
        'reached=$lastCol winner=$isWinner');
  }

  // 아래줄의 특정 열(bottomCol) 에 도달하는 윗줄 시작 열을 역으로 찾는 헬퍼
  //
  // 사다리는 1:1 매핑이므로 모든 윗줄 열에 대해 _computePath 를 돌려
  // 종착지가 bottomCol 인 시작 열을 찾으면 됩니다.
  int _findTopIndexForBottom(int bottomCol) {
    for (var c = 0; c < widget.labels.length; c++) {
      final p = _computePath(c);
      if (p.last.dx.round() == bottomCol) return c;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.labels.length;
    if (n < 2) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          '후보가 2명 이상이어야 사다리를 만들 수 있어요.',
          style: AppTextStyles.bodyMedium,
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 윗줄: 후보 칩 (탭하여 시작 위치 선택) ─────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(n, (i) {
              final isSelected = _selectedColumn == i;
              return GestureDetector(
                onTap: () => _onPickColumn(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 56,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? CustomerColors.primary
                        : CustomerColors.primarySurface,
                    borderRadius:
                        BorderRadius.circular(AppRadius.small),
                    border: Border.all(
                      color: CustomerColors.primaryDark,
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _shortLabel(widget.labels[i]),
                    style: AppTextStyles.label.copyWith(
                      color: isSelected
                          ? AppColors.background
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── 사다리 본체 (CustomPaint) ────────────────────────
        SizedBox(
          width: math.min(56.0 * n + 32, 360),
          height: 280,
          child: AnimatedBuilder(
            animation: _trace,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_trace.value);
              return CustomPaint(
                painter: _LadderPainter(
                  columnCount: n,
                  rowCount: _rowCount,
                  rungs: _rungs,
                  winnerColumn: _winnerColumn,
                  path: _path,
                  progress: t,
                ),
              );
            },
          ),
        ),

        const SizedBox(height: AppSpacing.sm),
        // ── 아래줄: ✅ / ❌ 표시 ─────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(n, (i) {
              final isWin = i == _winnerColumn;
              return Container(
                width: 56,
                height: 40,
                decoration: BoxDecoration(
                  color: isWin
                      ? AppColors.success
                      : AppColors.disabledBackground,
                  borderRadius:
                      BorderRadius.circular(AppRadius.small),
                ),
                alignment: Alignment.center,
                child: Text(
                  isWin ? '당첨!' : '꽝',
                  style: AppTextStyles.label.copyWith(
                    color: isWin
                        ? AppColors.background
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // 칩에 표시할 짧은 라벨(겹침 방지)
  String _shortLabel(String raw) {
    if (raw.length <= 4) return raw;
    return '${raw.substring(0, 3)}…';
  }
}

// ─────────────────────────────────────────────────────────
// 사다리 본체 + 경로 트레이스를 그리는 Painter
// ─────────────────────────────────────────────────────────
class _LadderPainter extends CustomPainter {
  _LadderPainter({
    required this.columnCount,
    required this.rowCount,
    required this.rungs,
    required this.winnerColumn,
    required this.path,
    required this.progress,
  });

  final int columnCount;
  final int rowCount;
  final List<Set<int>> rungs;
  final int winnerColumn;
  final List<Offset> path; // (col, rowFractional) 단위
  final double progress; // 0.0 ~ 1.0

  @override
  void paint(Canvas canvas, Size size) {
    if (columnCount < 2 || rungs.isEmpty) return;

    // 격자 좌표 → 픽셀 좌표 변환 헬퍼
    final colSpacing = size.width / (columnCount - 1);
    final rowHeight = size.height / rowCount;

    Offset toPixel(Offset cell) =>
        Offset(cell.dx * colSpacing, cell.dy * rowHeight);

    // ── 세로줄(기둥) ─────────────────────────────────────
    final pillar = Paint()
      ..color = AppColors.border
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var c = 0; c < columnCount; c++) {
      final x = c * colSpacing;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), pillar);
    }

    // ── 가로선(rung) ────────────────────────────────────
    final rung = Paint()
      ..color = AppColors.border
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var r = 0; r < rowCount; r++) {
      final y = (r + 0.5) * rowHeight;
      for (final c in rungs[r]) {
        final x1 = c * colSpacing;
        final x2 = (c + 1) * colSpacing;
        canvas.drawLine(Offset(x1, y), Offset(x2, y), rung);
      }
    }

    // ── 추적 경로(빨간 선) — progress 만큼만 그림 ──────────
    if (path.length > 1 && progress > 0) {
      final tracePaint = Paint()
        ..color = CustomerColors.secondary
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final tracePath = Path();

      // 경로 전체 길이를 알아내서 progress 비율만큼 잘라 그리기
      final pixelPoints = path.map(toPixel).toList(growable: false);
      double totalLen = 0;
      for (var i = 1; i < pixelPoints.length; i++) {
        totalLen += (pixelPoints[i] - pixelPoints[i - 1]).distance;
      }
      final targetLen = totalLen * progress;

      double accumulated = 0;
      tracePath.moveTo(pixelPoints.first.dx, pixelPoints.first.dy);
      for (var i = 1; i < pixelPoints.length; i++) {
        final segLen = (pixelPoints[i] - pixelPoints[i - 1]).distance;
        if (accumulated + segLen <= targetLen) {
          tracePath.lineTo(pixelPoints[i].dx, pixelPoints[i].dy);
          accumulated += segLen;
        } else {
          // 부분 세그먼트: 시작점에서 비율만큼만 그리기
          final remain = targetLen - accumulated;
          final ratio = remain / segLen;
          final dx = pixelPoints[i - 1].dx +
              (pixelPoints[i].dx - pixelPoints[i - 1].dx) * ratio;
          final dy = pixelPoints[i - 1].dy +
              (pixelPoints[i].dy - pixelPoints[i - 1].dy) * ratio;
          tracePath.lineTo(dx, dy);
          break;
        }
      }
      canvas.drawPath(tracePath, tracePaint);
    }

    // ── 당첨 컬럼 강조(아래줄로 떨어지는 화살표) ──────────
    final hint = Paint()
      ..color = AppColors.success
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final winnerX = winnerColumn * colSpacing;
    canvas.drawLine(
      Offset(winnerX, size.height - 8),
      Offset(winnerX, size.height),
      hint,
    );
  }

  @override
  bool shouldRepaint(covariant _LadderPainter old) =>
      old.progress != progress ||
      old.path != path ||
      old.rungs != rungs ||
      old.winnerColumn != winnerColumn;
}
