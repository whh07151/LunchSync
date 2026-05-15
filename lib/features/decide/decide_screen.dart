// ══════════════════════════════════════════════════════════
// 파일 역할: "미니게임으로 점심 결정하기" 화면 (DecideScreen)
//
// 진입 방법(부모가 호출):
//   await Navigator.of(context).push(
//     MaterialPageRoute(
//       builder: (_) => DecideScreen(
//         candidates: pickedRestaurants,
//         sessionId: sessionId,   // votes API 자동 호출용 — 필수
//         isHost: isHost,         // true 면 decide() 호출, false 면 castVote()
//       ),
//     ),
//   );
//
// 동작 흐름 (2026-05-14 votes API 통합 강화):
//   1) 룰렛/사다리로 winner 결정
//   2) "이 식당으로 결정" 누르면 자동으로 votes API 호출
//       - 호스트: POST /sessions/:id/decide → 세션 ORDERED 전이 → MenuScreen push
//       - 비호스트: POST /sessions/:id/votes (한 표만 등록)
//                  → 호스트가 종료할 때까지 본 화면에 머무름(혹은 pop 으로 복귀)
//   3) winner 카드에 FoodImage + 카테고리 + 가격대 + 평점 미리보기 강화
//
// 게임 종류:
//   1) 룰렛(스피너 휠) — 기본 선택, 시연 임팩트 1순위
//   2) 사다리 — 4~6명 케이스에 최적화
//
// 색상 정책: CustomerColors / AppColors 디자인 토큰만 사용 (변경 금지).
// asset 추가 없음 — 이모지 + CustomPainter 로 모든 그래픽 구현.
// ══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../core/widgets/food_image.dart';
import '../../models/restaurant.dart';
import '../../providers/user_provider.dart';
import '../../services/votes_api_service.dart';
import '../menu/menu_screen.dart';
import 'widgets/ladder_game.dart';
import 'widgets/spinner_wheel.dart';

/// 미니게임으로 후보 식당 중 하나를 결정하는 화면
///
/// votes API 자동 호출을 위해 sessionId 와 isHost 를 함께 받는다.
/// 두 값이 모두 누락된 레거시 호출부(테스트/프리뷰)는 게임만 동작하고
/// 결과 확정 시 단순 pop 으로 결과 식당을 반환하는 fallback 으로 폴백된다.
class DecideScreen extends ConsumerStatefulWidget {
  const DecideScreen({
    super.key,
    required this.candidates,
    this.sessionId,
    this.isHost = false,
  });

  /// 결정 대상 후보 식당 목록
  ///
  /// - 2개 이상 권장 (1개 이하면 게임 의미가 없음 → 진입 직후 안내)
  /// - 너무 많으면 룰렛 글자가 겹치므로 상위 6개까지만 표시
  final List<Restaurant> candidates;

  /// votes API 호출 대상 세션 UUID.
  ///
  /// null 이면 API 호출 없이 단순 pop 으로 결과만 반환하는 레거시 모드로 동작.
  /// 정상 흐름(추천 리스트/비교 화면)에서는 항상 값이 전달되어야 한다.
  final String? sessionId;

  /// 현재 사용자가 세션 호스트인지.
  ///
  /// - true:  "이 식당으로 결정" → POST /decide → MenuScreen 으로 자동 push
  /// - false: "이 식당으로 결정" → POST /votes → 본인 한 표 등록 후 pop
  ///
  /// 백엔드가 권한 검증을 수행하므로 잘못 넣어도 안전하지만,
  /// UI 표기(버튼 카피)를 위해 정확하게 받아야 한다.
  final bool isHost;

  @override
  ConsumerState<DecideScreen> createState() => _DecideScreenState();
}

/// 어떤 게임을 선택했는지 구분하는 enum
enum _GameKind {
  spinner('룰렛', '🎯'),
  ladder('사다리', '🪜');

  const _GameKind(this.label, this.emoji);

  final String label;
  final String emoji;
}

class _DecideScreenState extends ConsumerState<DecideScreen> {
  // 현재 선택된 게임 (탭 전환용)
  _GameKind _selected = _GameKind.spinner;

  // 게임 결과로 정해진 winner index (룰렛/사다리 위젯 → onResult 콜백으로 받음)
  // - null: 아직 결정 안 됨 (게임 실행 전 또는 회전 중)
  int? _winnerIndex;

  // votes API 호출 중 — 중복 클릭/이중 push 방지용 가드
  bool _isSubmitting = false;

  // 룰렛/사다리 위젯을 외부에서 제어하기 위한 컨트롤러
  // ("다시 돌리기" 버튼 → 컨트롤러.spin() 호출 방식)
  final SpinnerWheelController _spinnerCtrl = SpinnerWheelController();
  final LadderGameController _ladderCtrl = LadderGameController();

  // votes API 클라이언트 — 호스트/비호스트 분기에 사용
  static const _votesApi = VotesApiService();

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

