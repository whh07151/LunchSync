import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/utils/normalizer.dart';
import '../../core/utils/distance_calculator.dart';
import '../../core/utils/distance_chip_helper.dart';
import '../../core/debug/debug_toast.dart';
import '../../models/restaurant.dart';
import '../../providers/user_provider.dart';
import '../../services/geolocation_service.dart';
import '../../services/recommendations_api_service.dart';
import '../../services/sessions_api_service.dart';
import '../decide/decide_screen.dart';
import '../map/recommendation_map_screen.dart';
import '../restaurant/restaurant_detail_screen.dart';
import '../restaurant/restaurant_comparison_screen.dart';
import 'vote_progress_screen.dart';
import 'widgets/chemistry_card.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-11 AI 추천 리스트 화면 (= 투표 화면)
//
// 진입 경로:
//   1. 세션 로비(CU-10) → "AI 추천 보고 투표 시작하기" 버튼 (방장/멤버)
//   2. 로비 폴링이 status==VOTING 을 감지 → 자동 라우팅 (멤버)
//   3. 추천 카드 탭 → 식당 상세(CU-12)
//
// 표시 내용:
//   - 상단 안내 배너: "이 중에서 골라봐요" 친근 카피 + 현재 상태(WAITING/VOTING)
//     시각화. 사장님 시연 피드백 "투표 어디서 하나요?" 해결 포인트.
//   - 세션 멤버 전원의 조건(예산/알레르기/비선호/최근식사)을 기반으로
//     백엔드 CORE-07/08 엔진이 계산한 추천 식당 상위 10개
//   - 각 카드에 이름 / 카테고리 / 가격대 / 점수 배지 / 추천 근거 태그
//
// 연동 API:
//   GET   /api/sessions/:id/recommendations  — 추천 리스트
//   PATCH /api/sessions/:id/status           — 방장의 "투표 시작" (WAITING→VOTING)
//
// 투표 시작 후 동작:
//   - 토스트만 띄우고 화면에 머무름. (이전엔 pop 으로 로비 복귀했으나
//     "다음에 뭘 하지?" 가 끊겼다는 시연 피드백에 따라 머무는 흐름으로 변경)
//   - 멤버는 로비 폴링이 같은 화면을 자동으로 push.
// ══════════════════════════════════════════════════════════

class RecommendationListScreen extends ConsumerStatefulWidget {
  const RecommendationListScreen({
    super.key,
    required this.sessionId,
    required this.sessionName,
  });

  final String sessionId;
  final String sessionName;

  @override
  ConsumerState<RecommendationListScreen> createState() =>
      _RecommendationListScreenState();
}

