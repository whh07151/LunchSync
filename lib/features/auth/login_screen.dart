import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/debug/debug_toast.dart';
import '../../services/kakao_auth_service.dart';
import '../../services/auth_api_service.dart';
import '../../providers/user_provider.dart';
import 'phone_verify_screen.dart';
import 'signup_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-02 통합 로그인 화면
//
// 회원가입/인증 결정(2026-05-07) 반영:
//   - 카카오 로그인 버튼 + 이메일/비밀번호 입력 + 회원가입 링크
//   - 손님/사장 구분은 별도 토글이 아니라, "로그인 결과의 role"로 자동 판단
//     (이메일·비밀번호로 로그인하면 서버가 role을 내려주고, Flutter가 그에 맞는
//      홈 화면으로 진입. 사용자는 "내가 사장인지 손님인지"를 다시 고를 필요 없음.)
//
// 동작 흐름:
//   - 카카오 로그인: kakao SDK → /auth/kakao → AuthResponse
//   - 이메일 로그인: /auth/login/email → AuthResponse
//   - 회원가입 버튼: SignupScreen 푸시
//
// 로그인 성공 시 nextStep:
//   PROFILE_SETUP / CONDITION_SETUP / HOME / OWNER_PENDING / OWNER_HOME
//   분기 처리는 main.dart의 _handleLoginSuccess 콜백에서 담당
// ══════════════════════════════════════════════════════════

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    required this.onLoginSuccess,
  });

  /// 로그인 성공 콜백
  /// [nextStep]: 서버가 지정한 다음 화면 (main.dart에서 분기)
  final void Function({required String nextStep}) onLoginSuccess;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {

  // ── 서비스 인스턴스 ──────────────────────────────────────
  static const _kakaoAuthService = KakaoAuthService();
  static const _authApiService = AuthApiService();

  // ── 입력 컨트롤러 ────────────────────────────────────────
  // dispose에서 해제해야 메모리 누수 없음
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // ── 상태 ─────────────────────────────────────────────────
  bool _isKakaoLoading = false; // 카카오 로그인 진행 중
  bool _isEmailLoading = false; // 이메일 로그인 진행 중
  bool _obscurePassword = true; // 비밀번호 숨김 토글

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-02');
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── 카카오 로그인 처리 ──────────────────────────────────
  Future<void> _handleKakaoLogin() async {
    if (_isKakaoLoading || _isEmailLoading) return;
    setState(() => _isKakaoLoading = true);

    final result = await _kakaoAuthService.login();
    if (!mounted) return;

    if (!result.isSuccess) {
      setState(() => _isKakaoLoading = false);
      _showError(result.errorMessage ?? '로그인에 실패했어요.');
      return;
    }

    final authResponse = await _authApiService.loginWithKakao(
      result.kakaoAccessToken!,
    );

    if (!mounted) return;
    setState(() => _isKakaoLoading = false);

    if (authResponse == null) {
      _showError('서버 연결에 실패했어요. 서버가 실행 중인지 확인해주세요.');
      return;
    }

    // Riverpod + SharedPreferences에 저장 → 자동로그인 가능
    await ref.read(userProvider.notifier).setUser(authResponse);
    if (!mounted) return;
    widget.onLoginSuccess(nextStep: authResponse.nextStep);
  }

  // ── 이메일 로그인 처리 ──────────────────────────────────
  Future<void> _handleEmailLogin() async {
    if (_isKakaoLoading || _isEmailLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // ── 클라이언트 측 빠른 검증 (서버 전송 전 빠른 피드백) ──
    if (email.isEmpty || password.isEmpty) {
      _showError('이메일과 비밀번호를 모두 입력해주세요.');
      return;
    }
    if (!email.contains('@')) {
      _showError('이메일 형식이 올바르지 않습니다.');
      return;
    }

    setState(() => _isEmailLoading = true);

    final result = await _authApiService.loginEmail(
      email: email,
      password: password,
    );

    if (!mounted) return;
    setState(() => _isEmailLoading = false);

    if (!result.isSuccess) {
      _showError(result.errorMessage ?? '로그인에 실패했습니다.');
      return;
    }

    await ref.read(userProvider.notifier).setUser(result.response!);
    if (!mounted) return;
    widget.onLoginSuccess(nextStep: result.response!.nextStep);
  }

  // ── 회원가입 화면으로 이동 ──────────────────────────────
  void _goToSignup() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SignupScreen(
          onSignupSuccess: ({required String nextStep}) {
            // 회원가입 성공 → 로그인 화면을 팝하고 main.dart의 라우터에 위임
            widget.onLoginSuccess(nextStep: nextStep);
          },
        ),
      ),
    );
  }

  // ── 휴대폰 인증 로그인 진입 ─────────────────────────────
  // Firebase Phone Auth — 번호 입력 → SMS OTP → 백엔드 /auth/verify-phone
  // 전화번호로 기존 사용자 조회되면 로그인, 없으면 신규 CUSTOMER 가입.
  void _goToPhoneLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhoneVerifyScreen(
          nextStep: 'HOME',          // 백엔드가 응답으로 덮어쓸 기본값
          allowSkip: false,           // 단독 로그인 흐름이므로 건너뛰기 비활성
          onComplete: ({required String nextStep}) {
            widget.onLoginSuccess(nextStep: nextStep);
          },
        ),
      ),
    );
  }

  // ── 에러 스낵바 헬퍼 ────────────────────────────────────
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

  // ── UI ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // 키보드 올라올 때 화면이 자동으로 줄어들어 입력창이 가려지지 않게
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(height: 40),
                _buildLogoSection(),
                _buildLoginFormSection(),
                _buildBottomSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 로고 + 슬로건 ───────────────────────────────────────
  Widget _buildLogoSection() {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: primary.withAlpha(20),
            shape: BoxShape.circle,
            border: Border.all(color: primary.withAlpha(60), width: 2),
          ),
          child: Icon(Icons.lunch_dining_rounded, size: 48, color: primary),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'LunchSync',
          style: AppTextStyles.heading1.copyWith(
            color: primary,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'AI가 추천하는 오늘의 점심',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // ── 이메일+비밀번호 입력 폼 + 로그인 버튼 ───────────────
  Widget _buildLoginFormSection() {
    final isLoading = _isKakaoLoading || _isEmailLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),

        // ── 이메일 입력 ────────────────────────────────────
        TextField(
          controller: _emailController,
          enabled: !isLoading,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '이메일',
            hintText: 'you@example.com',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ),

        const SizedBox(height: AppSpacing.sm),

        // ── 비밀번호 입력 ──────────────────────────────────
        TextField(
          controller: _passwordController,
          enabled: !isLoading,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _handleEmailLogin(),
          decoration: InputDecoration(
            labelText: '비밀번호',
            hintText: '비밀번호 입력',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            // 눈 아이콘 — 비밀번호 보기/숨기기 토글
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
        ),

        const SizedBox(height: AppSpacing.md),

        // ── 로그인 버튼 (이메일) ─────────────────────────
        ElevatedButton(
          onPressed: isLoading ? null : _handleEmailLogin,
          child: _isEmailLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text('로그인'),
        ),

        const SizedBox(height: AppSpacing.sm),

        // ── 회원가입 링크 ───────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '아직 계정이 없으신가요?',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            TextButton(
              onPressed: isLoading ? null : _goToSignup,
              child: const Text('회원가입'),
            ),
          ],
        ),
      ],
    );
  }

  // ── 하단: 구분선 + 카카오 로그인 ────────────────────────
  Widget _buildBottomSection() {
    return Column(
      children: [
        // ── "또는" 구분선 ──────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              const Expanded(child: Divider(color: AppColors.divider)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '또는',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: AppColors.divider)),
            ],
          ),
        ),

        // ── 카카오 로그인 버튼 ─────────────────────────────
        _buildKakaoButton(),
        const SizedBox(height: AppSpacing.sm),

        // ── 휴대폰으로 시작하기 버튼 ─────────────────────
        _buildPhoneButton(),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  Widget _buildPhoneButton() {
    final isLoading = _isKakaoLoading || _isEmailLoading;
    return OutlinedButton.icon(
      onPressed: isLoading ? null : _goToPhoneLogin,
      icon: const Icon(Icons.smartphone_rounded, size: 20),
      label: const Text(
        '휴대폰 번호로 시작하기',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: AppColors.border),
        foregroundColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
    );
  }

  Widget _buildKakaoButton() {
    final isLoading = _isKakaoLoading || _isEmailLoading;
    return GestureDetector(
      onTap: isLoading ? null : _handleKakaoLogin,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          // 카카오 공식 로그인 버튼 색상: #FEE500
          color: isLoading
              ? const Color(0xFFFEE500).withAlpha(160)
              : const Color(0xFFFEE500),
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_rounded,
              size: 22,
              color: Colors.black.withAlpha(210),
            ),
            const SizedBox(width: 8),
            if (_isKakaoLoading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.black.withAlpha(180),
                ),
              )
            else
              Text(
                '카카오로 시작하기',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.black.withAlpha(217),
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
