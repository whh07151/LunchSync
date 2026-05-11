import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../services/users_api_service.dart';
import '../../providers/user_provider.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-03 기본 프로필 설정 화면
//
// 디자인 정돈 (2026-05-11):
//   - 모든 픽셀을 AppSpacing/AppRadius 토큰으로 일관 적용
//   - 마이크로카피 친근체("~해요", "~해주세요" 통일)
//   - 단계 인디케이터: 현재 단계 강조 + 다음 단계 흐림
//
// 와이어프레임:
//   상단 — 온보딩 진행 단계(1/3)
//   본문 — 단계 라벨 + 제목 + 안내 + 프로필 사진 + 이름/소속 + 반경 칩
//   하단 — 고정 "다음" 버튼
//
// 동작:
//   1) "다음" 탭 → PATCH /users/me (name/org/radius) 즉시 저장
//   2) 성공 시 onNext() → CU-05 진입
// ══════════════════════════════════════════════════════════

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({
    super.key,
    required this.onNext,
  });

  final VoidCallback onNext;

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _orgController = TextEditingController();

  String _selectedRadius = '500m';
  static const List<String> _radiusOptions = ['300m', '500m', '1km', '2km'];

  static const _usersApiService = UsersApiService();
  bool _isSaving = false;

  bool get _canProceed =>
      _nameController.text.trim().isNotEmpty &&
      _orgController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    DebugToast.show(context, 'CU-03');
    _nameController.addListener(() => setState(() {}));
    _orgController.addListener(() => setState(() {}));
  }

  Future<void> _handleNext() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final accessToken = ref.read(userProvider).accessToken;

    if (accessToken != null) {
      await _usersApiService.updateMe(
        accessToken: accessToken,
        name: _nameController.text.trim(),
        org: _orgController.text.trim(),
        radius: _selectedRadius,
      );
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    widget.onNext();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _orgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(showBack: true),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    _buildStepIndicator(),
                    const SizedBox(height: AppSpacing.lg),
                    _buildHeader(),
                    const SizedBox(height: AppSpacing.xl),
                    _buildProfilePhoto(context),
                    const SizedBox(height: AppSpacing.xl),
                    AppTextField(
                      controller: _nameController,
                      label: '이름',
                      hint: '실명을 입력해주세요',
                      textInputAction: TextInputAction.next,
                      maxLength: 20,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: _orgController,
                      label: '소속',
                      hint: '회사 또는 팀 이름을 입력해주세요',
                      textInputAction: TextInputAction.done,
                      maxLength: 30,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _buildRadiusSection(),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
            _buildBottomButton(),
          ],
        ),
      ),
    );
  }

  // ── 온보딩 진행 단계 표시 (1/3) ──────────────────────────
  // 현재 단계는 primary, 나머지는 옅은 회색. AnimatedContainer 로 다음 단계 진입 시 부드러운 전환.
  Widget _buildStepIndicator() {
    final primary = Theme.of(context).colorScheme.primary;
    const totalSteps = 3;
    const currentStep = 0;
    return Row(
      children: List.generate(totalSteps, (index) {
        final isActive = index <= currentStep;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: index < totalSteps - 1 ? AppSpacing.xs : 0,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              decoration: BoxDecoration(
                color: isActive ? primary : AppColors.border,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ── 화면 제목 + 안내 문구 ────────────────────────────────
  Widget _buildHeader() {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '1단계 / 3단계',
          style: AppTextStyles.label.copyWith(
            color: primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs + 2),
        Text(
          '기본 프로필을\n설정해주세요',
          style: AppTextStyles.heading1,
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        Text(
          '점심 세션에서 팀원들에게 표시될 이름과\n소속을 입력해주세요',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // ── 프로필 사진 영역 — 원형 + 카메라 배지 ────────────────
  Widget _buildProfilePhoto(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Center(
      child: GestureDetector(
        onTap: () {
          // 추후: 갤러리/카메라 선택 바텀시트
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: primary.withAlpha(25),
                shape: BoxShape.circle,
                border: Border.all(
                  color: primary.withAlpha(60),
                  width: 2,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.person_rounded,
                  size: 44,
                  color: primary.withAlpha(120),
                ),
              ),
            ),
            Positioned(
              right: -AppSpacing.xs / 2,
              bottom: -AppSpacing.xs / 2,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.surface,
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 기본 반경 선택 섹션 ──────────────────────────────────
  Widget _buildRadiusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '기본 반경',
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '점심 식당을 추천할 때 기준이 되는 도보 거리예요',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm + 4),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _radiusOptions.map((radius) {
            return AppChip(
              label: radius,
              isSelected: _selectedRadius == radius,
              onTap: () {
                setState(() => _selectedRadius = radius);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── 하단 고정 버튼 ───────────────────────────────────────
  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.sm + 4,
        AppSpacing.screenHorizontal,
        AppSpacing.xl,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: AppPrimaryButton(
        label: _isSaving ? '저장 중...' : '다음',
        isEnabled: _canProceed && !_isSaving,
        onPressed: (_canProceed && !_isSaving) ? _handleNext : null,
      ),
    );
  }
}
