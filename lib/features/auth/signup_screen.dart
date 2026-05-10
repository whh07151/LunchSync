import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../services/auth_api_service.dart';
import '../../providers/user_provider.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 이메일+비밀번호 회원가입 화면
//
// 회원가입/인증 결정(2026-05-07) 반영:
//   - 역할 선택(CUSTOMER / OWNER) 라디오 추가
//   - OWNER 선택 시 가게 상호명 / 사업자등록번호 입력 필드 노출
//   - 이메일 OTP·휴대폰 인증은 추후 단계에서 추가 (현재는 즉시 가입 완료)
//
// 가입 성공 시 nextStep:
//   CUSTOMER → PROFILE_SETUP (이어서 CU-03 온보딩)
//   OWNER    → OWNER_PENDING (운영자 승인 대기 안내)
//
// 입력 검증 (클라이언트):
//   - 이메일 @ 포함
//   - 비밀번호 8자 이상
//   - 비밀번호 확인 일치
//   - 이름 비어있지 않음
//   - OWNER 선택 시 상호명/사업자번호 비어있지 않음
//
// 본 검증은 빠른 피드백용. 서버에서도 동일하게 다시 검증함.
// ══════════════════════════════════════════════════════════

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({
    super.key,
    required this.onSignupSuccess,
  });

  /// 가입 성공 후 다음 화면으로 이동시킬 콜백
  final void Function({required String nextStep}) onSignupSuccess;

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  static const _authApiService = AuthApiService();

  // ── 입력 컨트롤러 ────────────────────────────────────
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _nameController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _businessNumberController = TextEditingController();

  // ── 상태 ───────────────────────────────────────────
  String _role = 'CUSTOMER'; // 라디오 기본값: 손님
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _nameController.dispose();
    _businessNameController.dispose();
    _businessNumberController.dispose();
    super.dispose();
  }

  // ── 가입 처리 ───────────────────────────────────────
  Future<void> _handleSignup() async {
    if (_isLoading) return;

    // ── 입력값 정리 ──
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final passwordConfirm = _passwordConfirmController.text;
    final name = _nameController.text.trim();
    final businessName = _businessNameController.text.trim();
    final businessNumber = _businessNumberController.text.trim();

    // ── 클라이언트 검증 ──
    if (email.isEmpty || !email.contains('@')) {
      return _showError('이메일 형식이 올바르지 않습니다.');
    }
    if (password.length < 8) {
      return _showError('비밀번호는 8자 이상이어야 합니다.');
    }
    if (password != passwordConfirm) {
      return _showError('비밀번호 확인이 일치하지 않습니다.');
    }
    if (name.isEmpty) {
      return _showError('이름을 입력해주세요.');
    }
    if (_role == 'OWNER') {
      if (businessName.isEmpty || businessNumber.isEmpty) {
        return _showError('사장 가입 시 상호명과 사업자등록번호를 입력해주세요.');
      }
    }

    // ── 서버 호출 ──
    setState(() => _isLoading = true);
    final result = await _authApiService.signupEmail(
      email: email,
      password: password,
      name: name,
      role: _role,
      businessName: _role == 'OWNER' ? businessName : null,
      businessNumber: _role == 'OWNER' ? businessNumber : null,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!result.isSuccess) {
      _showError(result.errorMessage ?? '회원가입에 실패했습니다.');
      return;
    }

    // ── 성공: Riverpod 저장 후 nextStep으로 이동 ──
    await ref.read(userProvider.notifier).setUser(result.response!);
    if (!mounted) return;
    widget.onSignupSuccess(nextStep: result.response!.nextStep);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
        ),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('회원가입')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.md,
            AppSpacing.screenHorizontal,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionLabel('로그인 정보'),
              const SizedBox(height: AppSpacing.sm),
              _buildEmailField(),
              const SizedBox(height: AppSpacing.sm),
              _buildPasswordField(),
              const SizedBox(height: AppSpacing.sm),
              _buildPasswordConfirmField(),

              const SizedBox(height: AppSpacing.lg),

              _buildSectionLabel('기본 정보'),
              const SizedBox(height: AppSpacing.sm),
              _buildNameField(),

              const SizedBox(height: AppSpacing.lg),

              _buildSectionLabel('가입 유형'),
              const SizedBox(height: AppSpacing.xs),
              _buildRoleSelector(),

              // OWNER 선택 시에만 가게 정보 노출
              if (_role == 'OWNER') ...[
                const SizedBox(height: AppSpacing.md),
                _buildSectionLabel('가게 정보 (사장님 가입)'),
                const SizedBox(height: AppSpacing.sm),
                _buildBusinessFields(),
                const SizedBox(height: AppSpacing.sm),
                _buildOwnerNotice(),
              ],

              const SizedBox(height: AppSpacing.xl),

              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: AppTextStyles.label.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildEmailField() {
    return TextField(
      controller: _emailController,
      enabled: !_isLoading,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      decoration: const InputDecoration(
        labelText: '이메일',
        hintText: 'you@example.com',
        prefixIcon: Icon(Icons.alternate_email_rounded),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      enabled: !_isLoading,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: '비밀번호 (8자 이상)',
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
          ),
          onPressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
    );
  }

  Widget _buildPasswordConfirmField() {
    return TextField(
      controller: _passwordConfirmController,
      enabled: !_isLoading,
      obscureText: _obscurePasswordConfirm,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: '비밀번호 확인',
        prefixIcon: const Icon(Icons.lock_reset_rounded),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePasswordConfirm
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
          ),
          onPressed: () => setState(
              () => _obscurePasswordConfirm = !_obscurePasswordConfirm),
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _nameController,
      enabled: !_isLoading,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: '이름',
        hintText: '예: 홍길동',
        prefixIcon: Icon(Icons.person_outline_rounded),
      ),
    );
  }

  // ── 손님/사장 라디오 선택기 ────────────────────────
  Widget _buildRoleSelector() {
    return Column(
      children: [
        _buildRoleOption(
          value: 'CUSTOMER',
          title: '손님으로 가입',
          subtitle: '점심 약속을 만들고, 식당 추천·투표·주문을 이용해요.',
          icon: Icons.fastfood_rounded,
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildRoleOption(
          value: 'OWNER',
          title: '사장님으로 가입',
          subtitle: '내 가게의 주문을 받고 POS와 연동해요. 운영자 승인 후 활성화.',
          icon: Icons.storefront_rounded,
        ),
      ],
    );
  }

  Widget _buildRoleOption({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _role == value;
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: _isLoading ? null : () => setState(() => _role = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected ? primary.withAlpha(15) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: isSelected ? primary : AppColors.border,
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? primary : AppColors.iconInactive),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? primary : AppColors.textPrimary,
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
            // 선택 표시 라디오 점
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? primary : AppColors.border,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration:
                            BoxDecoration(color: primary, shape: BoxShape.circle),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessFields() {
    return Column(
      children: [
        TextField(
          controller: _businessNameController,
          enabled: !_isLoading,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '가게 상호명',
            hintText: '예: 김밥천국 한국대점',
            prefixIcon: Icon(Icons.store_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _businessNumberController,
          enabled: !_isLoading,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '사업자등록번호',
            hintText: '예: 123-45-67890',
            prefixIcon: Icon(Icons.receipt_long_rounded),
          ),
        ),
      ],
    );
  }

  Widget _buildOwnerNotice() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(20),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.warning.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '사장님 가입은 운영자 승인이 필요해요. 가입 직후엔 사장 화면에 접근할 수 없고,\n승인이 완료되면 다음 로그인부터 사장 화면이 열립니다.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _handleSignup,
      child: _isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : const Text('가입하기'),
    );
  }
}
