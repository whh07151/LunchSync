import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../models/session.dart';
import '../../providers/user_provider.dart';
import '../../services/sessions_api_service.dart';
import 'recommendation_list_screen.dart';
import '../menu/menu_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 세션 로비 화면 (CU-10)
//
// 진입 경로:
//   1. 세션 생성 후 (호스트) — inviteCode 포함
//   2. 초대코드 수락 후 (참가자) — inviteCode 없음
//
// 주요 기능:
//   - 초대코드 표시 + 클립보드 복사 + 공유 시트(웹: Web Share API)
//   - 세션 멤버 목록 (3초 폴링)
//   - 세션 상태 표시
//   - 세션 조건(예산/반경/복귀시간) 칩 표시
//   - scheduledAt 기반 점심시간 카운트다운 (1초 갱신)
//   - **자동 라우팅**: 폴링 도중 status 가 VOTING 으로 바뀌면
//     멤버 화면도 즉시 RecommendationListScreen 으로 자동 이동.
//     → 사장님 시연 피드백("투표 시작 이후 어디서 투표하는지 모름") 해결.
//
// 폴링: Timer.periodic 3초 간격 (멤버 목록 + 세션 상세)
//   백그라운드 진입 시 취소, 복귀 시 재시작 (WidgetsBindingObserver)
//
// 카운트다운 타이머: Timer.periodic 1초 간격
//   scheduledAt 가 미래일 때만 활성. 지나면 "지금 점심시간이에요" 안내.
// ══════════════════════════════════════════════════════════

class SessionLobbyScreen extends ConsumerStatefulWidget {
  const SessionLobbyScreen({
    super.key,
    required this.sessionId,
    this.inviteCode,   // 호스트만 가짐. null이면 참가자 화면
    this.initialSession, // createSession / getByCode 응답을 바로 넘기면 첫 로딩 생략
  });

  final String sessionId;
  final String? inviteCode;
  final Session? initialSession;

  @override
  ConsumerState<SessionLobbyScreen> createState() => _SessionLobbyScreenState();
}

