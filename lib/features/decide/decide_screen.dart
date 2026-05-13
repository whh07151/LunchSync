// ══════════════════════════════════════════════════════════
// 파일 역할: "미니게임으로 점심 결정하기" 화면 (DecideScreen)
//
// 진입 방법(부모가 호출):
//   final winner = await Navigator.of(context).push<Restaurant?>(
//     MaterialPageRoute(
//       builder: (_) => DecideScreen(candidates: pickedRestaurants),
//     ),
//   );
//   if (winner != null) { /* votes API 호출 또는 세션 결정 처리 */ }
//
// 반환값:
//   - Restaurant 1개 (사용자가 "이 식당으로 결정" 버튼을 눌렀을 때)
//   - null (그냥 뒤로 갔을 때)
//
// 게임 종류:
//   1) 룰렛(스피너 휠) — 기본 선택, 시연 임팩트 1순위
//   2) 사다리 — 4~6명 케이스에 최적화
//
// 사장님 피드백: "후보들 중에서 미니게임(사다리/뽑기/룰렛 등)으로
//               결정할 수 있게 하고 싶다" → 캡스톤 시연 임팩트 포인트
//
// 색상 정책: CustomerColors / AppColors 디자인 토큰만 사용 (변경 금지).
// asset 추가 없음 — 이모지 + CustomPainter 로 모든 그래픽 구현.
// ══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../models/restaurant.dart';
import 'widgets/ladder_game.dart';
import 'widgets/spinner_wheel.dart';

/// 미니게임으로 후보 식당 중 하나를 결정하는 화면
class DecideScreen extends StatefulWidget {
  const DecideScreen({
    super.key,
    required this.candidates,
  });

  /// 결정 대상 후보 식당 목록
  ///
  /// - 2개 이상 권장 (1개 이하면 게임 의미가 없음 → 진입 직후 안내)
  /// - 너무 많으면 룰렛 글자가 겹치므로 상위 6개까지만 표시
  final List<Restaurant> candidates;

  @override
  State<DecideScreen> createState() => _DecideScreenState();
}

/// 어떤 게임을 선택했는지 구분하는 enum
enum _GameKind {
  spinner('룰렛', '🎯'),
  ladder('사다리', '🪜');

  const _GameKind(this.label, this.emoji);

  final String label;
  final String emoji;
}

class _DecideScreenState extends State<DecideScreen> {
  // 현재 선택된 게임 (탭 전환용)
  _GameKind _selected = _GameKind.spinner;

  // 게임 결과로 정해진 winner index (룰렛/사다리 위젯 → onResult 콜백으로 받음)
  // - null: 아직 결정 안 됨 (게임 실행 전 또는 회전 중)
  int? _winnerIndex;

  // 룰렛/사다리 위젯을 외부에서 제어하기 위한 컨트롤러
  // ("다시 돌리기" 버튼 → 컨트롤러.spin() 호출 방식)
  final SpinnerWheelController _spinnerCtrl = SpinnerWheelController();
  final LadderGameController _ladderCtrl = LadderGameController();

  // 룰렛에 한 번에 표시할 최대 후보 수 (글자 겹침 방지)
  static const int _maxWheelCandidates = 6;

  // 화면에 실제로 사용되는 후보 목록 (최대 _maxWheelCandidates 명으로 자른 결과)
  late final List<Restaurant> _candidates;

  @override
  void initState() {
    super.initState();
    // 후보가 너무 많으면 상위 N개로 잘라서 표시
    // (백엔드 추천 순서대로 들어왔다고 가정 → 상위 = 점수 높은 후보)
    _candidates = widget.candidates.length > _maxWheelCandidates
        ? widget.candidates.sublist(0, _maxWheelCandidates)
        : widget.candidates;
  }

  // 게임 위젯에서 결과를 받았을 때 호출
  void _onWinner(int idx) {
    if (!mounted) return;
    setState(() => _winnerIndex = idx);
  }

  // "다시 돌리기" — 현재 선택된 게임 컨트롤러를 통해 재실행
  void _retry() {
    setState(() => _winnerIndex = null);
    if (_selected == _GameKind.spinner) {
      _spinnerCtrl.spin();
    } else {
      _ladderCtrl.reset();
    }
  }

  // "이 식당으로 결정" — Navigator.pop 으로 부모에게 결과 반환
  void _confirm() {
    if (_winnerIndex == null) return;
    final winner = _candidates[_winnerIndex!];
    Navigator.of(context).pop<Restaurant>(winner);
  }

