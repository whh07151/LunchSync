import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../providers/user_provider.dart';
import '../../services/users_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-23 내정보/설정 화면
//
// 와이어프레임 기준 구성 요소:
//   - 프로필 섹션: 프로필 사진 + 이름 + 소속 (편집 가능)
//   - 내 설정 섹션: 반경 / 예산 / 식사 속도 (편집 가능)
//   - 앱 설정 섹션: 알림 설정 (준비 중), 버전 정보
//   - 하단: 로그아웃 버튼
//
// 데이터 전략:
//   - 화면 진입 시 GET /api/users/me 로 DB 최신값 조회 → 컨트롤러/상태 초기화
//   - 저장 버튼: PATCH /api/users/me 호출 → 성공 시 userProvider도 갱신
//   - 취소 버튼: 마지막으로 조회한 DB 원본값으로 복구
//
// 동작 흐름:
//   홈 하단 탭(4번 내정보) → 이 화면 → initState에서 GET /users/me 호출
//   "편집" 버튼 탭 → 인라인 편집 모드 전환
//   편집 완료 후 "저장" 탭 → PATCH /users/me → userProvider 갱신
//   로그아웃 탭 → 확인 다이얼로그 → 로그인 화면으로 이동
//
// TODO: _logout() → 카카오 SDK unlink + JWT 삭제 + 로그인 화면 이동
// ══════════════════════════════════════════════════════════

// ConsumerStatefulWidget: userProvider(JWT)를 읽고, 저장 후 갱신하기 위해 사용
class MyInfoScreen extends ConsumerStatefulWidget {
  const MyInfoScreen({
    super.key,
    this.onLogout, // 로그아웃 완료 시 로그인 화면으로 이동하는 콜백
  });

  /// 로그아웃 후 실행되는 함수 (로그인 화면으로 이동)
  /// null이면 로그아웃 버튼 미표시 (탭 내부 embed 용도)
  final VoidCallback? onLogout;

  @override
  ConsumerState<MyInfoScreen> createState() => _MyInfoScreenState();
}

class _MyInfoScreenState extends ConsumerState<MyInfoScreen> {

  // ── API 서비스 ────────────────────────────────────────────
  static const _usersApiService = UsersApiService();

  // ── 로딩/저장 중 여부 ────────────────────────────────────
  // true일 때 버튼 비활성화, 로딩 표시
  bool _isLoading = true;
  bool _isSaving = false;

  // ── 편집 모드 여부 ────────────────────────────────────────
  // true: 텍스트 필드와 칩이 활성화되어 수정 가능
  // false: 읽기 전용으로 표시 (기본 상태)
  bool _isEditing = false;

  // ── 텍스트 입력 컨트롤러 ─────────────────────────────────
  // 이름과 소속 필드 편집에 사용
  late TextEditingController _nameController;
  late TextEditingController _orgController;

  // ── 설정 선택 상태 ────────────────────────────────────────
  // 반경/예산/속도는 칩 선택 방식으로 편집
  // 기본값: 로딩 전 빈 상태 (GET /users/me 완료 후 채워짐)
  String _selectedRadius = '500m';
  String _selectedBudget = '1만원 이하';
  String _selectedSpeed = 'NORMAL';

  // ── DB 원본값 (취소 시 복구용) ────────────────────────────
  // GET /users/me 성공 시 저장해두고, 편집 취소 시 이 값으로 되돌림
  String _originalName = '';
  String _originalOrg = '';
  String _originalRadius = '500m';
  String _originalBudget = '1만원 이하';
  String _originalSpeed = 'NORMAL';

  // ── 선택지 목록 ──────────────────────────────────────────
  // CU-05 condition_setup_screen.dart와 동일한 옵션
  static const List<String> _radiusOptions = ['300m', '500m', '1km', '2km'];
  static const List<String> _budgetOptions = [
    '5천원 이하',
    '8천원 이하',
    '1만원 이하',
    '1만5천원 이하',
    '제한 없음',
  ];
  static const List<String> _speedOptions = ['FAST', 'NORMAL', 'SLOW'];

