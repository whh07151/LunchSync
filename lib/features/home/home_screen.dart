import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../session/member_select_screen.dart';
import '../session/session_create_screen.dart';
import '../session/join_session_screen.dart';
import '../session/session_lobby_screen.dart';
import '../restaurant/restaurant_detail_screen.dart';
import '../orders/order_list_screen.dart';
import '../notifications/notification_screen.dart';
import '../my_info/my_info_screen.dart';
import '../auth/login_screen.dart';
import '../../core/debug/debug_toast.dart';
import '../../providers/user_provider.dart';
import '../../services/users_api_service.dart';
import '../../services/sessions_api_service.dart';
import '../../services/restaurants_api_service.dart';
import '../../models/session.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-06 홈 대시보드 화면
//
// 구성 (와이어프레임 기준):
//   - 상단 앱바: 앱 로고 + 알림 아이콘
//   - 인사말 헤더: 사용자 이름 + 소속
//   - 빠른 실행 CTA 4개: 점심 만들기 / 코드로 참가 / 최근 이력 / 알림
//   - 오늘의 세션 섹션: 오늘 참여 중인 세션 카드
//   - AI 추천 식당 섹션: 식당 카드 가로 스크롤 (지도 없음)
//   - 하단 탭바 5개: 홈 / 점심세션 / 주문현황 / 내역 / 내정보
//
// 📌 지도는 홈에 없음. CU-15(지도/리스트 토글) 화면에서만 표시 (와이어프레임 기준).
//
// 연동:
//   - GET /api/users/me               → userProvider
//   - GET /api/sessions/today         → _todaySessions
//   - GET /api/restaurants?limit=10   → _recommendedRestaurants
// ══════════════════════════════════════════════════════════

