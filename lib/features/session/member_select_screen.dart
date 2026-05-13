import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../models/member.dart';
import '../../providers/session_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/invitations_api_service.dart';
import '../../services/sessions_api_service.dart';
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
// Mock 데이터 사용 이유:
//   친구 목록은 카카오 친구 API(우현호 담당) 또는
//   자체 백엔드 API(안태환 담당)에서 받아와야 합니다.
//   연동 전까지 화면에 직접 적힌 가짜 데이터(Mock)를 사용합니다.
//   → API 연동 시: _mockFriends 리스트를 API 응답으로 교체
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

  // ── Mock 친구 목록 ──────────────────────────────────────
  // TODO: API 연동 시 (안태환 씨) — GET /friends 또는 GET /users/friends 응답으로 교체
  // TODO: 카카오 친구 API 연동 시 (우현호 씨) — 카카오 응답을 Member 모델로 변환 후 교체
  static const List<Member> _mockFriends = [
    Member(id: 'u1', name: '안태환', organization: '개발팀'),
    Member(id: 'u2', name: '장다현', organization: '디자인팀'),
    Member(id: 'u3', name: '우현호', organization: '기획팀'),
    Member(id: 'u4', name: '최예은', organization: '개발팀'),
    Member(id: 'u5', name: '정우진', organization: '마케팅팀'),
    Member(id: 'u6', name: '한지수', organization: '개발팀'),
    Member(id: 'u7', name: '오태양', organization: '기획팀'),
    Member(id: 'u8', name: '신예린', organization: '디자인팀'),
  ];

  // ── 검색어 필터가 적용된 친구 목록 ────────────────────────
  // getter: 매번 계산이 필요한 값을 변수처럼 쓸 수 있게 해줌
  // 검색어가 없으면 전체 목록, 있으면 이름/소속에 검색어가 포함된 것만 반환
  List<Member> get _filteredFriends {
    if (_searchQuery.isEmpty) return _mockFriends;
    return _mockFriends.where((member) =>
      member.name.contains(_searchQuery) ||
      member.organization.contains(_searchQuery),
    ).toList();
  }

  // ── 다음 버튼 활성 여부 ────────────────────────────────
  // 1명 이상 선택했을 때만 "조건 설정하기" 버튼 활성화
  bool get _canProceed => _selectedIds.isNotEmpty;

  // ── 생명주기: 화면이 처음 만들어질 때 ──────────────────
  @override
  void initState() {
    super.initState();
    DebugToast.show(context, 'CU-08');
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

        // ── 화면 제목 ────────────────────────────────────
        Text(
          '함께 먹을 사람을\n선택해주세요',
          style: AppTextStyles.heading1,
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
      hint: '이름 또는 소속으로 검색',
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
  Widget _buildFriendList() {
    final friends = _filteredFriends;

    // 검색 결과 없음 상태
    if (friends.isEmpty) {
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
  Widget _buildFriendItem(Member member) {
    final isSelected = _selectedIds.contains(member.id);
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: () {
        setState(() {
          // 이미 선택된 경우 → 선택 해제, 아닌 경우 → 선택 추가
          if (isSelected) {
            _selectedIds.remove(member.id);
          } else {
            _selectedIds.add(member.id);
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

            // ── 프로필 아바타 (이름 첫 글자) ──────────────
            // TODO: API 연동 시 — 실제 프로필 이미지 URL이 있으면 CircleAvatar(backgroundImage)로 교체
            CircleAvatar(
              radius: 22,
              backgroundColor: isSelected
                  ? primary.withAlpha(40)
                  : AppColors.backgroundGrey,
              child: Text(
                member.name[0], // 이름의 첫 글자만 표시 (예: "김민준" → "김")
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isSelected ? primary : AppColors.textSecondary,
                ),
              ),
            ),

            const SizedBox(width: AppSpacing.md),

            // ── 이름 + 소속 ────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      // 선택됨: primary 색상으로 이름 강조
                      color: isSelected ? primary : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    member.organization,
                    style: AppTextStyles.bodySmall,
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
                    // _selectedIds(ID 집합)에 해당하는 Member 객체만 필터링
                    final selectedMembers = _mockFriends
                        .where((m) => _selectedIds.contains(m.id))
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