import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../models/member.dart';
import '../../providers/session_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/friends_api_service.dart';
import '../../services/invitations_api_service.dart';
import '../../services/sessions_api_service.dart';
import '../friends/friends_screen.dart';
import 'session_lobby_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-08 친구/멤버 리스트 화면
//
// 와이어프레임 기준 구성 요소:
//   - 상단 단계 표시바: 1.인원(현재) → 2.조건 → 3.AI추천
//   - 화면 제목: "함께 먹을 사람을 선택해주세요"
//   - 검색창: 이름 또는 소속으로 필터링
//   - 친구 목록: 프로필 아바타 + 이름 + 소속 + 체크박스
//   - 하단: 선택된 인원 수 표시 + "조건 설정하기" 버튼
//
// 동작 흐름:
//   홈 대시보드(CU-06) "친구 초대" 버튼
//     → 이 화면 (멤버 선택)
//       → "조건 설정하기" 버튼
//         → sessionProvider에 선택 멤버 저장
//         → CU-09 세션 생성 조건 설정 화면 (우현호 담당)
//
// 친구 데이터 출처:
//   2026-05-14 백엔드 friends API 연동 완료.
//   GET  /api/friends 로 목록 조회 → FriendDto 리스트 사용.
//   친구 추가/삭제는 별도 화면(FriendsScreen) 에서 수행.
//
// Riverpod 연동:
//   "조건 설정하기" 버튼 탭 시 선택된 멤버 목록을 sessionProvider에 저장합니다.
//   CU-09(우현호 담당)에서 ref.watch(sessionProvider).selectedMembers 로 읽습니다.
//   UI 선택 상태(_selectedIds)는 여전히 로컬 setState로 관리합니다.
//   (로컬 체크박스 상태는 전역으로 올릴 필요 없음)
//
// TODO (우현호 씨와 CU-09 연동 시 확인):
//   - CU-09가 Member 데이터 중 어떤 필드를 실제로 쓰는지
//   - kakaoId 같은 추가 필드가 필요한지
//   형태가 달라지더라도 models/member.dart 수정 + 변환 함수 추가로 대응 가능
// ══════════════════════════════════════════════════════════

// ── ConsumerStatefulWidget으로 변환한 이유 ─────────────────
// Riverpod의 ref(참조 객체)를 StatefulWidget 내부에서 사용하려면
// ConsumerStatefulWidget + ConsumerState 조합이 필요합니다.
// ref를 통해 sessionProvider에 선택된 멤버 목록을 저장합니다.
class MemberSelectScreen extends ConsumerStatefulWidget {
  const MemberSelectScreen({
    super.key,
    required this.onNext,
  });

  /// 멤버 선택 완료 후 실행되는 함수 (네비게이션 전담)
  /// 실제 멤버 데이터는 sessionProvider에 저장되므로
  /// 이 콜백은 "다음 화면으로 이동" 로직만 담당합니다.
  /// CU-09(우현호 담당)는 sessionProvider에서 멤버를 읽으면 됩니다.
  final void Function(List<Member> selectedMembers) onNext;

  @override
  ConsumerState<MemberSelectScreen> createState() => _MemberSelectScreenState();
}

class _MemberSelectScreenState extends ConsumerState<MemberSelectScreen> {

  // ── 선택된 멤버 ID 집합 ─────────────────────────────────
  // Set을 사용하는 이유: 같은 ID가 두 번 추가되는 일이 없도록 중복을 자동 제거
  final Set<String> _selectedIds = {};

  // ── 검색 컨트롤러 및 검색어 ────────────────────────────
  // TextEditingController: 검색창의 텍스트를 프로그래밍으로 읽거나 초기화할 때 사용
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = ''; // 현재 입력된 검색어

  // ── 친구 목록 (서버에서 받아온 실제 친구) ───────────────────
  // 2026-05-14 (백엔드 friends API 연동):
  //   - 기존 _mockFriends = <Member>[] 자리 → 서버 응답 캐시로 교체
  //   - initState 에서 GET /api/friends 로 채움
  //   - FriendsScreen 다녀온 후에도 다시 fetch 해서 최신 동기화
  // 백엔드 FriendDto: { id, name, email, profileImage, since }
  List<FriendDto> _friends = const [];