class _SessionLobbyScreenState extends ConsumerState<SessionLobbyScreen>
    with WidgetsBindingObserver {

  // ── 상태 변수 ─────────────────────────────────────────
  Session? _session;                    // 세션 기본 정보
  SessionMembersResponse? _membersData; // 멤버 목록 + 카운트
  bool _isLoading = false;              // initialSession이 있으면 처음부터 false
  String? _errorMessage;                // 에러 메시지
  Timer? _pollingTimer;                 // 멤버 목록 폴링 타이머 (3초)
  Timer? _countdownTimer;               // 점심 카운트다운 타이머 (1초)

  // 카운트다운에 사용할 "현재 시각" — 1초마다 갱신해 UI rebuild 유도.
  DateTime _now = DateTime.now();

  // ── 자동 라우팅 가드 ─────────────────────────────────────
  // 폴링이 3초마다 돌며 status==VOTING 을 감지하면 RecommendationListScreen 으로
  // 자동 이동시킨다. 이때 push 한 번 띄운 뒤에도 폴링이 계속 돌고 있으면
  // 매 사이클마다 push 가 또 호출돼 화면이 여러 장 쌓이는 버그가 생긴다.
  // _autoNavigatedToVoting=true 로 한 번만 이동하도록 잠근다.
  bool _autoNavigatedToVoting = false;

  // ── ORDERED 자동 라우팅 가드 (사장님 핵심 요구 #2) ───────────
  // 호스트가 decide 를 누르거나 전원 투표로 결과가 확정되면 status 가
  // ORDERED 로 바뀌고 winner_restaurant_id 가 채워진다. 이때 멤버 전원이
  // 메뉴 선택 화면으로 자연스럽게 이동해야 "결정 → 주문" 흐름이 끊기지 않는다.
  // _autoNavigatedToOrdered=true 로 1회만 실행 (중복 push 방지).
  bool _autoNavigatedToOrdered = false;

  static const _sessionsApi = SessionsApiService();

  // ── 생명주기 ──────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DebugToast.show(context, 'CU-10');
    // initialSession이 있으면 바로 표시, 없으면 API로 로드
    if (widget.initialSession != null) {
      _session = widget.initialSession;
    } else {
      _isLoading = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialSession == null) _loadAll();
      _loadMembers(); // 멤버 목록은 항상 최초 1회 로드
      // 진입 즉시 세션 상태도 1회 점검 — initialSession 으로 들어왔어도
      // 그 사이 방장이 이미 투표를 시작했을 수 있음(딥링크/뒤로가기 경로).
      _loadSessionStatus();
      _startPolling();
      _startCountdown();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── 점심 카운트다운: 1초마다 _now 갱신 → build() 재호출 → 표시 갱신 ──
  // scheduledAt 미설정 세션에는 타이머 자체를 시작하지 않는다.
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  // ── 앱 포그라운드/백그라운드 전환 감지 ─────────────────
  // 백그라운드: 폴링·카운트다운 중단 (배터리 보호)
  // 포그라운드: 두 타이머 재시작
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pollingTimer?.cancel();
      _countdownTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _loadMembers(); // 즉시 1회 갱신
      _startPolling();
      _startCountdown();
    }
  }

  // ── 세션 정보 + 멤버 목록 동시 로드 (initialSession 없을 때만 호출) ──
  Future<void> _loadAll() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    try {
      final session = await _sessionsApi.getSessionById(
          accessToken: token, sessionId: widget.sessionId);

      if (!mounted) return;
      setState(() {
        _session = session;
        _isLoading = false;
        _errorMessage = session == null ? '세션 정보를 불러오지 못했어요.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '세션 정보를 불러오지 못했어요.';
      });
    }
  }

  // ── 멤버 목록만 갱신 (최초 로드 + 폴링용) ────────────
  Future<void> _loadMembers() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    final result = await _sessionsApi.getSessionMembers(
        accessToken: token, sessionId: widget.sessionId);
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _membersData = result;
        _isLoading = false; // 멤버 로드 완료 시 로딩 해제
      });
    }
  }

  // ── 세션 상세 갱신 (폴링용) ─────────────────────────────
  // 멤버 목록과 별도로 status 변화를 감지하기 위해 1회 추가 호출한다.
  // VOTING 으로 바뀌면 자동으로 추천 리스트 화면으로 멤버를 데려간다.
  // (이전에는 폴링이 멤버만 갱신해서, 방장이 "투표 시작" 을 눌러도 멤버 화면이
  //  로비에 그대로 머물러 "어디서 투표하지?" 라는 시연 피드백이 나왔음)
  Future<void> _loadSessionStatus() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    final session = await _sessionsApi.getSessionById(
        accessToken: token, sessionId: widget.sessionId);
    if (!mounted || session == null) return;

    setState(() {
      _session = session;
    });

    // status 가 VOTING 이고 아직 자동 이동을 안 했으면 즉시 추천 화면으로 push.
    // 방장은 이미 _startVoting() 흐름에서 직접 push 하므로 _autoNavigatedToVoting
    // 플래그가 켜져 있어 중복 이동되지 않는다.
    if (session.status == 'VOTING' && !_autoNavigatedToVoting) {
      _autoNavigatedToVoting = true;
      // 폴링 콜백 안에서 직접 라우팅하면 setState 와 충돌하기 쉬워 다음 프레임에 예약.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _goToRecommendations(autoTransition: true);
      });
    }

    // ── ORDERED 자동 라우팅 (사장님 핵심 요구 #2) ─────────
    // 결과 확정 직후 모든 멤버가 메뉴 선택 화면으로 자동 진입.
    //   - winner_restaurant_id 가 비어 있으면(에지 케이스) 라우팅 보류.
    //   - 본 로비 화면을 그대로 두면 사용자가 뒤로가기 시 다시 돌아올 수 있어
    //     pushReplacement 가 아닌 push 사용. ("결제 후 로비로 복귀" 동선 유지)
    if (session.status == 'ORDERED' &&
        !_autoNavigatedToOrdered &&
        (session.winnerRestaurantId ?? '').isNotEmpty) {
      _autoNavigatedToOrdered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _goToMenuForWinner(session.winnerRestaurantId!);
      });
    }
  }

  // ── 우승 식당 메뉴 화면으로 이동 ─────────────────────────
  // ORDERED 감지 시 호출. 친근 토스트 + MenuScreen push.
  // 식당 이름은 우선 session 모델에 없어 fallback 으로 sessionName 또는
  // "결정된 식당" 사용. (백엔드가 winnerRestaurantName 도 함께 내려주면 더 정확)
  void _goToMenuForWinner(String winnerRestaurantId) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('이 식당으로 결정됐어요! 메뉴 골라봐요'),
        duration: Duration(seconds: 3),
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MenuScreen(
          restaurantId: winnerRestaurantId,
          restaurantName: '결정된 식당', // 백엔드 winner 이름 미지원 — fallback
          sessionId: widget.sessionId,
        ),
      ),
    ).then((_) {
      // 메뉴 화면에서 돌아왔을 때 status 가 여전히 ORDERED 면 가드는 유지.
      // DONE 으로 바뀌었다면 자동 라우팅이 다시 발동할 일이 없으므로 그대로 둠.
    });
  }

  // ── 3초 폴링 시작 ──────────────────────────────────────
  // 멤버 목록 + 세션 상세를 함께 갱신.
  // 세션 상세 폴링은 status 변화 감지용이고, 변화가 감지되면
  // _loadSessionStatus() 내부에서 자동 라우팅을 수행한다.
  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadMembers();
      _loadSessionStatus();
    });
  }

  // ── AI 추천 리스트 화면으로 이동 ────────────────────────
  // [autoTransition] true 면 status 폴링이 트리거한 자동 이동.
  //   - 안내 스낵바를 1회 보여 사용자에게 "왜 화면이 바뀌었는지" 알려준다.
  //   - 시연 피드백("어디서 투표하나요?") 의 핵심 해결 지점.
  void _goToRecommendations({bool autoTransition = false}) {
    if (autoTransition) {
      // 친근 톤 + 다음 액션(고르기) 명시
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('투표가 시작됐어요! 마음에 드는 식당을 골라봐요'),
          duration: Duration(seconds: 3),
        ),
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecommendationListScreen(
          sessionId: widget.sessionId,
          sessionName: _session?.name ?? '점심 세션',
        ),
      ),
    ).then((_) {
      // 추천 화면에서 돌아왔을 때 다시 자동 이동이 발동하지 않도록
      // 잠금을 유지한다. (status 가 여전히 VOTING 이면 push 또 시도될 수 있음)
      // 단 status 가 WAITING 으로 되돌아간 경우엔 다시 감지하도록 해제.
      if (!mounted) return;
      if (_session?.status != 'VOTING') {
        _autoNavigatedToVoting = false;
      }
    });
  }

  // ── 초대코드 클립보드 복사 ─────────────────────────────
  Future<void> _copyInviteCode() async {
    await Clipboard.setData(ClipboardData(text: widget.inviteCode!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('초대 코드가 복사됐어요!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ── 초대 공유 시트 — 친구에게 카톡 메시지 / 링크 복사 ──
  // 시연 친화적으로 메시지 미리보기와 두 가지 액션(메시지 복사 / 코드만 복사)을 제공.
  // 카톡 SDK 의 인앱 공유는 추후 통합 가능 (현재는 텍스트 복사로 fallback).
  Future<void> _openShareSheet() async {
    final inviteCode = widget.inviteCode!;
    final sessionName = _session?.name ?? '점심 세션';
    final shareMessage =
        '$sessionName 에 초대합니다!\n'
        'LunchSync 앱에서 아래 코드를 입력해주세요:\n'
        '\n📋 초대 코드: $inviteCode\n'
        '⏰ 24시간 동안 유효해요.';

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context).colorScheme.primary;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 4,
                  width: 40,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text('친구에게 초대 보내기',
                    style: AppTextStyles.heading3),
                const SizedBox(height: 4),
                Text(
                  '아래 메시지를 카카오톡·문자 등에 붙여 넣으세요.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundGrey,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SelectableText(
                    shareMessage,
                    style: AppTextStyles.bodySmall,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(sheetCtx).pop();
                    await Clipboard.setData(ClipboardData(text: shareMessage));
                    messenger.showSnackBar(
                      const SnackBar(
                        // 다음 액션 명시 — 어디에 붙여넣을지 안내
        content: Text('초대 메시지를 복사했어요! 카톡에 붙여 넣어 보내봐요'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                  label: const Text('메시지 전체 복사'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(sheetCtx).pop();
                    await Clipboard.setData(ClipboardData(text: inviteCode));
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('초대 코드만 복사됐어요.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.numbers_rounded, size: 18),
                  label: const Text('초대 코드만 복사'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: BorderSide(color: AppColors.border),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── UI ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(showBack: true),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  // ── 에러 상태 ─────────────────────────────────────────
  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_errorMessage!, style: AppTextStyles.bodyMedium),
          const SizedBox(height: 16),
          AppPrimaryButton(
            label: '다시 시도',
            onPressed: () {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
              _loadAll();
            },
          ),
        ],
      ),
    );
  }

  // ── 정상 콘텐츠 ──────────────────────────────────────
  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.lg),

          // ── 세션 이름 + 상태 레이블 ───────────────────
          if (_session != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _session!.name,
                    style: AppTextStyles.heading1,
                  ),
                ),
                // 세션 상태 배지
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Text(
                    _session!.statusLabel ?? _session!.status,
                    style: AppTextStyles.label.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // ── 점심시간 카운트다운 ────────────────────────
            // scheduledAt 이 미래면 "11:32 후 점심시간" 같은 카드 표시.
            // 점심 시각 지난 후엔 "지금 점심시간이에요" 안내.
            // scheduledAt 미설정 세션이면 카드 자체 미노출.
            if (_session!.scheduledAt != null) _buildCountdownCard(),

            // ── 세션 조건 칩들 ─────────────────────────────
            // 예산 / 반경 / 복귀시간 — 호스트가 설정한 값을 멤버에게 노출.
            _buildConditionChips(),
            const SizedBox(height: AppSpacing.sm),
          ],

          // ── 초대코드 섹션 (호스트만 표시) ─────────────
          if (widget.inviteCode != null) ...[
            const SizedBox(height: AppSpacing.md),
            _buildInviteCodeCard(),
            const SizedBox(height: AppSpacing.lg),
          ] else
            const SizedBox(height: AppSpacing.md),

          // ── 멤버 목록 헤더 ─────────────────────────────
          Row(
            children: [
              Text('참여 멤버', style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
              )),
              const SizedBox(width: 8),
              if (_membersData != null)
                Text(
                  '${_membersData!.joinedCount}명',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              // 폴링 중임을 나타내는 작은 아이콘
              const Spacer(),
              const Icon(Icons.sync_rounded, size: 14, color: AppColors.textHint),
              const SizedBox(width: 4),
              Text('자동 갱신 중', style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textHint,
              )),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // ── 멤버 목록 ─────────────────────────────────
          Expanded(
            child: _membersData == null || _membersData!.members.isEmpty
                ? Center(
                    // 빈 상태 — 초대 코드 공유라는 다음 액션을 동시에 환기
                    child: Text('초대 코드를 공유해 멤버를 불러보세요',
                        style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary)),
                  )
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: _membersData!.members.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) => _buildMemberItem(_membersData!.members[i]),
                  ),
          ),

          // ── 메인 CTA 버튼 ───────────────────────────────
          // 현재 세션 상태에 따라 라벨이 달라진다:
          //   - WAITING: "AI 추천 보고 투표 시작하기" — 추천 화면으로 이동해
          //     거기서 방장이 "투표 시작하기" 버튼을 누르는 흐름.
          //   - VOTING:  "지금 투표하러 가기" — 이미 시작된 투표 화면으로 복귀.
          //     멤버에겐 사실상 자동 이동되지만, 자동 이동이 실패했거나
          //     사용자가 뒤로 돌아온 경우의 안전 진입 경로.
          //
          // 시연 피드백("투표가 어디서 진행되는지 모름") 해결 핵심:
          //   - 동사를 분명히("투표하러 가기")
          //   - VOTING 단계에서 강조색 + 깜빡임 같은 강조는 색상 변경 금지
          //     원칙에 따라 적용하지 않음. 라벨 텍스트와 자동 이동만으로 명확화.
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.md,
            ),
            child: AppPrimaryButton(
              label: _session?.status == 'VOTING'
                  ? '지금 투표하러 가기'
                  : 'AI 추천 보고 투표 시작하기',
              // tearoff 가 named optional 인자를 가져 VoidCallback 과 시그니처가
              // 달라서 분석 경고가 날 수 있어 명시적 람다로 감싼다.
              onPressed: () => _goToRecommendations(),
            ),
          ),
        ],
      ),
    );
  }

  // ── 초대코드 카드 ─────────────────────────────────────
  Widget _buildInviteCodeCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withAlpha(15),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withAlpha(60),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '초대 코드',
            style: AppTextStyles.label.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // 코드 문자 (크게 표시)
              Expanded(
                child: Text(
                  widget.inviteCode!,
                  style: AppTextStyles.heading1.copyWith(
                    letterSpacing: 4,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              // 복사 버튼 (단순 코드 복사)
              IconButton(
                onPressed: _copyInviteCode,
                icon: const Icon(Icons.copy_rounded),
                color: Theme.of(context).colorScheme.primary,
                tooltip: '코드 복사',
              ),
              // 공유 버튼 (메시지 미리보기 시트)
              IconButton(
                onPressed: _openShareSheet,
                icon: const Icon(Icons.ios_share_rounded),
                color: Theme.of(context).colorScheme.primary,
                tooltip: '공유 메시지 만들기',
              ),
            ],
          ),
          Text(
            '이 코드를 친구에게 공유하세요 (24시간 유효)',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // ── 점심 카운트다운 카드 ──────────────────────────────
  // scheduledAt 까지 남은 시간을 "HH시간 MM분 SS초" 형태로 표시.
  // 5분 이내로 남으면 강조색(주황), 지났으면 안내 메시지로 전환.
  Widget _buildCountdownCard() {
    final scheduled = DateTime.tryParse(_session!.scheduledAt!)?.toLocal();
    if (scheduled == null) return const SizedBox.shrink();

    final primary = Theme.of(context).colorScheme.primary;
    final remaining = scheduled.difference(_now);

    String label;
    IconData icon;
    Color accent;

    if (remaining.isNegative) {
      final passed = -remaining;
      label = passed.inMinutes < 60
          ? '점심시간이에요! (${passed.inMinutes}분 경과)'
          : '점심시간이 지났어요';
      icon = Icons.restaurant_rounded;
      accent = primary;
    } else {
      icon = Icons.access_time_rounded;
      if (remaining.inMinutes >= 60) {
        final h = remaining.inHours;
        final m = remaining.inMinutes % 60;
        label = '$h시간 $m분 후 점심시간';
        accent = AppColors.textPrimary;
      } else if (remaining.inMinutes >= 5) {
        final m = remaining.inMinutes;
        final s = remaining.inSeconds % 60;
        label = '$m분 ${s.toString().padLeft(2, '0')}초 남음';
        accent = AppColors.textPrimary;
      } else {
        final m = remaining.inMinutes;
        final s = remaining.inSeconds % 60;
        label = '곧 시작! $m분 ${s.toString().padLeft(2, '0')}초 남음';
        accent = primary;
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withAlpha(15),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: accent.withAlpha(40)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 세션 조건 칩 (예산/반경/복귀시간) ──────────────────
  Widget _buildConditionChips() {
    final session = _session!;
    final chips = <Widget>[];

    if (session.budget != null) {
      chips.add(_conditionChip(
        Icons.payments_outlined,
        '${_formatThousands(session.budget!)}원',
      ));
    }
    if (session.radius != null) {
      chips.add(_conditionChip(
        Icons.place_outlined,
        '반경 ${session.radius!}m',
      ));
    }
    if (session.returnMinutes != null) {
      chips.add(_conditionChip(
        Icons.timer_outlined,
        '${session.returnMinutes}분 안 복귀',
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );
  }

  Widget _conditionChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.backgroundGrey,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatThousands(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ── 멤버 항목 하나 ────────────────────────────────────
  Widget _buildMemberItem(SessionMember member) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // 프로필 아바타
          CircleAvatar(
            radius: 20,
            backgroundColor: member.isHost
                ? primary.withAlpha(40)
                : AppColors.backgroundGrey,
            child: Text(
              (member.name ?? '?')[0],
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: member.isHost ? primary : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),

          // 이름 + 소속
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      member.name ?? '알 수 없음',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (member.isHost) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: primary.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '방장',
                          style: AppTextStyles.label.copyWith(
                            color: primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (member.org != null)
                  Text(
                    member.org!,
                    style: AppTextStyles.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