  // API 값 → 화면 표시 한국어 레이블
  static const Map<String, String> _speedLabel = {
    'FAST': '빠르게',
    'NORMAL': '보통',
    'SLOW': '여유롭게',
  };

  // ── 생명주기: 초기화 ─────────────────────────────────────
  @override
  void initState() {
    super.initState();
    DebugToast.show(context, 'CU-23');

    // 컨트롤러 초기화 (빈 값 → _loadProfile 완료 후 채워짐)
    _nameController = TextEditingController();
    _orgController = TextEditingController();

    // 첫 프레임 렌더링 후 DB에서 프로필 조회
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfile();
    });
  }

  // ── 생명주기: 메모리 해제 ────────────────────────────────
  @override
  void dispose() {
    _nameController.dispose();
    _orgController.dispose();
    super.dispose();
  }

  // ── DB에서 프로필 조회 후 컨트롤러/상태 초기화 ─────────────
  // GET /api/users/me → 이름/소속/반경/예산/속도를 실제 DB값으로 설정
  Future<void> _loadProfile() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      setState(() => _isLoading = false);
      return;
    }

    final profile = await _usersApiService.getMe(token);

    if (!mounted) return;

    if (profile != null) {
      // DB 값을 화면 표시용 문자열로 변환 후 상태 반영
      final name   = profile.name;
      final org    = profile.org ?? '';
      final radius = profile.radius ?? '500m';
      final budget = _intToBudget(profile.budget);
      final speed  = profile.speed ?? 'NORMAL';

      setState(() {
        _isLoading = false;

        // 컨트롤러에 실제 값 적용
        _nameController.text = name;
        _orgController.text  = org;

        // 칩 선택 상태 적용
        _selectedRadius = radius;
        _selectedBudget = budget;
        _selectedSpeed  = speed;

        // 원본값 저장 (취소 시 복구용)
        _originalName   = name;
        _originalOrg    = org;
        _originalRadius = radius;
        _originalBudget = budget;
        _originalSpeed  = speed;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  // ── int 예산값 → 칩 표시 문자열 변환 ─────────────────────
  // condition_setup_screen.dart의 _budgetToInt()의 역방향 변환
  // DB에 저장된 정수를 UI 칩 선택지 문자열로 바꿈
  String _intToBudget(int? value) {
    switch (value) {
      case 5000:  return '5천원 이하';
      case 8000:  return '8천원 이하';
      case 10000: return '1만원 이하';
      case 15000: return '1만5천원 이하';
      default:    return '제한 없음'; // null 또는 미지정
    }
  }

  // ── 칩 표시 문자열 → int 예산값 변환 ─────────────────────
  // PATCH /users/me 호출 시 budget 필드에 사용
  int? _budgetToInt(String budget) {
    switch (budget) {
      case '5천원 이하':    return 5000;
      case '8천원 이하':    return 8000;
      case '1만원 이하':    return 10000;
      case '1만5천원 이하': return 15000;
      case '제한 없음':     return null;
      default:             return null;
    }
  }

  // ── 편집 시작 ────────────────────────────────────────────
  void _startEditing() => setState(() => _isEditing = true);

  // ── 편집 취소: GET /users/me로 받은 원본값으로 복구 ────────
  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _nameController.text = _originalName;
      _orgController.text  = _originalOrg;
      _selectedRadius      = _originalRadius;
      _selectedBudget      = _originalBudget;
      _selectedSpeed       = _originalSpeed;
    });
  }

  // ── 변경 사항 저장: PATCH /api/users/me 호출 ─────────────
  // 성공 시: userProvider 갱신 + 원본값 업데이트 + 편집 모드 종료
  // 실패 시: 스낵바로 에러 안내
  Future<void> _saveChanges() async {
    if (_isSaving) return;

    // 이름이 비어 있으면 저장 불가
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이름을 입력해주세요')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final token = ref.read(userProvider).accessToken;
    bool success = false;

    if (token != null) {
      success = await _usersApiService.updateMe(
        accessToken: token,
        name:   _nameController.text.trim(),
        org:    _orgController.text.trim(),
        radius: _selectedRadius,
        budget: _budgetToInt(_selectedBudget),
        speed:  _selectedSpeed,
      );
    }

    if (!mounted) return;

    if (success) {
      // 저장 성공: 원본값 업데이트 + userProvider 이름/소속 갱신
      final newName = _nameController.text.trim();
      final newOrg  = _orgController.text.trim();

      setState(() {
        _isSaving       = false;
        _isEditing      = false;
        _originalName   = newName;
        _originalOrg    = newOrg;
        _originalRadius = _selectedRadius;
        _originalBudget = _selectedBudget;
        _originalSpeed  = _selectedSpeed;
      });

      // userProvider 갱신: 홈 화면 인사말도 즉시 반영됨
      ref.read(userProvider.notifier).setFromProfile(
        UserProfile(
          id: ref.read(userProvider).userId ?? '',
          name: newName,
          org: newOrg.isNotEmpty ? newOrg : null,
          profileImage: ref.read(userProvider).profileImage,
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('저장되었습니다'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      // 저장 실패
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('저장에 실패했습니다. 다시 시도해주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── 로그아웃 확인 다이얼로그 표시 ───────────────────────
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        title: Text(
          '로그아웃',
          style: AppTextStyles.heading3,
        ),
        content: Text(
          '정말 로그아웃 하시겠어요?',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          // 취소
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              '취소',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          // 로그아웃 확인
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // TODO: API 연동 시 — 카카오 SDK unlink + JWT 삭제 후 콜백 호출
              widget.onLogout?.call();
            },
            child: Text(
              '로그아웃',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── UI 구성 ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,

      // ── 앱바 ─────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: false, // 탭 내부 화면이므로 뒤로가기 없음
        title: Text(
          '내정보',
          style: AppTextStyles.heading3.copyWith(color: AppColors.textPrimary),
        ),
        centerTitle: false,
        actions: [
          // 로딩/저장 중에는 버튼 숨김
          if (!_isLoading && !_isSaving) ...[
            if (_isEditing) ...[
              // 편집 중: 취소 버튼
              TextButton(
                onPressed: _cancelEditing,
                child: Text(
                  '취소',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              // 편집 중: 저장 버튼
              TextButton(
                onPressed: _saveChanges,
                child: Text(
                  '저장',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ] else ...[
              // 기본: 편집 버튼
              TextButton(
                onPressed: _startEditing,
                child: Text(
                  '편집',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),

      // 로딩 중: 중앙에 스피너 표시
      // 로딩 완료: 실제 프로필 데이터로 본문 표시
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          children: [

            // ── 프로필 섹션 ──────────────────────────────
            _buildProfileSection(),

            const SizedBox(height: AppSpacing.md),

            // ── 내 설정 섹션 (반경/예산/속도) ────────────
            _buildPreferencesSection(),

            const SizedBox(height: AppSpacing.md),

            // ── 앱 설정 섹션 ─────────────────────────────
            _buildAppSettingsSection(),

            const SizedBox(height: AppSpacing.lg),

            // ── 로그아웃 버튼 ─────────────────────────────
            if (widget.onLogout != null) _buildLogoutButton(),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  // ── 프로필 섹션 위젯 ──────────────────────────────────────
  // 프로필 사진 + 이름 + 소속
  // 편집 모드에서는 이름/소속을 텍스트 필드로 입력 가능
  Widget _buildProfileSection() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [

          // ── 프로필 사진 ──────────────────────────────
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withAlpha(25),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withAlpha(60),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.person_rounded,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary.withAlpha(120),
                  ),
                ),
              ),
              // 편집 모드일 때만 카메라 배지 표시
              if (_isEditing)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: GestureDetector(
                    // TODO: 구현 필요 — 갤러리/카메라 선택 바텀시트
                    onTap: () {},
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // ── 이름 필드 ───────────────────────────────
          _isEditing
              ? AppTextField(
                  controller: _nameController,
                  label: '이름',
                  hint: '실명을 입력해주세요',
                  textInputAction: TextInputAction.next,
                  maxLength: 20,
                )
              : Text(
                  _nameController.text,
                  style: AppTextStyles.heading2.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),

          if (!_isEditing) const SizedBox(height: 4),

          // ── 소속 필드 ───────────────────────────────
          _isEditing
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: AppTextField(
                    controller: _orgController,
                    label: '소속',
                    hint: '회사 또는 팀 이름을 입력해주세요',
                    textInputAction: TextInputAction.done,
                    maxLength: 30,
                  ),
                )
              : Text(
                  _orgController.text,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
        ],
      ),
    );
  }

  // ── 내 설정 섹션 위젯 ─────────────────────────────────────
  // 반경 / 예산 / 식사 속도 선택
  // 편집 모드에서는 칩을 탭해 변경 가능
  Widget _buildPreferencesSection() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // 섹션 타이틀
          Text(
            '내 설정',
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // ── 반경 설정 행 ───────────────────────────
          _buildPreferenceRow(
            label: '기본 반경',
            options: _radiusOptions,
            selected: _selectedRadius,
            onSelect: (v) => setState(() => _selectedRadius = v),
          ),

          const Divider(height: AppSpacing.lg, color: AppColors.divider),

          // ── 예산 설정 행 ───────────────────────────
          _buildPreferenceRow(
            label: '예산',
            options: _budgetOptions,
            selected: _selectedBudget,
            onSelect: (v) => setState(() => _selectedBudget = v),
          ),

          const Divider(height: AppSpacing.lg, color: AppColors.divider),

          // ── 식사 속도 설정 행 ──────────────────────
          _buildPreferenceRow(
            label: '식사 속도',
            options: _speedOptions,
            selected: _selectedSpeed,
            onSelect: (v) => setState(() => _selectedSpeed = v),
          ),
        ],
      ),
    );
  }

  // ── 설정 항목 행 위젯 ─────────────────────────────────────
  // 레이블 + 칩 목록으로 구성
  // 편집 모드: 칩 탭으로 선택 변경 가능
  // 뷰 모드: 선택된 값만 표시
  Widget _buildPreferenceRow({
    required String label,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 항목 레이블
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),

        const SizedBox(height: AppSpacing.sm),

        // 편집 모드: 모든 칩 표시 (선택 가능)
        // 뷰 모드: 선택된 칩 하나만 표시
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: (_isEditing ? options : [selected]).map((option) {
            // speed 옵션은 API 영문값(FAST/NORMAL/SLOW)을 한국어 레이블로 표시
            final displayLabel = _speedLabel[option] ?? option;
            return AppChip(
              label: displayLabel,
              isSelected: option == selected,
              // 편집 모드일 때만 탭으로 선택 변경 가능
              onTap: _isEditing ? () => onSelect(option) : null,
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── 앱 설정 섹션 위젯 ─────────────────────────────────────
  // 알림 설정, 버전 정보 등
  Widget _buildAppSettingsSection() {
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          // 알림 설정 (준비 중)
          _buildSettingsRow(
            icon: Icons.notifications_outlined,
            label: '알림 설정',
            trailing: Text(
              '준비 중',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            onTap: null, // TODO: 알림 설정 화면 연결
          ),
          const Divider(height: 1, indent: 56, color: AppColors.divider),

          // 앱 버전
          _buildSettingsRow(
            icon: Icons.info_outline_rounded,
            label: '버전 정보',
            trailing: Text(
              'v1.0.0',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            onTap: null,
          ),
        ],
      ),
    );
  }

  // ── 설정 항목 단일 행 위젯 ────────────────────────────────
  // 아이콘 + 레이블 + 우측 내용으로 구성된 범용 행
  Widget _buildSettingsRow({
    required IconData icon,
    required String label,
    required Widget trailing,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            trailing,
            if (onTap != null) ...[
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textSecondary),
            ],
          ],
        ),
      ),
    );
  }

  // ── 로그아웃 버튼 위젯 ────────────────────────────────────
  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
      ),
      child: OutlinedButton(
        onPressed: _showLogoutDialog,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
        ),
        child: Text(
          '로그아웃',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.error,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