  // 친구 목록 로딩 중인지 (true: 로딩 스피너 표시)
  bool _isLoadingFriends = true;

  // 친구 API 서비스 (const 인스턴스라 매번 새로 만들 필요 없음)
  static const _friendsApi = FriendsApiService();

  // ── 검색어 필터가 적용된 친구 목록 ────────────────────────
  // getter: 매번 계산이 필요한 값을 변수처럼 쓸 수 있게 해줌
  // 검색어가 없으면 전체 목록, 있으면 이름/이메일에 검색어가 포함된 것만 반환
  List<FriendDto> get _filteredFriends {
    if (_searchQuery.isEmpty) return _friends;
    final q = _searchQuery.toLowerCase();
    return _friends.where((friend) {
      final email = (friend.email ?? '').toLowerCase();
      return friend.name.toLowerCase().contains(q) || email.contains(q);
    }).toList();
  }

  // ── 다음 버튼 활성 여부 ────────────────────────────────
  // 2026-05-14: 친구 목록 없어도 호스트 혼자 세션 가능 → 항상 true.
  // 친구가 있어도 선택 안 해도 OK (초대 코드 흐름으로 모집).
  bool get _canProceed => true;

  // ── 생명주기: 화면이 처음 만들어질 때 ──────────────────
  @override
  void initState() {
    super.initState();
    DebugToast.show(context, 'CU-08');
    // 서버에서 친구 목록 비동기로 가져오기 (build 와 분리)
    Future.microtask(_loadFriends);
  }

  // ── 친구 목록 새로고침 ────────────────────────────────────
  // 로그인 토큰이 없으면 빈 리스트로 빠르게 종료.
  // mounted 체크: 비동기 응답 도착 전에 화면이 닫혔을 수 있음.
  Future<void> _loadFriends() async {
    final accessToken = ref.read(userProvider).accessToken;
    if (accessToken == null) {
      if (!mounted) return;
      setState(() {
        _friends = const [];
        _isLoadingFriends = false;
      });
      return;
    }

    final list = await _friendsApi.listFriends(accessToken: accessToken);
    if (!mounted) return;
    setState(() {
      _friends = list;
      _isLoadingFriends = false;
      // 서버에서 사라진 친구가 _selectedIds 에 남아있을 수 있어 정리
      final validIds = _friends.map((f) => f.id).toSet();
      _selectedIds.removeWhere((id) => !validIds.contains(id));
    });
  }