  // "이 식당으로 결정" — votes API 호출 + 후속 라우팅
  //
  // 분기:
  //   - sessionId 없음(레거시): 단순 pop 으로 winner 반환
  //   - 호스트: decide() → 성공 시 MenuScreen pushReplacement
  //   - 비호스트: castVote() → 성공/중복(409) 둘 다 친근 안내 후 pop
  Future<void> _confirm() async {
    if (_winnerIndex == null || _isSubmitting) return;
    final winner = _candidates[_winnerIndex!];

    // ── 1) 레거시 호출부(sessionId 미지정) ────────────────
    // votes API 를 모르는 호출부를 위한 안전한 fallback. 게임 결과만 반환.
    if (widget.sessionId == null || widget.sessionId!.isEmpty) {
      Navigator.of(context).pop<Restaurant>(winner);
      return;
    }

    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 풀렸어요. 다시 로그인해봐요')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    if (widget.isHost) {
      // ── 2) 호스트 — decide(restaurantId) → ORDERED → MenuScreen ─
      // 2026-05-15 회귀 fix (폰 라이브 검증):
      //   룰렛/사다리는 "투표 건너뛰고 호스트가 바로 정하기" 흐름.
      //   기존엔 castVote(VOTING 강제) + decide(투표집계) 라 WAITING 에서
      //   "결정을 마치지 못했어요" 발생. 이제 winner.id 를 decide 에 직접
      //   전달 → 백엔드 decideManually 가 WAITING 에서도 즉석 확정.
      //   castVote 선행 호출 제거 (불필요 + WAITING 에서 실패 원인).
      final result = await _votesApi.decide(
        accessToken: token,
        sessionId: widget.sessionId!,
        restaurantId: winner.id,
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (result == null || result.winnerRestaurantId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('결정을 마치지 못했어요. 잠시 후 다시 시도해봐요')),
        );
        return;
      }

      // 결과 안내 토스트 — 친근 톤 + 다음 액션 명시
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${result.winnerName}" 으로 결정됐어요! 메뉴 골라봐요'),
          duration: const Duration(seconds: 3),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );

      // MenuScreen 으로 pushReplacement — 뒤로 가기로 다시 게임화면 안 돌아오게
      // (vote_progress_screen 의 _navigateToMenu 와 동일한 흐름)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MenuScreen(
            restaurantId: result.winnerRestaurantId,
            restaurantName: result.winnerName.isNotEmpty
                ? result.winnerName
                : winner.name,
            sessionId: widget.sessionId,
          ),
        ),
      );
    } else {
      // ── 3) 비호스트 — castVote() 만 호출 ──────────────────
      // 결과는 호스트가 종료할 때까지 vote_progress_screen 폴링에서 확인.
      // 본 화면은 단순 pop 으로 빠져나가 부모(추천 리스트/비교)에 winner 를 반환.
      final result = await _votesApi.castVote(
        accessToken: token,
        sessionId: widget.sessionId!,
        restaurantId: winner.id,
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      String message;
      if (result.isSuccess) {
        message = '"${winner.name}" 에 한 표! 호스트가 종료하면 메뉴 화면으로 이동해요';
      } else if (result.alreadyVoted) {
        // 백엔드 409 — 이미 다른 식당에 한 표 던진 상태. 친근 안내.
        message = result.message ?? '이미 투표했어요';
      } else {
        message = result.message ?? '투표가 안 됐어요. 다시 시도해봐요';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          backgroundColor: result.isSuccess
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
      );

      // 부모로 winner 반환 — 호출부가 후속 액션(예: 비교 화면 pop) 처리 가능
      Navigator.of(context).pop<Restaurant>(winner);
    }
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
                  isHost: widget.isHost,
                  isSubmitting: _isSubmitting,
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
// 결과 카드 — 우승 식당 풍부한 미리보기 (2026-05-14 강화)
//
// 기존: 텍스트만(식당 이름 + 가격대)
// 강화: FoodImage(70x70) + 카테고리 + 가격대 + ⭐ 평점 + 카피 + 액션 버튼
//
// 버튼 카피는 호스트 여부에 따라 분기:
//   - 호스트: "이 식당으로 결정" (decide → MenuScreen)
//   - 비호스트: "이 식당에 투표" (castVote → pop)
// ─────────────────────────────────────────────────────────
class _WinnerCard extends StatelessWidget {
  const _WinnerCard({
    required this.restaurant,
    required this.isHost,
    required this.isSubmitting,
    required this.onRetry,
    required this.onConfirm,
  });

  final Restaurant restaurant;
  final bool isHost;
  final bool isSubmitting;
  final VoidCallback onRetry;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    // 호스트는 결정, 비호스트는 투표 한 표만 등록 → 카피 다르게.
    final confirmLabel = isHost ? '이 식당으로 결정' : '이 식당에 투표';

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
          // ── 헤더: 🎉 + 카피 ────────────────────────────
          Row(
            children: [
              const Text('🎉', style: TextStyle(fontSize: 28)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '이 식당으로 정해졌어요!',
                  style: AppTextStyles.heading3,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── 식당 미리보기 (사진 + 메타 정보) ────────────
          // FoodImage 가 imageUrl 결측/실패를 카테고리 이모지 fallback 으로
          // 자동 처리해주므로 호출부는 그대로 모델 필드를 전달만 하면 된다.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FoodImage(
                imageUrl: restaurant.imageUrl,
                categoryLabel: restaurant.category.label,
                width: 70,
                height: 70,
                emojiSize: 32,
                semanticLabel: '${restaurant.name} 이미지',
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 식당 이름 — 강조 톤
                    Text(
                      restaurant.name,
                      style: AppTextStyles.heading3.copyWith(
                        color: CustomerColors.primaryDark,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // 카테고리 라벨 (RestaurantCategory.label 사용 — 한글)
                    Text(
                      restaurant.category.label,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    // 가격대 — priceRange 가 있을 때만 표시
                    if (restaurant.priceRange != null &&
                        restaurant.priceRange!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        restaurant.priceDisplay,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    // ⭐ 평점 — null 이 아니면 1자리 소수로 표시
                    if (restaurant.rating != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Text('⭐', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 2),
                          Text(
                            restaurant.rating!.toStringAsFixed(1),
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── 액션 버튼 ────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isSubmitting ? null : onRetry,
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
                  onPressed: isSubmitting ? null : onConfirm,
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
                  // 제출 중이면 스피너로 잠금 표시 — 더블 탭/이중 push 방지.
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.background,
                          ),
                        )
                      : Text(
                          confirmLabel,
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
