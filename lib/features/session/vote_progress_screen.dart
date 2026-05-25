import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../providers/user_provider.dart';
import '../../services/recommendations_api_service.dart';
import '../../services/sessions_api_service.dart';
import '../../services/votes_api_service.dart';
import '../../models/session.dart' show SessionMember;
import '../menu/menu_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 투표 진행 + 결과 실시간 현황 화면 (CU-14/15 UI)
//
// 진입 경로:
//   1. recommendation_list_screen 의 "투표 현황 보기" CTA
//   2. session_lobby_screen 자동 라우팅(별도 — 본 화면이 아닌 추천 리스트로 이동)
//
// 핵심 목표 (사장님 시연 피드백 반영):
//   - "투표가 어떻게 진행되는지 보이지 않는다" → 진행도/결과를 한 화면에 시각화
//   - "투표 끝나면 자동으로 메뉴 선택으로 가야 한다" → ORDERED 감지 시 push 자동
//
// 폴링: 3초 간격으로 GET /sessions/:id, GET /sessions/:id/members,
//      GET /sessions/:id/votes 를 모아 진행도/결과를 갱신.
//
// 디자인 토큰: Theme.of(context).colorScheme.primary, AppColors.*,
//             primary.withAlpha(15/25/40) 만 사용. 새 색상 추가 금지.
//
// 화면 구성:
//   1) 상단 안내 배너 (투표 진행 중 안내 + 다음 액션)
//   2) 진행도 카드: LinearProgressIndicator + "N/M명 투표 완료"
//   3) 결과 차트: 식당별 가로 바 (voteCount + percentage + 1·2·3등 강조)
//   4) 본인 액션:
//        - 아직 투표 안 함 → 추천 식당 카드 리스트 (탭 → castVote)
//        - 이미 투표 → "투표 완료" 표시
//   5) 호스트 전용 "투표 종료하기" CTA (전원 투표 시 활성)
//   6) ORDERED 감지 시 MenuScreen 으로 pushReplacement
// ══════════════════════════════════════════════════════════

class VoteProgressScreen extends ConsumerStatefulWidget {
  const VoteProgressScreen({
    super.key,
    required this.sessionId,
    required this.sessionName,
  });

  /// 폴링/투표 대상 세션 UUID
  final String sessionId;

  /// 상단 헤더 표시용 세션 이름 (호출부에서 그대로 넘겨받음)
  final String sessionName;

  @override
  ConsumerState<VoteProgressScreen> createState() =>
      _VoteProgressScreenState();
}

