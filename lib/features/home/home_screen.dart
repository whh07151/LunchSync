import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../session/member_select_screen.dart';
import '../menu/menu_screen.dart';
import '../../core/debug/debug_toast.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-06 홈 대시보드 화면
//
// [연결 예정 데이터]
//   - lib/data/seeds/restaurant_seeds.dart → _mockRestaurants 교체
//   - lib/core/constants/ui_texts.dart (RecommendTexts) → 추천 근거 문구
//   - lib/core/constants/ui_texts.dart (DetailTexts) → 식당 정보 레이블
//   - lib/core/utils/normalizer.dart → 카테고리/가격대 정규화
//   - lib/models/restaurant.dart → _MockRestaurant 클래스 교체
//   - lib/models/tag.dart → 태그 기반 필터/추천 표시
//
// 와이어프레임 기준 구성 요소:
//   - 상단 앱바: 앱 로고(왼쪽) + 알림 아이콘(오른쪽)
//   - 인사말 헤더: 사용자 이름 + 오늘 날짜
//   - 빠른 실행 CTA 4개:
//       점심 만들기 / 친구 초대 / 최근 이력 / 알림
//   - 오늘의 세션 섹션: 현재 진행 중인 점심 세션 카드
//   - AI 추천 식당 섹션: 조건 기반 추천 식당 카드 3개
//   - 하단 탭바 5개: 홈 / 점심세션 / 주문현황 / 내역 / 내정보
//
// Mock 데이터 사용 이유:
//   홈 화면의 실시간 데이터(세션 현황, 추천 식당 등)는
//   안태환이 담당하는 NestJS 백엔드 API에서 받아와야 합니다.
//   API가 완성되기 전까지 코드 안에 직접 적힌 가짜 데이터(Mock)를
//   사용해 UI를 먼저 완성합니다.
//   → API 연동 시: _mock으로 시작하는 변수들을 API 호출로 교체
//
// 동작 흐름:
//   이전 화면(기본 조건 설정, CU-05) → 이 화면 (온보딩 완료)
//   → 하단 탭으로 다른 섹션 이동 가능
//   → CTA 버튼으로 주요 플로우 바로 진입 가능
//
// 상태 관리 라이브러리 무관:
//   현재는 StatefulWidget으로 탭 인덱스만 관리.
//   추후 전역 상태 관리 도입 시 탭 상태를 Provider/Riverpod 등으로 이전 가능.
// ══════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ── 하단 탭바 상태 ─────────────────────────────────────
  // 현재 선택된 탭의 인덱스 (0: 홈, 1: 점심세션, 2: 주문현황, 3: 내역, 4: 내정보)
  // 기본값: 0 (홈 탭)
  int _currentTabIndex = 0;

  // ── 생명주기: 화면이 처음 만들어질 때 ──────────────────
  @override
  void initState() {
    super.initState();
    DebugToast.show(context, 'CU-06');
  }

  // ── Mock 데이터: 사용자 정보 ────────────────────────────
  // TODO: API 연동 시 — 로그인/프로필 정보에서 실제 이름/소속으로 교체
  static const String _mockUserName = '지효';
  static const String _mockUserOrg = '개발팀';

  // ── Mock 데이터: 오늘의 세션 ────────────────────────────
  // TODO: API 연동 시 (안태환) — GET /sessions/today 응답으로 교체
  // null이면 "오늘 세션 없음" 상태를 표시함
  static const _mockSession = _MockSession(
    id: 'session_001',
    name: '개발팀 점심',
    status: '멤버 모집 중',       // 세션 상태: 모집 중 / 투표 중 / 주문 완료 등
    memberCount: 3,              // 현재 참여 인원
    maxMemberCount: 8,           // 최대 인원
    scheduledTime: '오후 12:00', // 예정 시간
  );

  // ── Mock 데이터: AI 추천 식당 목록 ──────────────────────
  // TODO: API 연동 시 (안태환) — GET /restaurants/recommend 응답으로 교체
  // 사용자의 기본 조건(반경/예산/속도)을 기반으로 필터링된 결과를 받게 됨
  // ── [SEED 연결 포인트] ──────────────────────────────────
  // → restaurant_seeds.dart의 restaurantSeeds로 교체
  // → Restaurant 모델 + Tag 모델로 전환
  // → RecommendTexts에서 추천 근거 문구 가져오기
  // → normalizeCategory()로 카테고리 표시 통일
  static const List<_MockRestaurant> _mockRestaurants = [
    _MockRestaurant(
      name: '한솥도시락',
      category: '한식 · 도시락',
      distance: '도보 3분',
      priceRange: '6,500원~',
      rating: 4.2,
      reviewCount: 128,
      isOpen: true,
    ),
    _MockRestaurant(
      name: '김밥천국',
      category: '분식',
      distance: '도보 5분',
      priceRange: '4,000원~',
      rating: 4.0,
      reviewCount: 256,
      isOpen: true,
    ),
    _MockRestaurant(
      name: '맘스터치',
      category: '패스트푸드',
      distance: '도보 7분',
      priceRange: '7,500원~',
      rating: 4.5,
      reviewCount: 89,
      isOpen: true,
    ),
  ];

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
          // TODO: CU-22 알림함 화면 완성 후 연결
          // 현재는 탭해도 아무 동작 없음 (데모용)
          onPressed: () {},
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

        // 2번 탭: 주문현황 — TODO: CU-20 주문/예약 추적 완성 후 교체
        _buildPlaceholderTab('주문현황', Icons.receipt_long_rounded),

        // 3번 탭: 내역 — TODO: 주문 이력 화면 완성 후 교체
        _buildPlaceholderTab('내역', Icons.history_rounded),

        // 4번 탭: 내정보 — TODO: CU-23 내정보/설정 완성 후 교체
        _buildPlaceholderTab('내정보', Icons.person_rounded),
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
          // 가로 스크롤 식당 카드 목록 (화면 너비를 넘어도 가로로 스크롤)
          _buildRestaurantList(),

          // 하단 여백 (하단 탭바와 겹치지 않도록)
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  // ── 인사말 헤더 위젯 ────────────────────────────────────
  // 주황 그라디언트 배경 + 사용자 이름 + 오늘 날짜
  Widget _buildGreetingHeader() {
    final primary = Theme.of(context).colorScheme.primary;

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

          // 인사말 문구
          // TODO: 수정 필요 — 실제 사용자 이름을 상태에서 가져오도록 교체
          Text(
            '안녕하세요, $_mockUserName님! 👋',
            style: AppTextStyles.heading2.copyWith(
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 4),

          // 소속 + 날짜 정보
          Text(
            // TODO: API 연동 시 — 실제 날짜 계산으로 교체 (DateTime.now())
            '$_mockUserOrg · 오늘 점심은 어디로?',
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
        // TODO: CU-09 세션 생성 화면 완성 후 실제 네비게이션으로 교체
        onTap: () {},
      ),
      _QuickAction(
        icon: Icons.person_add_rounded,
        label: '친구 초대',
        // CU-08 멤버 선택 화면으로 이동
        // push: 뒤로가기로 홈으로 돌아올 수 있도록 pushReplacement가 아닌 push 사용
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MemberSelectScreen(
                onNext: (selectedMembers) {
                  // TODO: CU-09 세션 조건 설정 화면 완성 후 (우현호 담당)
                  //       selectedMembers를 넘겨주며 CU-09로 이동하도록 교체
                  // 현재는 선택 완료 후 홈으로 돌아옴 (임시 동작)
                  Navigator.of(context).pop();
                },
              ),
            ),
          );
        },
      ),
      _QuickAction(
        icon: Icons.history_rounded,
        label: '최근 이력',
        // TODO: 내역 탭으로 이동
        onTap: () => setState(() => _currentTabIndex = 3),
      ),
      _QuickAction(
        icon: Icons.notifications_rounded,
        label: '알림',
        // TODO: CU-22 알림함 화면 완성 후 연결
        onTap: () {},
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
  // 진행 중인 세션이 있으면 세션 정보 카드를, 없으면 "시작하기" 유도 카드를 표시
  Widget _buildTodaySession() {
    // TODO: API 연동 시 (안태환) — _mockSession을 null로 두면 빈 상태 표시
    // 현재는 항상 Mock 세션을 표시
    return AppHighlightCard(
      // TODO: CU-10 세션 로비 화면 완성 후 해당 화면으로 이동
      onTap: () {},
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
                  // TODO: API 연동 시 — 실제 세션 상태로 교체
                  _mockSession.status,
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
                  // TODO: API 연동 시 — 실제 세션 이름으로 교체
                  _mockSession.name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis, // 길면 ... 처리
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // ── 세션 상세 정보 ───────────────────────────
          Row(
            children: [
              // 멤버 수 아이콘 + 텍스트
              _buildSessionInfoItem(
                Icons.people_rounded,
                // TODO: API 연동 시 — 실제 인원 데이터로 교체
                '${_mockSession.memberCount}/${_mockSession.maxMemberCount}명 참여',
              ),

              const SizedBox(width: AppSpacing.md),

              // 예정 시간 아이콘 + 텍스트
              _buildSessionInfoItem(
                Icons.access_time_rounded,
                // TODO: API 연동 시 — 실제 예정 시간으로 교체
                _mockSession.scheduledTime,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm + 4),

          // ── "세션 입장하기" 버튼 ─────────────────────
          AppPrimaryButton(
            label: '세션 입장하기',
            height: 44, // 카드 안의 버튼은 조금 작게
            // TODO: CU-10 세션 로비 화면 완성 후 실제 네비게이션으로 교체
            onPressed: () {},
          ),
        ],
      ),
    );
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
  Widget _buildRestaurantList() {
    return SizedBox(
      // TODO: 수치 확정 시 수정 — 식당 카드 영역 높이 (현재 176px)
      height: 176,
      child: ListView.separated(
        // scrollDirection.horizontal: 가로 방향으로 스크롤
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        // 양 끝 여백: 화면 좌우 여백과 동일하게 맞춤
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
        ),
        itemCount: _mockRestaurants.length,
        // separatedBuilder: 각 아이템 사이에 구분 간격을 넣음
        separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.sm + 4),
        itemBuilder: (context, index) {
          return _buildRestaurantCard(_mockRestaurants[index]);
        },
      ),
    );
  }

  // 식당 카드 위젯 하나 (이름 / 카테고리 / 거리 / 가격 / 별점)
  Widget _buildRestaurantCard(_MockRestaurant restaurant) {
    final primary = Theme.of(context).colorScheme.primary;

    return AppCard(
      // 식당 카드 탭 → CU-16 메뉴 목록 화면으로 이동
      // TODO: CU-13 식당 상세 화면(장다연 담당) 완성 후 CU-13 → CU-16 순서로 변경
      //       현재는 CU-13을 생략하고 바로 메뉴 화면으로 진입 (데모용)
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MenuScreen(restaurantName: restaurant.name),
          ),
        );
      },
      // TODO: 수치 확정 시 수정 — 식당 카드 가로 크기 (현재 150px)
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── 식당 이미지 영역 ─────────────────────────
            // TODO: API 연동 시 — 실제 식당 이미지 URL로 교체 (Image.network)
            Container(
              height: 72,
              decoration: BoxDecoration(
                color: primary.withAlpha(15), // 이미지 없을 때 연한 주황 배경
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
              // TODO: API 연동 시 — 실제 식당 이름으로 교체
              restaurant.name,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 2),

            // ── 카테고리 ─────────────────────────────────
            Text(
              // TODO: API 연동 시 — 실제 카테고리로 교체
              restaurant.category,
              style: AppTextStyles.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),

            const Spacer(), // 남은 공간을 차지해서 하단 정보를 카드 아래로 밀어냄

            // ── 거리 + 별점 ──────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 거리
                Text(
                  // TODO: API 연동 시 — 실제 거리 계산값으로 교체
                  restaurant.distance,
                  style: AppTextStyles.caption,
                ),
                // 별점
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 12, color: primary),
                    const SizedBox(width: 2),
                    Text(
                      // TODO: API 연동 시 — 실제 별점으로 교체
                      restaurant.rating.toStringAsFixed(1),
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

// Mock 세션 데이터 구조
// TODO: API 연동 시 — lib/models/session.dart 같은 별도 모델 파일로 이전
class _MockSession {
  const _MockSession({
    required this.id,             // 세션 고유 ID
    required this.name,           // 세션 이름 (예: "개발팀 점심")
    required this.status,         // 세션 상태 (모집 중 / 투표 중 / 주문 완료)
    required this.memberCount,    // 현재 참여 인원
    required this.maxMemberCount, // 최대 수용 인원
    required this.scheduledTime,  // 예정 시간 (예: "오후 12:00")
  });
  final String id;
  final String name;
  final String status;
  final int memberCount;
  final int maxMemberCount;
  final String scheduledTime;
}

// Mock 식당 데이터 구조
// TODO: API 연동 시 — lib/models/restaurant.dart 같은 별도 모델 파일로 이전
class _MockRestaurant {
  const _MockRestaurant({
    required this.name,        // 식당 이름
    required this.category,    // 음식 카테고리 (예: "한식 · 도시락")
    required this.distance,    // 도보 거리 (예: "도보 3분")
    required this.priceRange,  // 가격대 (예: "6,500원~")
    required this.rating,      // 별점 (0.0~5.0)
    required this.reviewCount, // 리뷰 수
    required this.isOpen,      // 현재 영업 중 여부
  });
  final String name;
  final String category;
  final String distance;
  final String priceRange;
  final double rating;
  final int reviewCount;
  final bool isOpen;
}
