import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/user_provider.dart';
import '../../services/votes_api_service.dart';
import '../../services/sessions_api_service.dart';
import '../../models/session.dart';
import 'add_candidate_screen.dart';
import '../menu/menu_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-14 투표 화면
//
// 진입 경로: AI 추천 목록(CU-11) → "투표 시작" 버튼
//
// 주요 기능:
//   - 투표 후보 식당 목록 표시 (AI 추천 + 멤버 추가분)
//   - 후보 식당 추가 (검색/반경 내 식당)
//   - 식당 1곳 선택 후 투표
//   - 투표 현황 3초 폴링 (누가 투표했는지, 득표수)
//   - 방장: "투표 종료" 버튼으로 결과 확정
//   - 결과 확정 시 메뉴 화면으로 이동
//
// 폴링: Timer.periodic 3초 간격
//   백그라운드 진입 시 취소, 복귀 시 재시작 (WidgetsBindingObserver)
// ══════════════════════════════════════════════════════════

class VotingScreen extends ConsumerStatefulWidget {
  const VotingScreen({
    super.key,
    required this.sessionId,
    required this.sessionName,
    this.isHost = false,
  });

  final String sessionId;
  final String sessionName;
  final bool isHost;

  @override
  ConsumerState<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends ConsumerState<VotingScreen>
    with WidgetsBindingObserver {
  // ── 상태 변수 ─────────────────────────────────────────
  List<CandidateDto> _candidates = [];
  List<VoteStatus> _votes = [];
  SessionMembersResponse? _membersData;
  bool _isLoading = true;
  bool _hasVoted = false;
  String? _selectedRestaurantId;
  String? _errorMessage;
  bool _isSubmitting = false;
  bool _isDeciding = false;
  Timer? _pollingTimer;

  static const _votesApi = VotesApiService();
  static const _sessionsApi = SessionsApiService();

  // ── 생명주기 ──────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAll();
      _startPolling();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pollingTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _loadVotesAndCandidates();
      _startPolling();
    }
  }

  // ── 폴링 ─────────────────────────────────────────────
  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadVotesAndCandidates();
    });
  }

  // ── 데이터 로드 ───────────────────────────────────────
  Future<void> _loadAll() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = '로그인이 필요합니다.';
      });
      return;
    }

    final results = await Future.wait([
      _votesApi.getCandidates(accessToken: token, sessionId: widget.sessionId),
      _votesApi.getVotes(accessToken: token, sessionId: widget.sessionId),
      _sessionsApi.getSessionMembers(accessToken: token, sessionId: widget.sessionId),
    ]);

    if (!mounted) return;

    final userId = ref.read(userProvider).userId;

    setState(() {
      _candidates = results[0] as List<CandidateDto>;
      _votes = results[1] as List<VoteStatus>;
      _membersData = results[2] as SessionMembersResponse?;
      _hasVoted = _votes.any((v) => v.userId == userId);
      _isLoading = false;
    });
  }

  Future<void> _loadVotesAndCandidates() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    final results = await Future.wait([
      _votesApi.getCandidates(accessToken: token, sessionId: widget.sessionId),
      _votesApi.getVotes(accessToken: token, sessionId: widget.sessionId),
    ]);

    if (!mounted) return;

    final userId = ref.read(userProvider).userId;

    setState(() {
      _candidates = results[0] as List<CandidateDto>;
      _votes = results[1] as List<VoteStatus>;
      _hasVoted = _votes.any((v) => v.userId == userId);
    });
  }

  // ── 투표 제출 ─────────────────────────────────────────
  Future<void> _submitVote() async {
    if (_selectedRestaurantId == null || _isSubmitting) return;

    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    setState(() => _isSubmitting = true);

    final result = await _votesApi.castVote(
      accessToken: token,
      sessionId: widget.sessionId,
      restaurantId: _selectedRestaurantId!,
    );

    if (!mounted) return;

    if (result != null) {
      setState(() {
        _hasVoted = true;
        _isSubmitting = false;
      });
      _loadVotesAndCandidates();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('투표 완료!')),
      );
    } else {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 투표했거나 오류가 발생했습니다.')),
      );
    }
  }

  // ── 투표 종료 (방장) ──────────────────────────────────
  Future<void> _decideVote() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    // 확인 다이얼로그
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('투표 종료'),
        content: const Text('투표를 종료하고 결과를 확정할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('확정'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isDeciding = true);

    final result = await _votesApi.decide(
      accessToken: token,
      sessionId: widget.sessionId,
    );

    if (!mounted) return;
    setState(() => _isDeciding = false);

    if (result != null) {
      _pollingTimer?.cancel();
      _showResultDialog(result);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('투표 결과 확정에 실패했습니다.')),
      );
    }
  }

  // ── 결과 다이얼로그 ───────────────────────────────────
  void _showResultDialog(VoteDecideResult result) {
    final primary = Theme.of(context).colorScheme.primary;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.emoji_events_rounded, color: primary, size: 28),
            const SizedBox(width: 8),
            const Text('투표 결과'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.winnerName,
              style: AppTextStyles.heading2.copyWith(color: primary),
            ),
            const SizedBox(height: 8),
            Text(
              '${result.voteCount}표 / 총 ${result.totalVotes}표',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 16),
            const Text('전체 결과', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...result.tally.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(child: Text(t.restaurantName, style: AppTextStyles.bodySmall)),
                  Text('${t.count}표', style: AppTextStyles.bodySmall),
                ],
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // 다이얼로그 닫기
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => MenuScreen(
                    restaurantName: result.winnerName,
                  ),
                ),
              );
            },
            child: const Text('메뉴 선택으로'),
          ),
        ],
      ),
    );
  }

  // ── 식당 추가 화면으로 이동 ───────────────────────────
  Future<void> _openAddCandidate() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddCandidateScreen(
          sessionId: widget.sessionId,
          existingCandidateIds: _candidates.map((c) => c.restaurantId).toSet(),
        ),
      ),
    );

    if (added == true) {
      _loadVotesAndCandidates();
    }
  }

  // ── 득표수 계산 ───────────────────────────────────────
  int _getVoteCount(String restaurantId) {
    return _votes.where((v) => v.restaurantId == restaurantId).length;
  }

  // ── 빌드 ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final totalMembers = _membersData?.joinedCount ?? 0;
    final votedCount = _votes.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(
        showBack: true,
        title: '투표',
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(child: Text(_errorMessage!, style: AppTextStyles.bodyMedium))
                : Column(
                    children: [
                      // ── 헤더: 세션 이름 + 투표 현황 ────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screenHorizontal,
                          AppSpacing.md,
                          AppSpacing.screenHorizontal,
                          AppSpacing.sm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.sessionName, style: AppTextStyles.heading3),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.how_to_vote_rounded, size: 16, color: primary),
                                const SizedBox(width: 4),
                                Text(
                                  '투표 현황: $votedCount / $totalMembers명 완료',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const Spacer(),
                                if (_hasVoted)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withAlpha(25),
                                      borderRadius: BorderRadius.circular(AppRadius.chip),
                                    ),
                                    child: Text(
                                      '투표 완료',
                                      style: AppTextStyles.caption.copyWith(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // 투표 진행률 바
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: totalMembers > 0 ? votedCount / totalMembers : 0,
                                backgroundColor: AppColors.backgroundGrey,
                                valueColor: AlwaysStoppedAnimation<Color>(primary),
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── 후보 식당 리스트 ───────────────────
                      Expanded(
                        child: _candidates.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.restaurant_outlined, size: 48, color: AppColors.iconInactive),
                                    const SizedBox(height: AppSpacing.sm),
                                    Text('후보 식당이 없어요', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                                    const SizedBox(height: AppSpacing.md),
                                    AppPrimaryButton(
                                      label: '식당 추가하기',
                                      onPressed: _openAddCandidate,
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.screenHorizontal,
                                  AppSpacing.sm,
                                  AppSpacing.screenHorizontal,
                                  AppSpacing.xl,
                                ),
                                physics: const BouncingScrollPhysics(),
                                itemCount: _candidates.length,
                                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                                itemBuilder: (_, i) => _buildCandidateCard(_candidates[i]),
                              ),
                      ),
                    ],
                  ),
      ),

      // ── 하단 버튼 영역 ────────────────────────────────
      bottomNavigationBar: _isLoading || _errorMessage != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 식당 추가 버튼
                    if (!_hasVoted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppOutlinedButton(
                          label: '+ 식당 후보 추가',
                          onPressed: _openAddCandidate,
                        ),
                      ),

                    // 투표 버튼 (투표 전)
                    if (!_hasVoted)
                      AppPrimaryButton(
                        label: '투표하기',
                        onPressed: _selectedRestaurantId != null ? _submitVote : null,
                        isLoading: _isSubmitting,
                      ),

                    // 투표 종료 버튼 (방장 + 투표 후)
                    if (widget.isHost && _votes.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: _hasVoted ? 0 : AppSpacing.sm),
                        child: AppPrimaryButton(
                          label: '투표 종료 및 결과 확정',
                          onPressed: _decideVote,
                          isLoading: _isDeciding,
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  // ── 후보 카드 ─────────────────────────────────────────
  Widget _buildCandidateCard(CandidateDto candidate) {
    final primary = Theme.of(context).colorScheme.primary;
    final isSelected = _selectedRestaurantId == candidate.restaurantId;
    final voteCount = _getVoteCount(candidate.restaurantId);

    // 가격대 레이블
    final priceLabel = candidate.priceRange != null
        ? '${_formatWithComma(candidate.priceRange!)}원대'
        : '가격 미정';

    return AppCard(
      onTap: _hasVoted
          ? null
          : () {
              setState(() {
                _selectedRestaurantId = isSelected ? null : candidate.restaurantId;
              });
            },
      padding: const EdgeInsets.all(AppSpacing.md),
      borderColor: isSelected ? primary : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 선택 라디오 (투표 전만)
              if (!_hasVoted)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: isSelected ? primary : AppColors.textHint,
                    size: 22,
                  ),
                ),

              // 식당 이름
              Expanded(
                child: Text(
                  candidate.name ?? '이름 없음',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // 출처 배지
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: candidate.source == 'AI'
                      ? primary.withAlpha(25)
                      : AppColors.backgroundGrey,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  candidate.source == 'AI' ? 'AI 추천' : '직접 추가',
                  style: AppTextStyles.caption.copyWith(
                    color: candidate.source == 'AI' ? primary : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // 득표수
              if (voteCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withAlpha(25),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    '$voteCount표',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // 카테고리 + 가격
          Row(
            children: [
              if (candidate.category != null) ...[
                const Icon(Icons.restaurant_rounded, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(candidate.category!, style: AppTextStyles.bodySmall),
                const SizedBox(width: AppSpacing.sm),
              ],
              const Icon(Icons.payments_outlined, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(priceLabel, style: AppTextStyles.bodySmall),
            ],
          ),

          // 주소
          if (candidate.address != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    candidate.address!,
                    style: AppTextStyles.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatWithComma(int value) {
    final s = value.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}