class _RecommendationListScreenState
    extends ConsumerState<RecommendationListScreen> {
  static const _api = RecommendationsApiService();

  List<RecommendationDto>? _recommendations;
  bool _isLoading = true;
  String? _errorMessage;

  // 현재 세션 상태 — 상단 안내 배너 문구 분기에 사용.
  //   WAITING: "투표 시작 전" — 방장이 시작하면 멤버 전원이 함께 진행됨을 안내.
  //   VOTING:  "투표 진행 중" — 마음에 드는 식당을 골라달라는 안내.
  //   기타:    배너 미노출 (이미 결정·종료된 세션)
  // 진입 시 1회 조회 + 방장의 "투표 시작" 성공 시점에 갱신.
  String? _sessionStatus;

  // 호스트 여부 — 미니게임(DecideScreen)·비교 화면에 isHost 인자로 전달.
  // session.createdBy.id 와 userProvider.userId 비교로 판단(소문자/공백 정규화).
  // 미로딩 상태(초기) 에는 false 로 가정해 비호스트(castVote) 동작으로 안전 폴백.
  bool _isHost = false;

  // 비교 모드 상태: true면 카드가 체크박스로 바뀌고 선택된 항목을 모음.
  // 선택 개수 2~3개일 때만 "비교하기" 버튼이 활성화됨.
  bool _isCompareMode = false;
  final Set<String> _selectedForCompare = <String>{};

  // ── 사용자 현재 위치(거리 표시용) ──────────────────────
  // 추천 카드 각각에 "거리 320m" 한 줄을 띄우기 위해 화면 진입 시 1회 조회.
  // 권한 거부/위치 서비스 꺼짐이면 영구히 null → 카드의 거리 라인은 자동 숨김.
  double? _userLat;
  double? _userLng;

  // ── WOW #3 점심 케미 매트릭스 ──────────────────────────
  // 진입 시 1회 호출(_loadChemistry). 백엔드 30분 캐시 덕에 같은 세션 재진입
  // 시에도 같은 응답 재사용 → Gemini 호출 횟수 절감.
  //   _chemistry        : null = 미수신(로딩 중) 또는 미노출 결정.
  //   _chemistryLoading : true 동안 스켈레톤 표시.
  //   _chemistryFailed  : 호출 실패 한 번이라도 발생 시 true — 카드 자체 미노출.
  ChemistryResult? _chemistry;
  bool _chemistryLoading = false;
  bool _chemistryFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-11');
      _loadRecommendations();
      _loadUserLocation();
      _loadSessionStatus();
      _loadChemistry(); // WOW #3 — Gemini 케미 매트릭스 1회 조회.
    });
  }

  // ── 세션 상태 1회 조회 ─────────────────────────────────
  // 진입 시 status (WAITING/VOTING/...) 를 가져와 상단 안내 배너 톤을 결정.
  // 폴링은 로비 화면에서 이미 수행 중 — 여기서는 한 번만 가져와도 충분.
  // 방장이 본 화면에서 "투표 시작" 을 누르면 _startVoting() 안에서
  // 직접 _sessionStatus 를 'VOTING' 으로 set 한다.
  Future<void> _loadSessionStatus() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    final session = await const SessionsApiService().getSessionById(
      accessToken: token,
      sessionId: widget.sessionId,
    );
    if (!mounted || session == null) return;
    // 호스트 판별 — 본 화면이 진입하는 미니게임/비교 화면에 isHost 인자를 넘기기 위해
    // session.createdBy.id 와 userProvider.userId 를 정규화해서 비교.
    final me = ref.read(userProvider).userId;
    final hostId = session.createdBy?.id;
    final isHost = (me != null && hostId != null) &&
        me.trim().toLowerCase() == hostId.trim().toLowerCase();
    setState(() {
      _sessionStatus = session.status;
      _isHost = isHost;
    });
  }

  // ── WOW #3 점심 케미 매트릭스 1회 조회 ─────────────────
  // 화면 진입 직후 호출. 백엔드는 30분 캐시 → 같은 세션 재진입도 부담 작음.
  // 실패 / 데이터 없음 / Gemini 키 없음 → null 반환 → 카드 자체 미노출.
  // 추천 리스트 렌더링과 완전 독립이라 실패해도 다른 영역에 영향 0.
  Future<void> _loadChemistry() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    setState(() => _chemistryLoading = true);
    final result = await const SessionsApiService().getChemistry(
      accessToken: token,
      sessionId: widget.sessionId,
    );
    if (!mounted) return;
    setState(() {
      _chemistry = result;
      _chemistryLoading = false;
      _chemistryFailed = result == null;
    });
  }

  // ── 사용자 위치 1회 조회 ──────────────────────────────
  // 화면 진입 시 GPS 1 스냅샷만 얻어 거리 표기에 사용.
  // 권한 거부/타임아웃 시 null 그대로 두어 거리 라인은 숨김.
  Future<void> _loadUserLocation() async {
    final pos = await const GeolocationService().getCurrentPosition();
    if (!mounted || pos == null) return;
    setState(() {
      _userLat = pos.latitude;
      _userLng = pos.longitude;
    });
  }

  // ── 추천 목록 조회 ─────────────────────────────────────
  // 에러 케이스:
  //   - 토큰 없음 → 로그아웃 상태 (일반적으로 도달 안 됨)
  //   - 네트워크 실패 → 빈 리스트 반환되면 "추천 없음" 상태 표시
  Future<void> _loadRecommendations() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = '로그인이 필요합니다.';
      });
      return;
    }

    final list = await _api.getRecommendations(
      accessToken: token,
      sessionId: widget.sessionId,
    );

    if (!mounted) return;
    setState(() {
      _recommendations = list;
      _isLoading = false;
    });
  }

  // 비교 모드 토글: 켜지면 선택 초기화
  void _toggleCompareMode() {
    setState(() {
      _isCompareMode = !_isCompareMode;
      _selectedForCompare.clear();
    });
  }

  // 카드 탭 처리 — 비교 모드면 선택 토글, 아니면 상세 화면 진입
  void _onCardTap(RecommendationDto rec) {
    if (_isCompareMode) {
      setState(() {
        if (_selectedForCompare.contains(rec.restaurantId)) {
          _selectedForCompare.remove(rec.restaurantId);
        } else {
          // 3개까지만 선택 허용
          if (_selectedForCompare.length >= 3) {
            // 상한 안내 — 행동 가이드(선택 해제) 자연 유도
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('비교는 최대 3개까지! 하나를 빼고 다시 골라봐요')),
            );
            return;
          }
          _selectedForCompare.add(rec.restaurantId);
        }
      });
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RestaurantDetailScreen(
            restaurantId: rec.restaurantId,
            initialName: rec.name,
          ),
        ),
      );
    }
  }

  // 비교 화면으로 이동
  void _openComparison() {
    final recs = _recommendations ?? const <RecommendationDto>[];
    final selected = recs
        .where((r) => _selectedForCompare.contains(r.restaurantId))
        .toList();

    if (selected.length < 2) {
      // 친근한 안내 — 부족한 개수 명확히
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비교는 2개 이상부터 가능해요. 하나만 더 골라봐요')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RestaurantComparisonScreen(
          recommendations: selected,
          sessionId: widget.sessionId,
          isHost: _isHost,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(
        showBack: true,
        title: 'AI 추천',
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
      // 비교 모드면 비교 CTA, 아니면 status 별 분기:
      //   WAITING / null → "투표 시작하기" (호스트만 의미 있음 — 백엔드가 권한 검증)
      //   VOTING         → "투표 현황 보기" (전원 → VoteProgressScreen 진입)
      //   ORDERED / DONE → "투표 결과 보기" (이미 결정 — 상태만 확인)
      //
      // 사장님 시연 피드백("투표가 어디서 진행되는지 모름") 의 마지막 진입점.
      // 자동 라우팅(로비 폴링 + decide 시점) 외에 사용자가 직접 들어올 수 있는
      // 명시적 통로를 본 화면 하단에 항상 유지한다.
      bottomNavigationBar: _isCompareMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: AppPrimaryButton(
                  label: '${_selectedForCompare.length}개 비교하기',
                  onPressed:
                      _selectedForCompare.length >= 2 ? _openComparison : null,
                ),
              ),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _buildPrimaryCta(),
              ),
            ),
    );
  }

  // ── 하단 메인 CTA — status 별 분기 ────────────────────
  // _sessionStatus 캐시(_loadSessionStatus 가 진입 시 1회 + _startVoting 성공 시
  // 갱신) 를 기준으로 라벨/동작을 바꿔준다. VOTING/ORDERED 진입 시
  // VoteProgressScreen 으로 push — 결과 화면이 별도로 분리되어
  // "투표 어디서 봄?" 의문이 한 번에 해소된다.
  Widget _buildPrimaryCta() {
    if (_sessionStatus == 'VOTING') {
      return AppPrimaryButton(
        label: '투표 현황 보기',
        onPressed: _openVoteProgress,
      );
    }
    if (_sessionStatus == 'ORDERED' || _sessionStatus == 'DONE') {
      return AppPrimaryButton(
        label: '투표 결과 보기',
        onPressed: _openVoteProgress,
      );
    }
    // 기본: WAITING / null — 호스트가 시작하는 흐름
    return AppPrimaryButton(
      label: _isStartingVote ? '투표 시작 중...' : '투표 시작하기',
      onPressed: _isStartingVote ? null : _startVoting,
    );
  }

  // ── VoteProgressScreen 으로 push ─────────────────────
  // recommendation_list_screen 에서 명시적으로 진입하는 보조 경로.
  // (자동 라우팅은 session_lobby_screen 폴링이 담당)
  void _openVoteProgress() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoteProgressScreen(
          sessionId: widget.sessionId,
          sessionName: widget.sessionName,
        ),
      ),
    );
  }

  // 투표 상태 전이 진행 중인지 — 중복 클릭 방지
  bool _isStartingVote = false;

  // ── 투표 시작 — PATCH /sessions/:id/status { status: 'VOTING' } ──
  // 백엔드가 호스트 권한을 검증. 호스트가 아니면 403/400 응답이 오므로 UI 에서
  // 별도 권한 가드는 두지 않음 (호스트 정보를 캐시하지 않는 정책).
  //
  // 2026-05-13 진단성 개선:
  //   기존엔 실패 시 무조건 "호스트만 시작할 수 있어요" 토스트를 띄워
  //   실제로 본인이 호스트인데도 다른 원인(JWT 만료/세션 상태 오류 등)으로
  //   실패한 경우 사용자가 잘못된 원인을 보고했음. 백엔드 401/403/404/400 을
  //   상세 응답으로 받아 케이스별 메시지를 표시.
  Future<void> _startVoting() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      // 로그인 만료 — 다음 액션(재로그인) 안내
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 풀렸어요. 다시 로그인해봐요')),
      );
      return;
    }

    setState(() => _isStartingVote = true);

    final result = await const SessionsApiService().updateSessionStatusDetailed(
      accessToken: token,
      sessionId: widget.sessionId,
      status: 'VOTING',
    );

    if (!mounted) return;
    setState(() => _isStartingVote = false);

    if (result.isSuccess) {
      // 2026-05-15 사장님 시연 피드백:
      //   "투표 시작하기 → 투표 현황 화면으로 자동 이동되어야 함"
      // 이전엔 본 화면에 머물러 status 만 갱신했지만, 사용자가
      // "어디서 투표하지?" 다시 헷갈리는 회귀가 있었음. 시작 성공 즉시
      // VoteProgressScreen 으로 push 해 다음 액션(투표) 흐름을 명확히 연결.
      setState(() {
        _sessionStatus = 'VOTING';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('투표가 시작됐어요! 곧 투표 화면으로 이동해요'),
          duration: const Duration(seconds: 2),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      // 짧은 토스트 후 자동 push — 토스트가 안 보이게 너무 빠르지 않게 600ms 대기
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _openVoteProgress();
      });
    } else {
      // 백엔드가 내려준 사유를 그대로 노출. 케이스별 메시지는 서비스 레이어에서 매핑.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // 백엔드가 내려준 사유 우선 사용, 없을 때 기본 친근 메시지
          content: Text(result.message ?? '투표 시작이 안 됐어요. 다시 시도해봐요'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildBody() {
    // 로딩 상태
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 에러 상태 (현재는 토큰 없음 케이스만)
    if (_errorMessage != null) {
      return Center(
        child: Text(_errorMessage!, style: AppTextStyles.bodyMedium),
      );
    }

    final recs = _recommendations ?? const <RecommendationDto>[];

    // 빈 결과 — 배민 패턴 빈 상태 강화 (2026-05-15)
    // 기존 결함: "찾지 못했어요" + "잠시 후 다시 시도" 만으로는 다음 액션이 약함.
    // 개선:
    //   1) 행동 가능한 다음 액션 2개를 박스 카드 안에 명시
    //      ① 다시 불러오기 (primary CTA — 즉시 해소 시도)
    //      ② 조건 다시 설정하기 (outlined — 멤버 조건이 너무 좁아 0건일 때)
    //   2) 카피를 "주변에 추천할 식당이 없어요" 로 사용자 시점에 맞춤
    //   3) 카드 형태로 감싸 빈 화면의 휑한 인상을 줄임.
    if (recs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
          vertical: AppSpacing.lg,
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.restaurant_outlined,
                  size: 48,
                  color: AppColors.iconInactive,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '주변에 추천할 식당이 없어요',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '조건을 조금 넓혀보거나 잠시 후 다시 시도해주세요',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                AppPrimaryButton(
                  label: '다시 불러오기',
                  onPressed: () {
                    setState(() => _isLoading = true);
                    _loadRecommendations();
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                // 사용자 입장에서 "조건 때문일까?" 의문에 대한 즉답 액션.
                // 세션 로비로 돌아가면 멤버 조건/세션 설정을 다시 손볼 수 있음.
                OutlinedButton.icon(
                  onPressed: () {
                    // 세션 로비로 복귀 (이전 화면) — 조건 재설정 진입점.
                    Navigator.of(context).maybePop();
                  },
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('조건 다시 설정하기'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 정상 리스트
    return Column(
      children: [
        // ── 상단 안내 배너 ───────────────────────────────
        // status 별 톤을 달리하여 "지금 무엇을 해야 하는지" 를 한눈에 알린다.
        // 시연 피드백("어디서 투표하나요?") 해결 핵심 영역.
        _buildHeaderBanner(),

        // ── WOW #3 점심 케미 카드 ───────────────────────
        // 로딩 중 → 스켈레톤 / 실패(null) → 위젯 자체 미노출 (장애 차단).
        // 화면 다른 영역에 영향을 주지 않도록 _buildChemistrySection 으로 캡슐화.
        _buildChemistrySection(),

        // ── 세션 이름 헤더 ───────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.sm,
            AppSpacing.screenHorizontal,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.sessionName,
                      style: AppTextStyles.heading3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '참여 멤버 조건 기반 추천 ${recs.length}개',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // 📊 투표 현황 보기 — VOTING/ORDERED 단계에서만 노출.
              // 사장님 시연 피드백("투표 어떻게 진행되는지 모름") 해결 핵심 진입점.
              // 2026-05-15 UX 미세 개선:
              //   기존: 5개 아이콘 헤더 직접 노출 (시각 복잡도 ↑, 자율 UX 감사 ★4)
              //   변경: 핵심 2개 (미니게임/지도) + 더보기 메뉴 (투표현황/비교/새로고침)
              //   배민 패턴 — 헤더는 핵심 1~2개만, 나머지는 more_vert
              // 🎯 미니게임 버튼 — 후보 식당으로 룰렛/사다리 결정 (시연 임팩트)
              IconButton(
                icon: const Icon(Icons.casino_rounded),
                tooltip: '재미있게 결정해봐요',
                onPressed: _openDecideGame,
              ),
              // 지도 보기 버튼 (CU-15 지도/리스트 토글)
              IconButton(
                icon: const Icon(Icons.map_outlined),
                tooltip: '지도 보기',
                onPressed: () {
                  final recs = _recommendations ?? const <RecommendationDto>[];
                  if (recs.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      // 친근한 안내 + 재시도 유도
                      const SnackBar(content: Text('아직 추천 식당이 없어요. 잠시 후 다시 시도해봐요')),
                    );
                    return;
                  }
                  // 2026-05-14 신규 지도 화면 연결 (lib/features/map/...) — 기존 화면
                  // (session 폴더)은 orphan 이 되었지만 다른 진입점에서 쓰일 가능성이 있어
                  // 파일은 그대로 두고 신규 화면만 진입에 사용한다.
                  // RecommendationDto → RestaurantMapPoint 변환:
                  //   - 좌표 없는 식당(크롤 실패 등)은 안전하게 필터링
                  //   - 좌표 있는 식당만 핀 + 미니카드로 표시
                  final points = recs
                      .where((r) => r.lat != null && r.lng != null)
                      .map(
                        (r) => RestaurantMapPoint(
                          restaurant: _recToRestaurant(r),
                          lat: r.lat!,
                          lng: r.lng!,
                        ),
                      )
                      .toList(growable: false);

                  if (points.isEmpty) {
                    // 모든 추천 식당에 좌표가 없는 케이스 — 친근 안내
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '식당 위치 정보가 아직 없어요. 잠시 후 다시 시도해봐요',
                        ),
                      ),
                    );
                    return;
                  }

                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RecommendationMapScreen(
                        points: points,
                        sessionTitle: widget.sessionName,
                      ),
                    ),
                  );
                },
              ),
              // ── 더보기 메뉴 (3개: 투표현황/비교/새로고침) ──────
              // 헤더가 너무 복잡해지지 않도록 보조 액션을 묶음.
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: '더보기',
                onSelected: (value) {
                  switch (value) {
                    case 'vote_progress':
                      _openVoteProgress();
                      break;
                    case 'compare':
                      _toggleCompareMode();
                      break;
                    case 'refresh':
                      setState(() => _isLoading = true);
                      _loadRecommendations();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (_sessionStatus == 'VOTING' || _sessionStatus == 'ORDERED')
                    PopupMenuItem(
                      value: 'vote_progress',
                      child: Row(
                        children: [
                          Icon(
                            Icons.how_to_vote_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text('투표 현황 보기'),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'compare',
                    child: Row(
                      children: [
                        Icon(
                          _isCompareMode
                              ? Icons.compare_arrows_rounded
                              : Icons.compare_rounded,
                          size: 18,
                          color: _isCompareMode
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(_isCompareMode ? '비교 모드 끄기' : '비교 모드'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'refresh',
                    child: Row(
                      children: [
                        Icon(Icons.refresh_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('새로고침'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── 추천 카드 목록 ───────────────────────────────
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              0,
              AppSpacing.screenHorizontal,
              AppSpacing.xl,
            ),
            physics: const BouncingScrollPhysics(),
            itemCount: recs.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) => _buildRecommendationCard(recs[i], i + 1),
          ),
        ),
      ],
    );
  }

  // ── WOW #3 점심 케미 섹션 ─────────────────────────────
  // 로딩 / 결과 / 실패 3가지를 한 곳에서 분기.
  //   - 로딩      : 스켈레톤 표시 (시연에서 빈 화면 인상 차단)
  //   - 결과 있음 : ChemistryCard 표시
  //   - 실패 / 데이터 없음 : SizedBox.shrink — 화면 영향 0 (장애 차단 정책)
  Widget _buildChemistrySection() {
    if (_chemistryLoading) {
      return const ChemistryCardSkeleton();
    }
    if (_chemistryFailed || _chemistry == null) {
      return const SizedBox.shrink();
    }
    return ChemistryCard(result: _chemistry!);
  }

  // ── 상단 안내 배너 ───────────────────────────────────
  // status 별 안내 카피:
  //   WAITING: "이 중에 마음에 드는 식당을 골라봐요" + 보조: 방장 시작 안내
  //   VOTING:  "투표 진행 중이에요! 마음에 드는 식당을 골라봐요"
  //   기타:    배너 미노출
  //
  // 디자인 토큰(색상)은 기존 추천 카드들과 동일한 primary.withAlpha(15)/(40)
  // 스타일을 그대로 재사용 — 색상 변경 금지 원칙 준수.
  // 친근 톤 "~봐요" 종결로 일관.
  Widget _buildHeaderBanner() {
    final primary = Theme.of(context).colorScheme.primary;
    final status = _sessionStatus;

    // 이미 결정·종료된 세션은 배너 자체를 숨김 (방해 요소 제거)
    if (status != null && status != 'WAITING' && status != 'VOTING') {
      return const SizedBox.shrink();
    }

    // status==VOTING 이면 강조 톤, WAITING/null 이면 안내 톤
    final isVoting = status == 'VOTING';
    final title = isVoting
        ? '투표 진행 중이에요! 마음에 드는 식당을 골라봐요'
        : '이 중에 마음에 드는 식당을 골라봐요';
    final subtitle = isVoting
        ? '카드를 눌러 식당 상세를 살펴봐요. 두 곳을 비교하고 싶다면 오른쪽 위 비교 모드를 켜봐요.'
        : '방장이 "투표 시작하기" 를 누르면 모두 함께 투표를 시작해요. 그 전에 후보를 살펴봐요.';
    final icon = isVoting
        ? Icons.how_to_vote_rounded
        : Icons.tips_and_updates_rounded;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.md,
        AppSpacing.screenHorizontal,
        0,
      ),
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

  // ── 추천 카드 하나 ────────────────────────────────────
  // 순위(1, 2, 3...) / 이름 / 카테고리 / 가격대 / 점수 / 근거 태그
  Widget _buildRecommendationCard(RecommendationDto rec, int rank) {
    final primary = Theme.of(context).colorScheme.primary;

    // 가격대 레이블은 공통 헬퍼로 통일.
    // price_range 값이 시드(원)·크롤(1000원 단위)·Gemini(1~5 척도)로 혼재돼
    // 단순 "${n}원대" 출력 시 "2원대"/"13원대" 같은 버그가 있었음.
    // formatRestaurantPriceRange가 값의 크기로 의미를 추정해 변환.
    final priceLabel = formatRestaurantPriceRange(rec.priceRange);

    // 거리 라벨 — 사용자 위치/식당 좌표 둘 다 있을 때만 표기.
    // null이면 거리 줄 자체를 그리지 않음(디자인 유지 원칙).
    final distance = distanceLabel(
      userLat: _userLat,
      userLng: _userLng,
      targetLat: rec.lat,
      targetLng: rec.lng,
    );

    // ── 거리 칩 정합화 (2026-05-13 사장님 피드백 → 2026-05-14 백엔드 정합) ──
    // [최초 도입] 백엔드 reasons 에는 "도보 1~2분 거리" 같은 비율 기반 칩이
    //   박혀 있어 실거리(예: 13km) 와 모순. walkChip 으로 실거리 라벨로 교체.
    // [2026-05-14] 백엔드도 distanceLabelFor(meters) 헬퍼로 실거리 라벨을 박도록
    //   정합화됨. 이 호출은 좌표 누락·구버전 응답 등 예외 상황의 "안전망"으로
    //   유지하며, 정상 흐름에서는 동일 칩 제거 후 재삽입(no-op)에 해당.
    final walkChip = walkChipForCoords(
      userLat: _userLat,
      userLng: _userLng,
      targetLat: rec.lat,
      targetLng: rec.lng,
    );
    final reconciledReasons = reconcileDistanceReasons(
      originalReasons: rec.reasons,
      distanceChip: walkChip,
    );

    // 비교 모드에서 선택된 카드는 테두리 강조
    final isSelected = _selectedForCompare.contains(rec.restaurantId);

    return AppCard(
      onTap: () => _onCardTap(rec),
      padding: const EdgeInsets.all(AppSpacing.md),
      // 비교 모드에서 선택되면 주황 테두리로 강조 (두께는 AppCard 기본)
      borderColor: isSelected ? primary : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 순위 배지 + 이름 + 점수 ───────────────────
          Row(
            children: [
              // 순위 원형 배지 (1~3등은 강조색, 그 이하는 회색)
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

              // 식당 이름
              Expanded(
                child: Text(
                  rec.name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // 점수 배지 (숫자만 작게)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: primary.withAlpha(25),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  '점수 ${rec.score}',
                  style: AppTextStyles.caption.copyWith(
                    color: primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // ── 카테고리 + 가격대 ─────────────────────────
          Row(
            children: [
              if (rec.category != null) ...[
                Icon(
                  Icons.restaurant_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(rec.category!, style: AppTextStyles.bodySmall),
                const SizedBox(width: AppSpacing.sm),
              ],
              Icon(
                Icons.payments_outlined,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(priceLabel, style: AppTextStyles.bodySmall),
            ],
          ),

          // ── 주소 ───────────────────────────────────────
          if (rec.address != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    rec.address!,
                    style: AppTextStyles.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // ── 거리(distance) ───────────────────────────
          // 위치 권한 + 식당 좌표가 모두 있을 때만 표기.
          // 디자인 토큰 변경 없이 directions_walk 아이콘 + bodySmall.
          if (distance != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.directions_walk_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(distance, style: AppTextStyles.bodySmall),
              ],
            ),
          ],

          // ── 추천 근거 태그들 ──────────────────────────
          // reconciledReasons 사용: 백엔드 reasons 의 거리 칩을 실거리 칩으로 교체한 결과
          if (reconciledReasons.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: reconciledReasons.map((reason) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundGrey,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    reason,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // 가격대 표기는 normalizer.dart 의 formatRestaurantPriceRange 로 통일.
  // 추천 카드에서 천단위 콤마 포맷은 더 이상 사용하지 않아 제거했음.

  // ══════════════════════════════════════════════════════════
  // 미니게임 결정 — 룰렛/사다리로 후보 중 하나 선택
  //
  // 사장님 피드백: "후보 중에서 재미있는 미니게임(사다리/뽑기/룰렛)으로
  //               결정할 수 있게 하고 싶다" → 캡스톤 시연 임팩트
  //
  // 흐름:
  //   1) 현재 추천 리스트(상위 6개) 를 Restaurant 모델로 변환
  //   2) DecideScreen 으로 push (sessionId + isHost 함께 전달)
  //   3) DecideScreen 내부에서 votes API(castVote/decide) 호출 + MenuScreen push
  //   4) 비호스트 케이스에는 winner 가 pop 으로 돌아옴 → 안내 토스트만
  // ══════════════════════════════════════════════════════════
  Future<void> _openDecideGame() async {
    final recs = _recommendations ?? const <RecommendationDto>[];
    if (recs.length < 2) {
      // 후보 부족 — 친근 안내
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('후보 식당이 2개 이상이어야 게임을 시작해요')),
      );
      return;
    }

    // DecideScreen 은 너무 많은 후보(7개 이상) 시 룰렛 글자가 겹쳐 자동 트림하지만,
    // 시연 시 알아보기 쉽게 상위 6개로 미리 잘라줌 (점수 순 그대로 유지)
    final candidates = recs
        .take(6)
        .map(_recToRestaurant)
        .toList(growable: false);

    // 호스트는 DecideScreen 내부에서 decide() 호출 후 MenuScreen 으로
    // pushReplacement 되므로 여기서는 winner 반환 처리에만 의존하면 된다.
    // (호스트는 pop 으로 돌아오지 않음 → winner 가 null 인 경우가 정상)
    final winner = await Navigator.of(context).push<Restaurant>(
      MaterialPageRoute(
        builder: (_) => DecideScreen(
          candidates: candidates,
          sessionId: widget.sessionId,
          isHost: _isHost,
        ),
      ),
    );

    if (!mounted || winner == null) return;
    // 비호스트 케이스 — castVote 만 등록한 상태로 돌아옴.
    // 안내 카피는 DecideScreen 내부 토스트가 이미 띄웠지만 추가 액션 유도용.
    if (!_isHost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${winner.name}" 에 한 표! 호스트 종료를 기다려봐요'),
          duration: const Duration(seconds: 3),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  // ── RecommendationDto → Restaurant 변환 ────────────────
  //
  // DecideScreen 은 공용 Restaurant 모델을 받음. RecommendationDto 에서
  // 필요한 필드만 minimal 변환. 룰렛/사다리는 name 만 표시하므로
  // description/tags 등 부수 필드는 빈 값으로 OK.
  Restaurant _recToRestaurant(RecommendationDto rec) {
    return Restaurant(
      id: rec.restaurantId,
      name: rec.name,
      category: _categoryFromKorean(rec.category),
      description: rec.reasons.join(', '),
      tags: const [],
      address: rec.address,
      priceRange: formatRestaurantPriceRange(rec.priceRange),
    );
  }

  // ── 한글 카테고리 → RestaurantCategory enum 매핑 ───────
  // 시드/크롤 카테고리 문자열을 모델 enum 으로 변환. 매칭 실패 시 etc.
  RestaurantCategory _categoryFromKorean(String? korean) {
    if (korean == null) return RestaurantCategory.etc;
    if (korean.contains('한식')) return RestaurantCategory.korean;
    if (korean.contains('중식') || korean.contains('중국')) {
      return RestaurantCategory.chinese;
    }
    if (korean.contains('일식') || korean.contains('일본')) {
      return RestaurantCategory.japanese;
    }
    if (korean.contains('양식') ||
        korean.contains('이탈리') ||
        korean.contains('파스타')) {
      return RestaurantCategory.western;
    }
    if (korean.contains('분식')) return RestaurantCategory.snack;
    if (korean.contains('카페') || korean.contains('디저트')) {
      return RestaurantCategory.cafe;
    }
    return RestaurantCategory.etc;
  }
}