class _VoteProgressScreenState extends ConsumerState<VoteProgressScreen>
    with WidgetsBindingObserver {
  // ── API 클라이언트 ────────────────────────────────────
  static const _sessionsApi = SessionsApiService();
  static const _votesApi = VotesApiService();
  static const _recApi = RecommendationsApiService();

  // ── 폴링/생명주기 ────────────────────────────────────
  Timer? _pollingTimer;

  // ── 데이터 캐시 ──────────────────────────────────────
  // 세션 상세 — 상태(VOTING/ORDERED) + 호스트 user id 판별용.
  // winnerRestaurantId 자체는 별도 보관하지 않고, 폴링 사이클마다 session
  // 응답에서 직접 추출 → _navigateToMenu 인자로 흘려보낸다. (필드로 들고
  // 있어도 다시 읽지 않아 unused_field warning 이 떴기 때문.)
  String? _status;
  String? _hostUserId;

  // 추천 식당 리스트 — 투표 후보 카드 + 결과 row 이름 보강용
  List<RecommendationDto> _recommendations = const [];

  // 멤버 분모 (joinedCount) — 진행도 계산용
  int _totalMembers = 0;

  // Phase D 추가: 멤버 목록 (id+name+isHost) — 누가 투표했고 누가 대기 중인지
  // 가시화하기 위한 데이터. _refreshOnce 폴링마다 GET /sessions/:id/members
  // 응답의 members 배열을 그대로 보관. 빈 리스트면 _buildMembersList 안 그림.
  List<SessionMember> _members = const <SessionMember>[];

  // 투표 진행도 + 결과 (VotesApiService 가 raw 배열을 집계해 만든 DTO)
  VotesProgressDto? _progress;

  // 본인이 투표한 식당 id — UI 가 "투표 완료" 표시·중복 차단에 사용.
  // null 이면 아직 미투표 또는 알 수 없음.
  String? _myVotedRestaurantId;

  // 초기 로딩 — 처음 데이터 도착 전엔 스피너만 표시
  bool _isLoading = true;

  // 본인 castVote 진행 중 — 중복 클릭 방지
  bool _isCastingVote = false;

  // 호스트 decide 진행 중 — 중복 클릭 방지
  bool _isDeciding = false;

  // ORDERED 자동 라우팅 가드 — 폴링이 3초마다 도는데 ORDERED 감지 시점에
  // 매 사이클 pushReplacement 가 또 호출되면 위젯 트리가 꼬임.
  bool _autoNavigatedToOrdered = false;

  // 마지막 에러 메시지 — 토스트 대신 화면 하단에 살짝 표시
  String? _lastError;

  // ── 생명주기 ──────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-14');
      _bootstrapAndStartPolling();
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
    // 백그라운드 진입 시 폴링 중단 → 배터리/네트워크 보호
    if (state == AppLifecycleState.paused) {
      _pollingTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      // 투표 현황 화면이 현재 최상위일 때만 폴링 재시작
      if (ModalRoute.of(context)?.isCurrent != true) return;
      // 복귀 시 즉시 1회 갱신 + 폴링 재시작
      _refreshOnce();
      _startPolling();
    }
  }

  // ── 초기 로딩 + 폴링 시작 ────────────────────────────
  // 추천 식당 리스트는 한 번만 가져오면 충분 (세션 동안 후보는 고정).
  // 진행도/멤버 수는 3초마다 갱신.
  Future<void> _bootstrapAndStartPolling() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      setState(() {
        _isLoading = false;
        _lastError = '로그인이 풀렸어요. 다시 로그인해봐요';
      });
      return;
    }

    // 추천 리스트 — 세션 멤버 조건 기반 후보 (백엔드 캐시 가능)
    final recs = await _recApi.getRecommendations(
      accessToken: token,
      sessionId: widget.sessionId,
    );
    if (!mounted) return;
    setState(() {
      _recommendations = recs;
    });

    // 첫 진행도 + 세션 상태 동기화 1회
    await _refreshOnce();
    if (!mounted) return;
    setState(() => _isLoading = false);

    _startPolling();
  }

  // ── 3초 폴링 ─────────────────────────────────────────
  // 폴링 사이클마다:
  //   1) GET /sessions/:id          (status + winner_restaurant_id)
  //   2) GET /sessions/:id/members  (totalMembers)
  //   3) GET /sessions/:id/votes    (raw 배열 → VotesProgressDto)
  //
  // 위 3개를 직렬이 아닌 거의 동시(병렬) 로 실행해 지연을 최소화.
  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshOnce();
    });
  }

  Future<void> _refreshOnce() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    // 1) 세션 상세 → status / winner_restaurant_id / host id
    final sessionFuture = _sessionsApi.getSessionById(
      accessToken: token,
      sessionId: widget.sessionId,
    );

    // 2) 멤버 목록 → joinedCount = totalMembers
    final membersFuture = _sessionsApi.getSessionMembers(
      accessToken: token,
      sessionId: widget.sessionId,
    );

    // 두 호출 먼저 끝낸 뒤 그 결과로 votes 호출 (isFinished/winnerId 필요)
    final session = await sessionFuture;
    final members = await membersFuture;
    if (!mounted) return;

    final isFinished = session?.status == 'ORDERED' ||
        session?.status == 'DONE';
    final winnerId = session?.winnerRestaurantId;

    // 3) raw 투표 데이터 → 진행도 DTO 변환
    final progress = await _votesApi.getVotes(
      accessToken: token,
      sessionId: widget.sessionId,
      totalMembers: members?.joinedCount ?? 0,
      isFinished: isFinished,
      winnerRestaurantId: winnerId,
    );
    if (!mounted) return;

    // 본인 투표 식당 추적: GET /votes 응답에는 userId 가 raw 로 들어있지만
    // VotesProgressDto 는 집계만 보관 → 자체로 본인 투표 여부 모름.
    // 별도 raw 조회는 비용이 크므로, castVote 성공 시점에 본 상태를
    // 직접 set 하는 방식으로 충분. (페이지 재진입 케이스는 모름 — 빈상태로 시작)

    setState(() {
      _status = session?.status;
      _hostUserId = session?.createdBy?.id;
      _totalMembers = members?.joinedCount ?? _totalMembers;
      _members = members?.members ?? _members;
      _progress = progress;
    });

    // ── ORDERED 자동 라우팅 ────────────────────────────
    // 사장님 핵심 요구 #2: "투표 끝나면 자동으로 메뉴 선택 화면으로"
    // 가드: _autoNavigatedToOrdered 로 1회만 실행.
    if (!_autoNavigatedToOrdered &&
        session?.status == 'ORDERED' &&
        winnerId != null &&
        winnerId.isNotEmpty) {
      _autoNavigatedToOrdered = true;
      _navigateToMenu(winnerRestaurantId: winnerId);
    }
  }

  // ── 메뉴 화면으로 자동 라우팅 ────────────────────────
  // 우승 식당 이름은 추천 리스트에서 찾아 보강 (없으면 progress.winner 이름).
  // MenuScreen 은 restaurantId + restaurantName + sessionId 를 받음.
  void _navigateToMenu({required String winnerRestaurantId}) {
    // 다음 프레임에 라우팅 — 폴링 콜백 안에서 직접 push 하면
    // build 사이클과 충돌해 예외가 날 수 있음.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 우승 식당 이름 보강 (UI 친근 메시지용)
      String name = '결정된 식당';
      for (final r in _recommendations) {
        if (r.restaurantId == winnerRestaurantId) {
          name = r.name;
          break;
        }
      }
      final winnerNameFromProgress = _progress?.winner?.restaurantName;
      if (winnerNameFromProgress != null &&
          winnerNameFromProgress.isNotEmpty) {
        name = winnerNameFromProgress;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"$name" 으로 결정됐어요! 메뉴 골라봐요',
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MenuScreen(
            restaurantId: winnerRestaurantId,
            restaurantName: name,
            sessionId: widget.sessionId,
          ),
        ),
      );
    });
  }

  // ── 본인 투표 ────────────────────────────────────────
  // 1인 1표라 한 번만 가능. 백엔드가 409 로 차단하지만 UI 에서도 가드.
  Future<void> _onCastVote(RecommendationDto rec) async {
    if (_isCastingVote) return; // 중복 클릭 방지
    if (_myVotedRestaurantId != null) {
      // 이미 투표 — 친근 안내
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이미 투표했어요. 결과를 함께 지켜봐요'),
        ),
      );
      return;
    }
    if (_status != 'VOTING') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('지금은 투표할 수 없어요. 잠시 후 다시 시도해봐요'),
        ),
      );
      return;
    }

    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 풀렸어요. 다시 로그인해봐요')),
      );
      return;
    }

    setState(() => _isCastingVote = true);

    final result = await _votesApi.castVote(
      accessToken: token,
      sessionId: widget.sessionId,
      restaurantId: rec.restaurantId,
    );

    if (!mounted) return;
    setState(() => _isCastingVote = false);

    if (result.isSuccess) {
      // 본인 투표 식당 캐시 + 즉시 진행도 갱신 (3초 기다리지 않고 빠른 피드백)
      setState(() {
        _myVotedRestaurantId = rec.restaurantId;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${rec.name}" 에 한 표! 결과를 함께 지켜봐요'),
          duration: const Duration(seconds: 2),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      _refreshOnce();
    } else if (result.alreadyVoted) {
      // 백엔드가 409 → 본인은 다른 식당에 이미 투표한 상태.
      // 어느 식당인지 알 수는 없어 일반 안내 + 진행도 갱신만 수행.
      setState(() {
        _myVotedRestaurantId = rec.restaurantId; // 적어도 더 못 누르도록 잠금
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? '이미 투표했어요')),
      );
      _refreshOnce();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? '투표가 안 됐어요. 다시 시도해봐요')),
      );
    }
  }

  // ── 호스트: 투표 종료 (decide) ────────────────────────
  // 전원 투표 시 활성. 호스트가 아니면 백엔드가 403 → 토스트 안내.
  Future<void> _onDecide() async {
    if (_isDeciding) return;
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 풀렸어요. 다시 로그인해봐요')),
      );
      return;
    }

    setState(() => _isDeciding = true);
    final res = await _votesApi.decide(
      accessToken: token,
      sessionId: widget.sessionId,
    );
    if (!mounted) return;
    setState(() => _isDeciding = false);

    if (res != null && res.winnerRestaurantId.isNotEmpty) {
      // decide 성공 → 곧 폴링이 ORDERED 를 감지해 메뉴 화면으로 라우팅.
      // 단, 사용자 체감을 위해 즉시 status 를 setState 해 진행도 카드에 반영.
      setState(() {
        _status = 'ORDERED';
      });
      // 즉시 메뉴 라우팅 — 자동 라우팅 가드 함께 set
      _autoNavigatedToOrdered = true;
      _navigateToMenu(winnerRestaurantId: res.winnerRestaurantId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('투표를 종료하지 못했어요. 잠시 후 다시 시도해봐요'),
        ),
      );
    }
  }

  // ── 현재 사용자가 호스트인지 ─────────────────────────
  // userProvider.userId 와 session.createdBy.id 비교 (소문자/공백 정규화)
  bool get _isHost {
    final me = ref.read(userProvider).userId;
    if (me == null || _hostUserId == null) return false;
    return me.trim().toLowerCase() == _hostUserId!.trim().toLowerCase();
  }

  // ──────────────────────────────────────────────────────
  // build
  // ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(showBack: true, title: '투표 현황'),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    // 빈 상태: 추천 0개 — castVote 할 후보가 없는 케이스
    if (_recommendations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.how_to_vote_outlined,
                size: 48,
                color: AppColors.iconInactive,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '아직 후보 식당이 없어요',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '추천이 만들어진 뒤 다시 들어와봐요',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textHint,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppPrimaryButton(
                label: '뒤로가기',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.md,
        AppSpacing.screenHorizontal,
        AppSpacing.xl,
      ),
      children: [
        // ── 상단 안내 배너 ────────────────────────────
        _buildBanner(),
        const SizedBox(height: AppSpacing.md),

        // ── 진행도 카드 ───────────────────────────────
        _buildProgressCard(),
        const SizedBox(height: AppSpacing.md),

        // ── 멤버별 ✓/대기 카드 (Phase D, 2026-05-15) ─
        // 사장님 시연 피드백: "다른 팀원들 투표 어떻게 되는지 모르겠다"
        // 멤버 목록 + 투표 완료 여부를 한 화면에 시각화.
        if (_members.isNotEmpty) ...[
          _buildMembersList(),
          const SizedBox(height: AppSpacing.md),
        ],

        // ── 결과 차트 ────────────────────────────────
        if ((_progress?.results.isNotEmpty ?? false)) ...[
          Text(
            '실시간 결과',
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildResultsChart(),
          const SizedBox(height: AppSpacing.md),
        ],

        // ── 본인 액션 영역 ────────────────────────────
        _buildMyActionSection(),

        // ── 호스트 전용 종료 CTA ─────────────────────
        if (_isHost) ...[
          const SizedBox(height: AppSpacing.md),
          _buildHostDecideButton(),
        ],

        // ── 에러 안내 (있으면) ────────────────────────
        if (_lastError != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _lastError!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  // ── 상단 안내 배너 ───────────────────────────────────
  // 사장님 시연 피드백: "투표 어떻게 진행되는지 모름" → 화면 진입과 동시에
  // "지금 무엇을 해야 하는지"를 한 줄로 알린다.
  Widget _buildBanner() {
    final primary = Theme.of(context).colorScheme.primary;
    final isVoting = _status == 'VOTING';
    final title = isVoting
        ? '투표 진행 중이에요'
        : (_status == 'ORDERED' ? '결과가 나왔어요!' : '곧 투표가 시작돼요');
    final subtitle = isVoting
        ? '아래 추천 중 하나를 골라봐요. 전원이 투표하면 결과가 자동으로 확정돼요.'
        : (_status == 'ORDERED'
            ? '잠시 후 메뉴 선택 화면으로 이동해요'
            : '방장이 투표를 시작하면 바로 진행할 수 있어요');
    final icon = isVoting
        ? Icons.how_to_vote_rounded
        : (_status == 'ORDERED'
            ? Icons.emoji_events_rounded
            : Icons.hourglass_top_rounded);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: primary.withAlpha(15),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: primary.withAlpha(40)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 진행도 카드 ───────────────────────────────────────
  // "N/M명 투표 완료" + LinearProgressIndicator (분모: totalMembers).
  // totalMembers 가 0 이면(멤버 응답 실패) votedCount 만 텍스트로 표시.
  Widget _buildProgressCard() {
    final primary = Theme.of(context).colorScheme.primary;
    final voted = _progress?.votedCount ?? 0;
    final total = _totalMembers;
    final ratio = total == 0 ? 0.0 : (voted / total).clamp(0.0, 1.0);
    final everyoneVoted = total > 0 && voted >= total;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, size: 18, color: primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  total == 0
                      ? '$voted명 투표함'
                      : '$voted / $total 명 투표 완료',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (everyoneVoted)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    '전원 완료',
                    style: AppTextStyles.caption.copyWith(
                      color: primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // LinearProgressIndicator — 디자인 토큰(primary)만 사용
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? null : ratio,
              backgroundColor: primary.withAlpha(15),
              color: primary,
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  // ── 멤버별 ✓/대기 가시화 카드 (Phase D 신규) ──────────
  // 사장님 시연 피드백: "다른 팀원들 투표 어떻게 되는지 모르겠다"
  //
  // 데이터:
  //   - _members         GET /sessions/:id/members 응답의 멤버 배열
  //   - votedUserIds     VotesProgressDto.votedUserIds (이번 사이클 raw votes 의 userId 집합)
  //
  // 표시:
  //   각 멤버 한 줄 — 아바타(이름 첫 글자) + 이름 + 방장 chip + 우측 ✓투표완료 / 대기중
  //
  // 디자인 토큰만 사용 (primary.withAlpha) — 새 색상 추가 없음.
  Widget _buildMembersList() {
    final primary = Theme.of(context).colorScheme.primary;
    final voted = _progress?.votedUserIds ?? const <String>{};

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_outline_rounded, size: 18, color: primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '참여 멤버 (${_members.length}명)',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._members.map((m) {
            final hasVoted = voted.contains(m.id);
            final name = (m.name ?? '').trim();
            final initial = name.isEmpty ? '?' : name[0];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: hasVoted
                        ? primary.withAlpha(40)
                        : AppColors.backgroundGrey,
                    child: Text(
                      initial,
                      style: AppTextStyles.caption.copyWith(
                        color: hasVoted ? primary : AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            name.isEmpty ? '이름 없음' : name,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (m.isHost) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: primary.withAlpha(25),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.chip),
                            ),
                            child: Text(
                              '방장',
                              style: AppTextStyles.caption.copyWith(
                                color: primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 투표 완료 / 대기 중 표시
                  Icon(
                    hasVoted
                        ? Icons.check_circle_rounded
                        : Icons.hourglass_top_rounded,
                    size: 16,
                    color: hasVoted ? primary : AppColors.textHint,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    hasVoted ? '투표 완료' : '대기 중',
                    style: AppTextStyles.caption.copyWith(
                      color: hasVoted ? primary : AppColors.textHint,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── 결과 차트 (식당별 가로 바) ─────────────────────────
  // 한 row = 식당 한 곳. 표 수 + 퍼센티지 + 1·2·3등 강조.
  // 본인이 투표한 식당은 별 아이콘으로 표시 (재미 요소 + 본인 확인).
  Widget _buildResultsChart() {
    final primary = Theme.of(context).colorScheme.primary;
    final results = _progress!.results;

    return Column(
      children: List.generate(results.length, (i) {
        final r = results[i];
        final rank = i + 1;
        final isTop = rank <= 3;
        final isMine = _myVotedRestaurantId == r.restaurantId;

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: isMine ? primary : AppColors.border,
              width: isMine ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 식당 이름 + 순위 ──────────────────
              Row(
                children: [
                  // 순위 배지 (1·2·3등은 강조, 그 외 회색)
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isTop ? primary : AppColors.backgroundGrey,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$rank',
                      style: AppTextStyles.caption.copyWith(
                        color: isTop ? Colors.white : AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      r.restaurantName.isEmpty ? '식당' : r.restaurantName,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isMine) ...[
                    Icon(Icons.star_rounded, size: 16, color: primary),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    '${r.voteCount}표 · ${r.percentage}%',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // ── 가로 바 ───────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (r.percentage / 100.0).clamp(0.0, 1.0),
                  backgroundColor: primary.withAlpha(15),
                  color: isTop ? primary : primary.withAlpha(120),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ── 본인 액션 섹션 ───────────────────────────────────
  // 미투표 → 추천 카드 리스트 (탭하면 castVote)
  // 투표 완료 → "투표 완료" 안내 카드
  Widget _buildMyActionSection() {
    if (_myVotedRestaurantId != null) {
      // 이미 투표 완료 — 결과만 지켜보는 단계
      final primary = Theme.of(context).colorScheme.primary;
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: primary.withAlpha(15),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: primary.withAlpha(40)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 20, color: primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '투표를 마쳤어요! 다른 멤버 결과를 함께 지켜봐요',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 미투표 — 추천 카드 리스트 노출 (탭하면 castVote)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '내가 가고 싶은 식당을 골라봐요',
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // 후보 식당 카드 리스트 — 상위 추천 그대로 사용
        ...List.generate(_recommendations.length, (i) {
          final r = _recommendations[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _buildVoteCandidateCard(r, i + 1),
          );
        }),
      ],
    );
  }

  // ── 투표 후보 카드 (탭하면 castVote) ──────────────────
  // 디자인은 추천 리스트 카드와 동일한 톤 — primary.withAlpha 만 사용.
  // VOTING 이 아닐 땐 onTap=null 로 비활성 시각 유지.
  Widget _buildVoteCandidateCard(RecommendationDto rec, int rank) {
    final primary = Theme.of(context).colorScheme.primary;
    final canVote = _status == 'VOTING' && !_isCastingVote;

    return AppCard(
      onTap: canVote ? () => _onCastVote(rec) : null,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          // 순위 배지
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rank <= 3 ? primary : AppColors.backgroundGrey,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: AppTextStyles.label.copyWith(
                color: rank <= 3 ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // 이름 + 카테고리
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rec.name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (rec.category != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      rec.category!,
                      style: AppTextStyles.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          // 투표 액션 표시
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: primary.withAlpha(canVote ? 25 : 15),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.how_to_vote_rounded,
                  size: 14,
                  color: canVote ? primary : AppColors.textHint,
                ),
                const SizedBox(width: 4),
                Text(
                  '투표하기',
                  style: AppTextStyles.caption.copyWith(
                    color: canVote ? primary : AppColors.textHint,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 호스트 전용 종료 버튼 ────────────────────────────
  // 전원 투표 시 활성 — 그 전엔 회색(비활성) 으로 잠금.
  // 백엔드 decide 는 호스트 권한 + VOTING 상태에서만 통과.
  Widget _buildHostDecideButton() {
    final voted = _progress?.votedCount ?? 0;
    final total = _totalMembers;
    final everyoneVoted = total > 0 && voted >= total;
    // 한 명이라도 투표했다면 호스트 종료 권한은 있으나, "전원 투표" 기준으로
    // 활성화해 의도치 않은 조기 종료를 방지. (필요시 길게 눌러 강제 종료 같은
    // 보조 동선을 후속 티켓으로 추가 가능)
    final canDecide = _status == 'VOTING' && everyoneVoted && !_isDeciding;

    return AppPrimaryButton(
      label: _isDeciding
          ? '결과 확정 중...'
          : (everyoneVoted ? '투표 종료하기' : '전원이 투표하면 종료할 수 있어요'),
      onPressed: canDecide ? _onDecide : null,
    );
  }
}