  // ── "친구 추가" 화면 열기 ─────────────────────────────────
  // FriendsScreen 에서 친구 추가/삭제 후 돌아오면 목록 자동 새로고침
  Future<void> _openFriendsScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FriendsScreen()),
    );
    if (!mounted) return;
    // 돌아오면 무조건 fetch — 추가/삭제 어떤 변화가 있었는지 확실하지 않음
    await _loadFriends();
  }

  // ── 위젯이 화면에서 제거될 때 컨트롤러 메모리 해제 ───────
  // dispose를 안 하면 메모리 누수(memory leak) 발생
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── UI 구성 ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      // 뒤로가기 버튼 있는 앱바 (홈으로 돌아갈 수 있음)
      appBar: AppCustomBar(showBack: true),

      body: SafeArea(
        child: Column(
          children: [

            // ── 스크롤 가능한 콘텐츠 영역 ──────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    const SizedBox(height: AppSpacing.lg),

                    // ── 세션 생성 단계 표시바 ───────────────
                    _buildStepIndicator(),

                    const SizedBox(height: AppSpacing.lg),

                    // ── 화면 제목 + 단계명 안내 ─────────────
                    _buildHeader(),

                    const SizedBox(height: AppSpacing.md),

                    // ── 친구 검색창 ────────────────────────
                    _buildSearchField(),

                    const SizedBox(height: AppSpacing.md),

                    // ── 친구 목록 ──────────────────────────
                    _buildFriendList(),

                    // 하단 버튼과 겹치지 않도록 여유 공간
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),

            // ── 하단 고정 버튼 영역 ────────────────────────
            _buildBottomButton(),
          ],
        ),
      ),
    );
  }

  // ── 초대 링크 생성 핸들러 (CORE-02) ───────────────────────
  Future<void> _handleCreateInviteLink(BuildContext context) async {
    final accessToken = ref.read(userProvider).accessToken;
    if (accessToken == null) return;

    // 세션이 아직 없으면 먼저 생성
    const sessionsApi = SessionsApiService();
    const invitationsApi = InvitationsApiService();

    final session = await sessionsApi.createSession(
      accessToken: accessToken,
      name: '점심 세션',
    );

    if (session == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        // 친근한 톤 + 다음 액션(재시도) 자연 유도
        const SnackBar(content: Text('세션을 만들지 못했어요. 잠시 후 다시 시도해봐요')),
      );
      return;
    }

    final invitation = await invitationsApi.createInvitation(
      accessToken: accessToken,
      sessionId: session.id,
    );

    if (!context.mounted) return;

    if (invitation != null) {
      // 세션 로비 화면으로 이동 (호스트 모드 — inviteCode 포함)
      // createSession 응답을 initialSession으로 넘겨 불필요한 재조회 방지
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SessionLobbyScreen(
            sessionId: session.id,
            inviteCode: invitation.inviteCode,
            initialSession: session,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        // 친근한 톤 + 다음 액션 안내
        const SnackBar(content: Text('초대 링크를 만들지 못했어요. 다시 시도해봐요')),
      );
    }
  }

  // ── 세션 생성 단계 표시바 위젯 ─────────────────────────────
  // 3단계 중 현재 1단계(인원 선택)가 활성화된 상태를 색상으로 표시
  // condition_setup_screen.dart의 _buildStepIndicator와 동일한 구조이나
  // 활성 단계가 1단계로 다름 (조건 설정은 2단계까지 활성)
  Widget _buildStepIndicator() {
    return Row(
      children: List.generate(
        3,
        (index) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index < 2 ? 4 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              decoration: BoxDecoration(
                // 0번(1단계=현재): 활성 → primary 색상
                // 1번(2단계), 2번(3단계): 미완료 → 연한 회색
                color: index == 0
                    ? Theme.of(context).colorScheme.primary
                    : AppColors.border,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 화면 제목 + 단계 안내 문구 위젯 ───────────────────────
  Widget _buildHeader() {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── 단계 안내 레이블 행 ────────────────────────────
        // "1단계 인원  ·  2단계 조건  ·  3단계 AI추천" 형태로 표시
        // 현재 단계만 primary 색상으로 강조, 나머지는 흐리게
        Row(
          children: [
            // 현재 단계 (강조)
            Text(
              '1단계 인원',
              style: AppTextStyles.label.copyWith(
                color: primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            // 구분자
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '·',
                style: AppTextStyles.label.copyWith(
                  color: AppColors.textHint,
                ),
              ),
            ),
            // 이후 단계 (흐리게)
            Text(
              '2단계 조건',
              style: AppTextStyles.label.copyWith(
                color: AppColors.textHint,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '·',
                style: AppTextStyles.label.copyWith(
                  color: AppColors.textHint,
                ),
              ),
            ),
            Text(
              '3단계 AI추천',
              style: AppTextStyles.label.copyWith(
                color: AppColors.textHint,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // ── 화면 제목 + "친구 추가" 작은 버튼 한 줄 ─────────
        // 제목과 같은 줄에 우측 정렬로 friends_screen 진입점 노출
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '함께 먹을 사람을\n선택해주세요',
                style: AppTextStyles.heading1,
              ),
            ),
            // 친구 추가/관리 버튼 (FriendsScreen 으로 이동)
            // OutlinedButton.icon — primary 톤만 사용, 새 색상 없음
            OutlinedButton.icon(
              onPressed: _openFriendsScreen,
              icon: Icon(
                Icons.person_add_alt_1_rounded,
                size: 16,
                color: primary,
              ),
              label: Text(
                '친구 추가',
                style: AppTextStyles.bodySmall.copyWith(
                  color: primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: primary.withAlpha(80)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // ── 안내 문구 ────────────────────────────────────
        // TODO: 수정 필요 — 실제 안내 문구로 교체
        Text(
          '선택한 멤버와 함께 점심 조건을 맞춰갈게요',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // ── 친구 검색창 위젯 ────────────────────────────────────────
  Widget _buildSearchField() {
    return AppTextField(
      controller: _searchController,
      hint: '이름 또는 이메일로 검색',
      // prefixIcon은 Widget 타입이므로 Icon() 위젯으로 감싸서 전달
      prefixIcon: const Icon(Icons.search_rounded, size: 20),
      onChanged: (value) {
        // 검색어가 바뀔 때마다 화면을 다시 그려서 필터 목록 업데이트
        setState(() => _searchQuery = value);
      },
    );
  }

  // ── 친구 목록 위젯 ──────────────────────────────────────────
  // 검색 결과가 없으면 안내 문구, 있으면 항목 목록 표시
  //
  // 2026-05-14: 백엔드 friends API 연동.
  //   - 로딩 중: 스피너
  //   - 친구 0명: 빈 상태 안내 + "친구 추가" 환기 + 초대 코드 흐름 유지
  //   - 검색어 있을 때: "검색 결과 없음"
  Widget _buildFriendList() {
    final primary = Theme.of(context).colorScheme.primary;

    // 로딩 중에는 스피너 표시 (서버 응답 도착 전 깜빡임 방지)
    if (_isLoadingFriends) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: primary,
            ),
          ),
        ),
      );
    }

    final friends = _filteredFriends;

    // 비어있을 때 — 검색어 유무에 따라 안내 분기
    if (friends.isEmpty) {
      // 검색어 있을 때는 단순 안내
      if (_searchQuery.isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(
            child: Text(
              '검색 결과가 없어요',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        );
      }

      // 검색어 없을 때 — 친근 빈 상태 + 다음 액션 명확 환기
      return Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: primary.withAlpha(15),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: primary.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.group_add_rounded, color: primary, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '아직 친구 목록이 비어 있어요',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '오른쪽 위 "친구 추가"로 친구를 등록하거나,\n'
              '"조건 설정하기"로 혼자 진행하거나,\n'
              '아래 "초대 링크 복사하기"로 바로 불러봐요.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    // 친구 항목 목록 (Column으로 세로 나열)
    // ListView 대신 Column을 사용하는 이유:
    //   부모에 이미 SingleChildScrollView가 있으므로
    //   내부에 또 스크롤 가능한 ListView를 쓰면 충돌 발생
    return Column(
      children: friends.map(_buildFriendItem).toList(),
    );
  }

  // ── 친구 항목 하나 위젯 ─────────────────────────────────────
  // 선택 여부에 따라 배경색, 테두리색, 체크박스, 글자 색이 애니메이션으로 변함
  //
  // 2026-05-14: 파라미터를 Member → FriendDto 로 교체.
  //   - id/name 는 동일하게 사용
  //   - 기존 "organization" 자리는 친구의 email 로 대체 (서버가 주는 값)
  //   - profileImage 가 있으면 CircleAvatar 에 NetworkImage 로 표시
  Widget _buildFriendItem(FriendDto friend) {
    final isSelected = _selectedIds.contains(friend.id);
    final primary = Theme.of(context).colorScheme.primary;
    final hasImage = (friend.profileImage ?? '').isNotEmpty;
    // 이메일이 비어있어도 빈 줄 안 나오게 분기 처리
    final subtitle = (friend.email ?? '').isNotEmpty ? friend.email! : '친구';

    return GestureDetector(
      onTap: () {
        setState(() {
          // 이미 선택된 경우 → 선택 해제, 아닌 경우 → 선택 추가
          if (isSelected) {
            _selectedIds.remove(friend.id);
          } else {
            _selectedIds.add(friend.id);
          }
        });
      },
      child: AnimatedContainer(
        // 선택/해제 시 색상이 부드럽게 전환됨
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          // 선택됨: 연한 primary 배경, 아님: 흰색 배경
          color: isSelected
              ? primary.withAlpha(18)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            // 선택됨: primary 테두리, 아님: 회색 테두리
            color: isSelected ? primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [

            // ── 프로필 아바타 ──────────────────────────────
            // 카카오 프로필 이미지 URL 이 있으면 NetworkImage, 없으면 첫 글자
            CircleAvatar(
              radius: 22,
              backgroundColor: isSelected
                  ? primary.withAlpha(40)
                  : AppColors.backgroundGrey,
              backgroundImage:
                  hasImage ? NetworkImage(friend.profileImage!) : null,
              child: hasImage
                  ? null
                  : Text(
                      // 이름이 비어있을 가능성을 방어 ('?' 표시)
                      friend.name.isNotEmpty ? friend.name[0] : '?',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isSelected ? primary : AppColors.textSecondary,
                      ),
                    ),
            ),

            const SizedBox(width: AppSpacing.md),

            // ── 이름 + 이메일 ──────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      // 선택됨: primary 색상으로 이름 강조
                      color: isSelected ? primary : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // ── 체크박스 ─────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                // 선택됨: primary 색 채워진 박스, 아님: 투명 박스
                color: isSelected ? primary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? primary : AppColors.border,
                  width: 2,
                ),
              ),
              // 선택됐을 때만 체크 아이콘 표시
              child: isSelected
                  ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ── 하단 고정 버튼 영역 위젯 ──────────────────────────────────
  // 선택된 인원 수 표시 + "조건 설정하기" 버튼
  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        12,
        AppSpacing.screenHorizontal,
        32,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Column이 내용물 크기만큼만 차지
        children: [

          // ── 선택된 인원 수 안내 (선택 시에만 표시) ──────
          // ...[]: if문 안의 여러 위젯을 Column children에 넣을 때 사용하는 spread 문법
          if (_selectedIds.isNotEmpty) ...[
            Text(
              '${_selectedIds.length}명 선택됨',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],

          // ── "초대 링크 복사" 버튼 (CORE-02) ─────────────
          AppOutlinedButton(
            label: '초대 링크 복사하기',
            onPressed: () => _handleCreateInviteLink(context),
          ),

          const SizedBox(height: 8),

          // ── "조건 설정하기" 버튼 ────────────────────────
          // onPressed가 null이면 버튼 비활성화(회색)됨
          // 1명 이상 선택해야 활성화
          AppPrimaryButton(
            label: '조건 설정하기',
            onPressed: _canProceed
                ? () {
                    // ── 선택된 Member 객체 목록 구성 ──────────────
                    // _selectedIds(ID 집합)에 해당하는 친구를 골라
                    // FriendDto → Member 로 변환(organization 자리에 email).
                    // CU-09 는 Member 의 id/name 만 사용하므로 호환 OK.
                    final selectedMembers = _friends
                        .where((f) => _selectedIds.contains(f.id))
                        .map((f) => Member(
                              id: f.id,
                              name: f.name,
                              organization: f.email ?? '친구',
                            ))
                        .toList();

                    // ── Riverpod: sessionProvider에 선택 멤버 저장 ─
                    // CU-09(우현호 담당)에서
                    //   ref.watch(sessionProvider).selectedMembers 로 읽을 수 있게 됨
                    // ref.read: 상태 변경(쓰기)은 read를 사용 (watch는 UI 감시용)
                    ref
                        .read(sessionProvider.notifier)
                        .setSelectedMembers(selectedMembers);

                    // ── 화면 이동 콜백 실행 ───────────────────────
                    // 데이터는 이미 Provider에 저장됐으므로
                    // 콜백은 순수하게 "다음 화면으로 이동"만 담당
                    widget.onNext(selectedMembers);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}


// ── Member 모델 이동 안내 ──────────────────────────────────
// Member 클래스는 lib/models/member.dart 로 이동되었습니다.
// 이 파일 상단의 import '../../models/member.dart' 로 가져옵니다.