  // 탭 전환 시 결과 초기화
  void _switchGame(_GameKind kind) {
    if (_selected == kind) return;
    setState(() {
      _selected = kind;
      _winnerIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 후보가 부족한 경우 안내 화면
    if (_candidates.length < 2) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('재미있게 결정해봐요'),
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: Text(
              '미니게임을 하려면\n후보 식당이 2개 이상 필요해요.',
              style: AppTextStyles.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('재미있게 결정해봐요'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
            vertical: AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 헤더: 친근한 카피 ─────────────────────────
              Text(
                '결정하기 어려울 땐\n미니게임으로 정해봐요!',
                style: AppTextStyles.heading2,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${_candidates.length}곳 중에서 한 곳을 골라드릴게요',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── 후보 식당 가로 스크롤 칩 ──────────────────
              _CandidateChips(
                candidates: _candidates,
                highlightedIndex: _winnerIndex,
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── 게임 선택 탭 ──────────────────────────────
              _GameTabBar(
                selected: _selected,
                onChange: _switchGame,
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── 게임 본체 ────────────────────────────────
              Center(
                child: _selected == _GameKind.spinner
                    ? SpinnerWheel(
                        labels: _candidates
                            .map((r) => r.name)
                            .toList(growable: false),
                        controller: _spinnerCtrl,
                        onResult: _onWinner,
                      )
                    : LadderGame(
                        labels: _candidates
                            .map((r) => r.name)
                            .toList(growable: false),
                        controller: _ladderCtrl,
                        onResult: _onWinner,
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── 결과 카드 (결정된 식당) ───────────────────
              if (_winnerIndex != null)
                _WinnerCard(
                  restaurant: _candidates[_winnerIndex!],
                  onRetry: _retry,
                  onConfirm: _confirm,
                ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 게임 선택 탭바 (룰렛 / 사다리)
// ─────────────────────────────────────────────────────────
class _GameTabBar extends StatelessWidget {
  const _GameTabBar({
    required this.selected,
    required this.onChange,
  });

  final _GameKind selected;
  final ValueChanged<_GameKind> onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.disabledBackground,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Row(
        children: _GameKind.values.map((k) {
          final isSelected = k == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChange(k),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: isSelected
                      ? CustomerColors.primary
                      : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(AppRadius.button),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${k.emoji} ${k.label}',
                  style: AppTextStyles.buttonMedium.copyWith(
                    color: isSelected
                        ? AppColors.background
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 후보 식당 가로 스크롤 칩
//
// - 현재 결정된 후보가 있으면 해당 칩만 강조(primary 배경)
// - 시연 시 사용자가 "후보가 누구누구였지?" 한눈에 보이도록 첫 화면에 노출
// ─────────────────────────────────────────────────────────
class _CandidateChips extends StatelessWidget {
  const _CandidateChips({
    required this.candidates,
    required this.highlightedIndex,
  });

  final List<Restaurant> candidates;
  final int? highlightedIndex;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: candidates.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final r = candidates[i];
          final isHighlighted = i == highlightedIndex;
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? CustomerColors.primary
                  : CustomerColors.primarySurface,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(
                color: isHighlighted
                    ? CustomerColors.primaryDark
                    : CustomerColors.primaryLight,
                width: 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              r.name,
              style: AppTextStyles.label.copyWith(
                color: isHighlighted
                    ? AppColors.background
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 결과 카드
//
// "이 식당으로 정해졌어요!" + 식당 이름 + "다시 돌리기" / "이 식당으로 결정"
// ─────────────────────────────────────────────────────────
class _WinnerCard extends StatelessWidget {
  const _WinnerCard({
    required this.restaurant,
    required this.onRetry,
    required this.onConfirm,
  });

  final Restaurant restaurant;
  final VoidCallback onRetry;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: CustomerColors.primarySurface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: CustomerColors.primary,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('🎉', style: TextStyle(fontSize: 28)),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '이 식당으로 정해졌어요!',
                style: AppTextStyles.heading3,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            restaurant.name,
            style: AppTextStyles.heading2.copyWith(
              color: CustomerColors.primaryDark,
            ),
          ),
          if (restaurant.priceRange != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              restaurant.priceDisplay,
              style: AppTextStyles.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CustomerColors.primary,
                    side: const BorderSide(
                      color: CustomerColors.primary,
                      width: 1.5,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm + 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: Text(
                    '다시 돌리기',
                    style: AppTextStyles.buttonMedium.copyWith(
                      color: CustomerColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CustomerColors.primary,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm + 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: Text(
                    '이 식당으로 결정',
                    style: AppTextStyles.buttonMedium.copyWith(
                      color: AppColors.background,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