// ConsumerStatefulWidget: Riverpod의 userProvider를 읽기 위해 사용
// StatefulWidget 대신 이걸 쓰면 ref.watch/read로 전역 상태에 접근 가능
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // ── 하단 탭바 상태 ─────────────────────────────────────
  // 현재 선택된 탭의 인덱스 (0: 홈, 1: 점심세션, 2: 주문현황, 3: 내역, 4: 내정보)
  // 기본값: 0 (홈 탭)
  int _currentTabIndex = 0;

  // ── 홈 데이터 상태 (백엔드 API 응답 저장소) ───────────────
  // 로딩 중에는 null, 조회 완료 후 실제 값으로 채움
  // Session 리스트 첫 번째 항목을 "오늘의 세션"으로 사용
  List<Session>? _todaySessions;
  List<RestaurantDto>? _recommendedRestaurants;

  // 각 섹션 로딩 상태 — UI에서 스켈레톤/스피너 표시용
  bool _isSessionsLoading = true;
  bool _isRestaurantsLoading = true;

  // ── 생명주기: 화면이 처음 만들어질 때 ──────────────────
  @override
  void initState() {
    super.initState();
    DebugToast.show(context, 'CU-06');

    // 화면 진입 시 DB에서 최신 프로필 조회 후 userProvider 갱신.
    // addPostFrameCallback: initState 안에서 ref.read가 안전하게 실행되도록
    // 첫 프레임 렌더링 완료 후 실행.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserProfile();
      _loadTodaySessions();
      _loadRecommendedRestaurants();
    });
  }

  // ── 멤버 선택 화면(CU-08)으로 이동 ──────────────────────
  // "점심 만들기"와 "친구 초대" CTA 둘 다 이 메서드를 통해 진입.
  // CU-09(세션 생성, 우현호) 완성 후 onNext 콜백에서 CU-09로 이동하도록 교체.
  void _goToMemberSelect() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemberSelectScreen(
          onNext: (selectedMembers) {
            // CU-08 완료 → CU-09 세션 조건 설정 화면으로 이동
            // selectedMembers는 이미 sessionProvider에 저장된 상태이므로
            // SessionCreateScreen에서 ref.watch(sessionProvider).selectedMembers 로 읽음
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SessionCreateScreen(),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── DB에서 프로필 조회 후 userProvider 갱신 ──────────────
  // GET /api/users/me 호출 → 이름/소속 최신값을 userProvider에 반영
  Future<void> _loadUserProfile() async {
    // accessToken이 없으면 조회 불가 (로그아웃 상태)
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    final profile = await const UsersApiService().getMe(token);
    if (profile != null && mounted) {
      // mounted: 비동기 완료 전에 화면이 사라졌을 경우 setState 방지
      ref.read(userProvider.notifier).setFromProfile(profile);
    }
  }

  // ── 오늘의 세션 조회 ────────────────────────────────────
  // GET /api/sessions/today — 오늘 날짜에 내가 참여하거나 만든 세션 목록
  // 첫 번째 항목을 홈 화면 "오늘의 세션" 카드로 노출.
  // 세션이 없으면 null로 두고 "시작하기" 유도 상태를 표시.
  Future<void> _loadTodaySessions() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      if (mounted) setState(() => _isSessionsLoading = false);
      return;
    }

    final sessions = await const SessionsApiService()
        .getTodaySessions(accessToken: token);

    if (!mounted) return;
    setState(() {
      _todaySessions = sessions;
      _isSessionsLoading = false;
    });
  }

  // ── AI 추천 식당 조회 ────────────────────────────────────
  // GET /api/restaurants?limit=10 — 기본 식당 목록(추후 추천 엔진 결과로 교체)
  // CORE-07 추천 점수화 엔진 완성 전까지는 단순 최신순 목록을 사용.
  Future<void> _loadRecommendedRestaurants() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      if (mounted) setState(() => _isRestaurantsLoading = false);
      return;
    }

    final list = await const RestaurantsApiService()
        .getRestaurants(accessToken: token, limit: 10);

    if (!mounted) return;
    setState(() {
      _recommendedRestaurants = list;
      _isRestaurantsLoading = false;
    });
  }

  // ── UI 구성 ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,

      // ── 상단 앱바 ──────────────────────────────────────
      appBar: _buildAppBar(),

      // ── 본문: 현재 선택된 탭에 따라 다른 화면 표시 ────
      body: _buildBody(),

      // ── 하단 탭바 ──────────────────────────────────────
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── 상단 앱바 위젯 ──────────────────────────────────────
  // 왼쪽: 앱 이름/로고, 오른쪽: 알림 아이콘 버튼
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      // automaticallyImplyLeading: 뒤로가기 버튼 자동 추가 방지
      // (홈 화면은 뒤로가기가 없으므로 false)
      automaticallyImplyLeading: false,

      // ── 왼쪽: 앱 이름 ────────────────────────────────
      title: Text(
        'LunchSync',
        style: AppTextStyles.heading3.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),

      // ── 오른쪽: 알림 아이콘 버튼 ─────────────────────
      actions: [
        IconButton(
          // CU-22 알림함 화면으로 이동 (push: 뒤로가기로 홈 복귀)
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NotificationScreen(),
              ),
            );
          },
          icon: Stack(
            // Stack: 알림 배지(빨간 점)를 아이콘 위에 겹쳐서 표시하기 위해 사용
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.notifications_outlined,
                color: AppColors.textPrimary,
              ),
              // ── 알림 배지 (읽지 않은 알림이 있을 때 표시) ──
              // TODO: API 연동 시 — 실제 미읽음 알림 수에 따라 표시/숨김 처리
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.error, // 빨간 점 = 읽지 않은 알림 있음
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 오른쪽 끝 여백
        const SizedBox(width: 4),
      ],
    );
  }

  // ── 본문 위젯: 탭 인덱스에 따라 화면 전환 ────────────────
  Widget _buildBody() {
    // IndexedStack: 모든 탭 화면을 메모리에 유지하면서 선택된 것만 표시
    // (탭 전환 시 화면이 재생성되지 않아 스크롤 위치 등이 유지됨)
    return IndexedStack(
      index: _currentTabIndex,
      children: [
        // 0번 탭: 홈
        _buildHomeTab(),

        // 1번 탭: 점심세션 — TODO: CU-09 세션 생성/CU-10 세션 로비 완성 후 교체
        _buildPlaceholderTab('점심세션', Icons.restaurant_menu_rounded),

        // 2번 탭: 주문현황 — OrderListScreen (오늘 내 주문 목록)
        const OrderListScreen(),

        // 3번 탭: 내역 — TODO: 주문 이력 화면 완성 후 교체
        _buildPlaceholderTab('내역', Icons.history_rounded),

        // 4번 탭: 내정보 — CU-23 내정보/설정
        MyInfoScreen(
          // 로그아웃 처리:
          //   1. userProvider 초기화 (JWT + 유저 정보 삭제)
          //   2. 내비게이션 스택 전체 제거 후 LoginScreen으로 이동
          //      (온보딩은 완료 상태이므로 SplashScreen 건너뜀)
          onLogout: () {
            ref.read(userProvider.notifier).clear();
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (ctx) => LoginScreen(
                  onLoginSuccess: ({required String nextStep}) {
                    // 로그아웃 후 재로그인: nextStep에 따라 화면 분기
                    // 온보딩 완료 기기이므로 대부분 HOME이지만,
                    // 다른 카카오 계정으로 로그인 시 PROFILE_SETUP이 올 수 있음
                    if (nextStep == 'HOME') {
                      Navigator.of(ctx).pushReplacement(
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                      );
                    } else {
                      // 온보딩 필요한 계정 → main.dart의 라우팅 로직과 동일하게 처리
                      Navigator.of(ctx).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                        (route) => false,
                      );
                    }
                  },
                ),
              ),
              (route) => false, // 이전 스택 전체 제거
            );
          },
        ),
      ],
    );
  }

  // ── 홈 탭 콘텐츠 위젯 ──────────────────────────────────
  // 스크롤 가능한 홈 화면의 실제 내용
  Widget _buildHomeTab() {
    return SingleChildScrollView(
      // physics: 스크롤 동작 방식. BouncingScrollPhysics = iOS처럼 끝에서 튕기는 효과
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── 인사말 헤더 섹션 ────────────────────────────
          _buildGreetingHeader(),

          // TODO: 수치 확정 시 수정 — 섹션 사이 간격 (현재 16px)
          const SizedBox(height: AppSpacing.md),

          // ── 빠른 실행 CTA 4개 ───────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
            ),
            child: _buildQuickActions(),
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── 오늘의 세션 섹션 ────────────────────────────
          _buildSectionTitle('오늘의 세션'),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
            ),
            child: _buildTodaySession(),
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── AI 추천 식당 섹션 ────────────────────────────
          _buildSectionTitle('AI 추천 식당'),
          const SizedBox(height: AppSpacing.sm),

          // 가로 스크롤 식당 카드 목록
          // (와이어프레임: 홈에는 지도 X. 지도는 CU-15 "지도/리스트 토글"에서만)
          _buildRestaurantList(),

          // 하단 여백 (하단 탭바와 겹치지 않도록)
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  // ── 인사말 헤더 위젯 ────────────────────────────────────
  // 주황 그라디언트 배경 + 사용자 이름 + 소속
  // DB에서 조회한 실제 이름/소속을 userProvider를 통해 표시
  Widget _buildGreetingHeader() {
    final primary = Theme.of(context).colorScheme.primary;

    // userProvider에서 실제 이름/소속 읽기
    // _loadUserProfile()이 완료되면 자동으로 리빌드됨
    final user = ref.watch(userProvider);
    final userName = user.name ?? '...';       // 로딩 중이면 '...' 표시
    final userOrg = user.org ?? '';            // 소속 미설정 시 빈 문자열

    return Container(
      width: double.infinity,
      // TODO: 수치 확정 시 수정 — 헤더 내부 여백
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.md,
        AppSpacing.screenHorizontal,
        AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        // 그라디언트 배경: 주황 → 연한 주황으로 자연스럽게 변함
        // TODO: 수치 확정 시 수정 — 그라디언트 색상 범위
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary,
            primary.withAlpha(180), // 오른쪽 아래로 갈수록 연해짐
          ],
        ),
        // 헤더 하단 모서리만 둥글게 처리 (카드처럼 보이도록)
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppRadius.bottomSheet),
          bottomRight: Radius.circular(AppRadius.bottomSheet),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // 인사말 문구: DB에서 조회한 실제 이름 표시
          Text(
            '안녕하세요, $userName님! 👋',
            style: AppTextStyles.heading2.copyWith(
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 4),

          // 소속 + 문구
          // userOrg가 비어 있으면 소속 부분 없이 문구만 표시
          Text(
            userOrg.isNotEmpty ? '$userOrg · 오늘 점심은 어디로?' : '오늘 점심은 어디로?',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.white.withAlpha(200),
            ),
          ),
        ],
      ),
    );
  }

  // ── 빠른 실행 CTA 4개 위젯 ────────────────────────────────
  // 2x2 그리드 형태로 주요 기능에 빠르게 접근할 수 있는 버튼들
  Widget _buildQuickActions() {
    // CTA 버튼 데이터를 리스트로 관리
    // 새로운 버튼 추가 시 이 리스트에만 추가하면 됨
    final actions = [
      _QuickAction(
        icon: Icons.add_circle_rounded,
        label: '점심 만들기',
        // CU-08 멤버 선택 화면 진입 (세션 생성의 첫 단계)
        // CU-09(세션 생성, 우현호) 완성 후 onNext에서 CU-09로 이동하도록 교체
        onTap: () => _goToMemberSelect(),
      ),
      _QuickAction(
        icon: Icons.person_add_rounded,
        label: '코드로 참가',
        // 초대 코드를 입력해 다른 사람의 세션에 참가하는 화면으로 이동
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const JoinSessionScreen()),
          );
        },
      ),
      _QuickAction(
        icon: Icons.history_rounded,
        label: '최근 이력',
        // 하단 탭 3번 (내역)으로 전환
        onTap: () => setState(() => _currentTabIndex = 3),
      ),
      _QuickAction(
        icon: Icons.notifications_rounded,
        label: '알림',
        // CU-22 알림함 화면으로 이동 (push: 뒤로가기로 홈 복귀)
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const NotificationScreen(),
            ),
          );
        },
      ),
    ];

    return GridView.count(
      // GridView.count: 열 개수를 고정한 그리드 레이아웃
      crossAxisCount: 4,      // 가로 4칸 (버튼 4개가 한 줄에 나란히)
      shrinkWrap: true,       // 그리드가 내용물 크기만큼만 차지 (스크롤 안에 있으므로 필수)
      physics: const NeverScrollableScrollPhysics(), // 그리드 자체는 스크롤 불가 (부모 스크롤 사용)
      // TODO: 수치 확정 시 수정 — 버튼 가로세로 비율 (현재 정사각형에 가까운 0.9)
      childAspectRatio: 0.9,
      children: actions.map(_buildQuickActionItem).toList(),
    );
  }

  // 빠른 실행 버튼 항목 하나 (아이콘 원 + 텍스트 레이블)
  Widget _buildQuickActionItem(_QuickAction action) {
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: action.onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── 아이콘 원형 배경 ─────────────────────────
          Container(
            // TODO: 수치 확정 시 수정 — 아이콘 원 크기 (현재 52px)
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              // 연한 주황 배경 (primarySurface)
              color: primary.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(
              action.icon,
              color: primary,
              // TODO: 수치 확정 시 수정 — 아이콘 크기 (현재 26px)
              size: 26,
            ),
          ),

          const SizedBox(height: 6),

          // ── 버튼 레이블 ──────────────────────────────
          Text(
            action.label,
            style: AppTextStyles.label.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── 섹션 제목 위젯 (공통) ────────────────────────────────
  // "오늘의 세션", "AI 추천 식당" 등의 섹션 헤더
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
      ),
      child: Text(
        title,
        style: AppTextStyles.heading3,
      ),
    );
  }

  // ── 오늘의 세션 카드 위젯 ──────────────────────────────────
  // 상태별 표시:
  //   ① 로딩 중        → 스피너 카드
  //   ② 세션 없음      → "점심 만들기" CTA 유도 카드
  //   ③ 세션 존재      → 첫 번째 세션 정보 카드 + 입장 버튼
  Widget _buildTodaySession() {
    // ① 로딩 상태
    if (_isSessionsLoading) {
      return const AppHighlightCard(
        child: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final sessions = _todaySessions ?? const <Session>[];

    // ② 오늘 세션 없음 → 만들기 유도 카드
    if (sessions.isEmpty) {
      return AppHighlightCard(
        onTap: _goToMemberSelect,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '오늘 예정된 세션이 없어요',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '점심 세션을 만들어 친구를 초대해보세요',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            AppPrimaryButton(
              label: '점심 만들기',
              height: 44,
              onPressed: _goToMemberSelect,
            ),
          ],
        ),
      );
    }

    // ③ 실제 세션 렌더링 — 첫 번째 세션을 메인으로 노출
    final session = sessions.first;
    // statusLabel이 있으면 한글 레이블 우선, 없으면 내부 enum 문자열
    final statusText = session.statusLabel ?? session.status;
    // scheduledAt은 ISO 8601 문자열 → 시:분만 추출. null이면 '시간 미정'
    final scheduledText = _formatScheduledTime(session.scheduledAt);
    // memberCount는 목록 응답에서만 제공. 없으면 "- 명"
    final memberText = session.memberCount != null
        ? '${session.memberCount}명 참여'
        : '참여 인원 확인 중';

    return AppHighlightCard(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SessionLobbyScreen(sessionId: session.id),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── 세션 상태 배지 + 세션 이름 ─────────────────
          Row(
            children: [
              // 상태 배지 (주황 pill 형태)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  statusText,
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(width: AppSpacing.sm),

              // 세션 이름
              Expanded(
                child: Text(
                  session.name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // ── 세션 상세 정보 ───────────────────────────
          Row(
            children: [
              _buildSessionInfoItem(Icons.people_rounded, memberText),
              const SizedBox(width: AppSpacing.md),
              _buildSessionInfoItem(Icons.access_time_rounded, scheduledText),
            ],
          ),

          const SizedBox(height: AppSpacing.sm + 4),

          // ── "세션 입장하기" 버튼 ─────────────────────
          AppPrimaryButton(
            label: '세션 입장하기',
            height: 44,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SessionLobbyScreen(sessionId: session.id),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── scheduledAt ISO 문자열 → "오후 12:00" 형태 포맷 ───────
  // 백엔드가 null을 줄 수도 있어서 안전하게 처리.
  String _formatScheduledTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '시간 미정';
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return '시간 미정';
    final local = dt.toLocal();
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    // 12시간제 + 오전/오후 표기 (한국식)
    final isAfternoon = hour >= 12;
    final display12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '${isAfternoon ? "오후" : "오전"} $display12:$minute';
  }

  // 세션 정보 항목 하나 (아이콘 + 텍스트 조합)
  Widget _buildSessionInfoItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min, // Row가 내용물 크기만큼만 차지
      children: [
        Icon(
          icon,
          size: 14,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTextStyles.bodySmall,
        ),
      ],
    );
  }

  // ── AI 추천 식당 가로 스크롤 목록 위젯 ──────────────────────
  // 식당 카드를 가로로 스크롤하며 볼 수 있는 리스트
  // 상태별 표시: 로딩 / 빈 상태 / 리스트
  Widget _buildRestaurantList() {
    // 로딩 중
    if (_isRestaurantsLoading) {
      return const SizedBox(
        height: 176,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final restaurants = _recommendedRestaurants ?? const <RestaurantDto>[];

    // 추천 결과 없음
    if (restaurants.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
        ),
        child: Container(
          height: 120,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            '추천할 식당이 없어요',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      // TODO: 수치 확정 시 수정 — 식당 카드 영역 높이 (현재 176px)
      height: 176,
      child: ListView.separated(
        // scrollDirection.horizontal: 가로 방향으로 스크롤
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
        ),
        itemCount: restaurants.length,
        separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.sm + 4),
        itemBuilder: (context, index) {
          return _buildRestaurantCard(restaurants[index]);
        },
      ),
    );
  }

  // 식당 카드 위젯 하나 (이름 / 카테고리 / 가격)
  // RestaurantDto는 priceRange(int) / address / lat / lng만 제공.
  // rating, 거리, 리뷰 수는 백엔드에 아직 없어서 카드 레이아웃 간소화.
  Widget _buildRestaurantCard(RestaurantDto restaurant) {
    final primary = Theme.of(context).colorScheme.primary;

    // 가격 레이블: 정수면 "X,XXX원~", null이면 "가격 미정"
    final priceLabel = restaurant.priceRange != null
        ? '${_formatWithComma(restaurant.priceRange!)}원~'
        : '가격 미정';

    return AppCard(
      // 식당 카드 탭 → CU-13 식당 상세 화면으로 이동
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RestaurantDetailScreen(
              restaurantId: restaurant.id,
              initialName: restaurant.name,
            ),
          ),
        );
      },
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── 식당 이미지 영역 (placeholder) ─────────────
            Container(
              height: 72,
              decoration: BoxDecoration(
                color: primary.withAlpha(15),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Center(
                child: Icon(
                  Icons.restaurant_rounded,
                  color: primary.withAlpha(100),
                  size: 32,
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            // ── 식당 이름 ────────────────────────────────
            Text(
              restaurant.name,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 2),

            // ── 카테고리 ─────────────────────────────────
            Text(
              restaurant.category ?? '카테고리 미정',
              style: AppTextStyles.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),

            const Spacer(),

            // ── 가격대 ───────────────────────────────────
            Text(
              priceLabel,
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 정수 → "12,345" 형태 천단위 콤마 포맷 ──────────────
  String _formatWithComma(int value) {
    final s = value.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      // 오른쪽 끝에서 3자리마다 쉼표 삽입
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  // ── 하단 탭바 위젯 ──────────────────────────────────────────
  // 손님앱 주요 5개 섹션 탭 (홈 / 점심세션 / 주문현황 / 내역 / 내정보)
  Widget _buildBottomNav() {
    // 탭 항목 데이터 목록
    // 순서 = 탭 인덱스 (0~4). _currentTabIndex와 순서가 반드시 일치해야 함
    final tabs = [
      _NavTab(icon: Icons.home_rounded,             label: '홈'),
      _NavTab(icon: Icons.restaurant_menu_rounded,  label: '점심세션'),
      _NavTab(icon: Icons.receipt_long_rounded,     label: '주문현황'),
      _NavTab(icon: Icons.history_rounded,          label: '내역'),
      _NavTab(icon: Icons.person_rounded,           label: '내정보'),
    ];

    return BottomNavigationBar(
      currentIndex: _currentTabIndex,
      // onTap: 탭을 누르면 해당 인덱스로 상태 업데이트 → IndexedStack이 화면 전환
      onTap: (index) => setState(() => _currentTabIndex = index),

      // type.fixed: 탭이 5개이므로 fixed 타입 사용 (shifting 타입은 선택 시 레이블 표시)
      type: BottomNavigationBarType.fixed,

      // 선택/비선택 색상: 테마의 primary 색과 비활성 색으로 자동 구분
      selectedItemColor: Theme.of(context).colorScheme.primary,
      unselectedItemColor: AppColors.iconInactive,

      // 선택된 탭의 레이블 크기: 강조하지 않고 동일하게 유지
      selectedFontSize: 11,
      unselectedFontSize: 11,

      // 배경색 + 상단 구분선
      backgroundColor: AppColors.surface,

      items: tabs.map((tab) {
        return BottomNavigationBarItem(
          icon: Icon(tab.icon),
          label: tab.label,
        );
      }).toList(),
    );
  }

  // ── 탭 준비 중 화면 위젯 (다른 탭 화면이 완성되기 전 임시) ──
  // 해당 탭의 화면이 완성되면 IndexedStack의 children에서 교체
  Widget _buildPlaceholderTab(String label, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.iconInactive),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$label 화면 준비 중',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════
// 내부 데이터 모델 클래스들 (이 파일 안에서만 사용하는 Mock 구조체)
//
// 왜 별도 파일이 아닌 여기에 정의하나?
//   이 클래스들은 오직 이 화면의 Mock 데이터 표현 용도로만 쓰임.
//   API 연동 후에는 서버 응답 DTO(Data Transfer Object)로 교체되므로
//   별도 파일을 만들어 관리할 필요가 없음.
// ══════════════════════════════════════════════════════════

// 빠른 실행 CTA 버튼 하나의 데이터
class _QuickAction {
  const _QuickAction({
    required this.icon,   // 버튼 아이콘
    required this.label,  // 버튼 레이블 텍스트
    required this.onTap,  // 탭 시 실행할 함수
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

// 하단 탭바 항목 하나의 데이터
class _NavTab {
  const _NavTab({
    required this.icon,  // 탭 아이콘
    required this.label, // 탭 레이블
  });
  final IconData icon;
  final String label;
}

