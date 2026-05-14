import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/user_provider.dart';
import '../../services/friends_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 친구 관리 화면 (CU-08 보강)
//
// 화면 구성:
//   - 상단 앱바 ("친구 관리")
//   - 친구 추가 카드: 이메일 입력 + "추가" 버튼
//   - 친구 목록: CircleAvatar + 이름 + 이메일 + 삭제 버튼
//   - 빈 상태: 친구가 없을 때 친근한 안내 박스
//
// 동작 흐름:
//   1) initState 에서 GET /friends 호출 → 목록 표시
//   2) 사용자가 이메일 입력 후 "추가" 누르면 POST /friends
//      - 성공: SnackBar "친구가 추가되었어요" + 목록 새로고침
//      - 이미 친구: SnackBar "이미 친구로 등록되어 있어요"
//      - 없는 사용자: SnackBar "해당 이메일로 가입한 사용자가 없어요"
//      - 잘못된 요청: SnackBar 백엔드 메시지 그대로
//      - 네트워크 오류: SnackBar "잠시 후 다시 시도해봐요"
//   3) 친구 항목 우측 삭제 버튼 → 확인 다이얼로그 → DELETE /friends/:id
//      - 성공: 즉시 목록에서 제거 (낙관적 업데이트는 안 함, 서버 응답 후 갱신)
//
// 호출 위치:
//   MemberSelectScreen 상단 "친구 추가" 버튼 → FriendsScreen push
//   FriendsScreen 에서 pop 시 MemberSelectScreen 이 자동 refresh
//
// 디자인 토큰:
//   AppColors / AppTextStyles / AppSpacing / AppRadius +
//   Theme.of(context).colorScheme.primary 만 사용 (새 색상 추가 0건)
// ══════════════════════════════════════════════════════════

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  // ── API 서비스 (const 라 매 빌드마다 재생성 비용 0) ─────────
  static const _api = FriendsApiService();

  // ── 친구 목록 (서버 응답 캐시) ────────────────────────────
  List<FriendDto> _friends = const [];

  // ── 로딩 플래그 ───────────────────────────────────────────
  bool _isLoadingList = true; // 초기 GET /friends 진행 중인지
  bool _isAdding = false;     // POST /friends 진행 중인지 (버튼 비활성용)

  // ── 이메일 입력 컨트롤러 ──────────────────────────────────
  // dispose 에서 메모리 해제 필수
  final TextEditingController _emailController = TextEditingController();

  // ── 생명주기: 화면이 처음 만들어질 때 1회 호출 ────────────
  @override
  void initState() {
    super.initState();
    // build 가 완료된 뒤에 호출되도록 microtask 로 띄움
    // (initState 안에서 직접 setState 호출은 안전하지만,
    //  await 가 섞이면 build 와 충돌할 수 있어 분리)
    Future.microtask(_loadFriends);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  // ── 친구 목록 새로고침 ────────────────────────────────────
  // - 토큰 없으면 빈 리스트로 끝냄
  // - 응답 받은 뒤 mounted 체크: 화면 사라진 후 setState 방지
  Future<void> _loadFriends() async {
    final accessToken = ref.read(userProvider).accessToken;
    if (accessToken == null) {
      if (!mounted) return;
      setState(() {
        _friends = const [];
        _isLoadingList = false;
      });
      return;
    }

    final list = await _api.listFriends(accessToken: accessToken);
    if (!mounted) return;
    setState(() {
      _friends = list;
      _isLoadingList = false;
    });
  }

  // ── 친구 추가 핸들러 ──────────────────────────────────────
  // - 이메일 비어있으면 안내 후 종료
  // - 추가 중에는 버튼 비활성화 (_isAdding)
  // - 결과 타입(AddFriendResult)별로 SnackBar 문구 분기
  // - 성공 시 입력창 비우고 목록 새로고침
  Future<void> _handleAddFriend() async {
    final accessToken = ref.read(userProvider).accessToken;
    if (accessToken == null) return;

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showSnack('이메일을 입력해주세요.');
      return;
    }

    setState(() => _isAdding = true);
    final result = await _api.addFriend(
      accessToken: accessToken,
      email: email,
    );
    if (!mounted) return;
    setState(() => _isAdding = false);

    // 결과 타입별 분기 처리
    switch (result) {
      case AddFriendSuccess(:final friend):
        _emailController.clear();
        _showSnack('${friend.name}님과 친구가 되었어요!');
        await _loadFriends();
      case AddFriendNotFound():
        _showSnack('해당 이메일로 가입한 사용자가 없어요. 친구가 먼저 가입해야 해요.');
      case AddFriendDuplicate():
        _showSnack('이미 친구로 등록되어 있어요.');
      case AddFriendInvalid(:final message):
        _showSnack(message);
      case AddFriendError():
        _showSnack('친구를 추가하지 못했어요. 잠시 후 다시 시도해봐요.');
    }
  }

  // ── 친구 삭제 핸들러 ──────────────────────────────────────
  // 실수로 누르는 일을 막기 위해 확인 다이얼로그 표시
  Future<void> _handleRemoveFriend(FriendDto friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('친구 삭제'),
        content: Text('${friend.name}님을 친구 목록에서 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              '삭제',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final accessToken = ref.read(userProvider).accessToken;
    if (accessToken == null) return;

    final ok = await _api.removeFriend(
      accessToken: accessToken,
      friendUserId: friend.id,
    );
    if (!mounted) return;
    if (ok) {
      _showSnack('${friend.name}님을 친구 목록에서 삭제했어요.');
      await _loadFriends();
    } else {
      _showSnack('삭제하지 못했어요. 잠시 후 다시 시도해봐요.');
    }
  }

  // ── 공용 SnackBar 헬퍼 ────────────────────────────────────
  // 한 곳에 모아 톤(친근체) 일관 유지 + 중복 코드 제거
  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ── UI 구성 ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppCustomBar(
        title: '친구 관리',
        showBack: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 안내 헤더 ───────────────────────────────────
              Text(
                '이메일로 친구를 추가해요',
                style: AppTextStyles.heading2,
              ),
              const SizedBox(height: 6),
              Text(
                '추가한 친구는 다음 세션 만들 때 함께 초대할 수 있어요.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // ── 친구 추가 카드 ──────────────────────────────
              _buildAddFriendCard(),

              const SizedBox(height: AppSpacing.lg),

              // ── 친구 목록 섹션 제목 ─────────────────────────
              Row(
                children: [
                  Text(
                    '내 친구',
                    style: AppTextStyles.heading3,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // 친구 수 배지 (목록 로딩 중에는 표시 안 함)
                  if (!_isLoadingList)
                    Text(
                      '${_friends.length}',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: AppSpacing.md),

              // ── 친구 목록 본문 ──────────────────────────────
              _buildFriendListBody(),

              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  // ── 친구 추가 카드 위젯 ───────────────────────────────────
  // 이메일 입력창 + 추가 버튼을 한 카드로 묶음
  Widget _buildAddFriendCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          AppTextField(
            controller: _emailController,
            hint: '친구 이메일 (예: friend@lunchsync.com)',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            prefixIcon: const Icon(Icons.mail_outline_rounded, size: 20),
            // 키보드 완료 버튼으로도 추가 가능 (입력 후 엔터)
            onSubmitted: (_) {
              if (!_isAdding) _handleAddFriend();
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          AppPrimaryButton(
            label: _isAdding ? '추가하는 중...' : '친구 추가',
            isLoading: _isAdding,
            onPressed: _handleAddFriend,
          ),
        ],
      ),
    );
  }

  // ── 친구 목록 본문 위젯 ───────────────────────────────────
  // 로딩 중 / 빈 상태 / 정상 목록 3가지 분기
  Widget _buildFriendListBody() {
    if (_isLoadingList) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    if (_friends.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: _friends.map(_buildFriendItem).toList(),
    );
  }

  // ── 친구 비어있을 때 안내 박스 위젯 ─────────────────────────
  // member_select_screen 빈 상태와 유사한 톤 + primary 강조
  Widget _buildEmptyState() {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
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
                  '아직 친구가 없어요',
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
            '위에서 친구의 이메일을 입력하고\n'
            '"친구 추가" 버튼을 눌러봐요.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── 친구 1명 항목 위젯 ────────────────────────────────────
  // 프로필 이미지가 있으면 NetworkImage 로, 없으면 이름 첫 글자로 폴백
  Widget _buildFriendItem(FriendDto friend) {
    final primary = Theme.of(context).colorScheme.primary;
    final hasImage = (friend.profileImage ?? '').isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // ── 프로필 아바타 ───────────────────────────────────
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.backgroundGrey,
            backgroundImage:
                hasImage ? NetworkImage(friend.profileImage!) : null,
            child: hasImage
                ? null
                : Text(
                    // 이름이 비어있을 가능성을 방어 ('?' 표시)
                    friend.name.isNotEmpty ? friend.name[0] : '?',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.md),

          // ── 이름 + 이메일 ───────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if ((friend.email ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    friend.email!,
                    style: AppTextStyles.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // ── 삭제 버튼 ───────────────────────────────────────
          // IconButton 의 padding 을 줄여 라인 높이 안에 맞춤
          IconButton(
            onPressed: () => _handleRemoveFriend(friend),
            icon: Icon(
              Icons.person_remove_alt_1_rounded,
              color: primary,
              size: 22,
            ),
            tooltip: '친구 삭제',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
