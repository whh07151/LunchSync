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

// ══════════════════════════════════════════════════════════
// 파일 역할: 세션 로비 화면 (CU-10 간소화 버전)
//
// 진입 경로:
//   1. 세션 생성 후 (호스트) — inviteCode 포함
//   2. 초대코드 수락 후 (참가자) — inviteCode 없음
//
// 주요 기능:
//   - 초대코드 표시 + 클립보드 복사 (호스트만)
//   - 세션 멤버 목록 (3초 폴링)
//   - 세션 상태 표시
//
// 폴링: Timer.periodic 3초 간격
//   백그라운드 진입 시 취소, 복귀 시 재시작 (WidgetsBindingObserver)
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
  Timer? _pollingTimer;                 // 멤버 목록 폴링 타이머

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
      _startPolling();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── 앱 포그라운드/백그라운드 전환 감지 ─────────────────
  // 백그라운드: 폴링 중단 (배터리 보호)
  // 포그라운드: 폴링 재시작
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pollingTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _loadMembers(); // 즉시 1회 갱신
      _startPolling();
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

  // ── 3초 폴링 시작 ──────────────────────────────────────
  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadMembers();
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
                    child: Text('아직 참여한 멤버가 없어요',
                        style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary)),
                  )
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: _membersData!.members.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) => _buildMemberItem(_membersData!.members[i]),
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
              // 복사 버튼
              IconButton(
                onPressed: _copyInviteCode,
                icon: const Icon(Icons.copy_rounded),
                color: Theme.of(context).colorScheme.primary,
                tooltip: '복사',
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
