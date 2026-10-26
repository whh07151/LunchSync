import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../providers/user_provider.dart';
import '../../services/email_otp_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 이메일 OTP 인증 화면
//
// 사용 시점:
//   회원가입 직후 (signup_screen → 가입 성공 → 본 화면 진입)
//   - 진입 시 자동으로 sendOtp(email) 호출 → Supabase Auth 가 메일 발송
//   - 사용자가 메일에서 받은 6자리 코드 입력 → verifyOtp 호출
//   - 검증 성공 시 백엔드가 users.email_verified_at 갱신 후 일반 JWT 발급
//   - 일반 JWT를 저장한 뒤 main.dart 라우터가 다음 화면 결정
//
// 재발송:
//   - "다시 보내기" 버튼은 30초 쿨다운 후 활성화 (Supabase rate-limit 보호)
// ══════════════════════════════════════════════════════════

class EmailOtpScreen extends ConsumerStatefulWidget {
  const EmailOtpScreen({
    super.key,
    required this.email,
    required this.verificationToken,
    required this.onComplete,
    this.otpService = const EmailOtpApiService(),
  });

  /// 인증할 이메일 (가입 시 입력한 값)
  final String email;

  /// 비밀번호 확인 또는 가입 직후 받은 10분짜리 이메일 검증 전용 JWT.
  /// 일반 API 토큰으로 저장하지 않고 이 화면의 OTP 요청에만 사용한다.
  final String verificationToken;

  /// 기본은 실제 API 서비스이며, 위젯 테스트에서는 결정적 fake를 주입한다.
  final EmailOtpApiService otpService;

  /// 화면 종료 콜백 — main.dart 의 _handleLoginSuccess 와 동일 시그니처
  final void Function({required String nextStep}) onComplete;

  @override
  ConsumerState<EmailOtpScreen> createState() => _EmailOtpScreenState();
}

class _EmailOtpScreenState extends ConsumerState<EmailOtpScreen> {
  final _codeController = TextEditingController();
  bool _isVerifying = false;
  bool _isResending = false;

  /// 다시 보내기 쿨다운 — 30초 카운트다운
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  String? _info; // 정보성 메시지 (메일 발송됨 등)
  String? _error; // 에러 메시지 (코드 불일치 등)

  @override
  void initState() {
    super.initState();
    // 진입 직후 즉시 OTP 발송 — 사용자가 메일을 일찍 확인할 수 있도록
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendOtp());
  }

  @override
  void dispose() {
    _codeController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  /// OTP 발송 (초기 1회 + 다시 보내기 버튼)
  Future<void> _sendOtp() async {
    if (_isResending) return;
    setState(() {
      _isResending = true;
      _error = null;
    });

    final result = await widget.otpService.sendOtp(
      widget.email,
      widget.verificationToken,
    );

    if (!mounted) return;
    setState(() {
      _isResending = false;
      if (result.success) {
        _info = result.message ?? '인증 메일을 보냈어요.';
        _startCooldown(30);
      } else {
        _error = result.message ?? '메일 발송에 실패했어요.';
      }
    });
  }

  void _startCooldown(int seconds) {
    setState(() => _resendCooldown = seconds);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> _verifyOtp() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = '인증 코드 6자리를 입력해주세요.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    final result = await widget.otpService.verifyOtp(
      widget.email,
      code,
      widget.verificationToken,
    );

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (result.success) {
      final authResponse = result.authResponse;
      if (authResponse == null) {
        setState(() => _error = '인증은 처리됐지만 로그인 정보를 확인하지 못했어요. 다시 로그인해주세요.');
        return;
      }

      await ref.read(userProvider.notifier).setUser(authResponse);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? '이메일 인증 완료'),
          backgroundColor: AppColors.success,
        ),
      );
      widget.onComplete(nextStep: authResponse.nextStep);
    } else {
      setState(() => _error = result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('이메일 인증'),
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.lg),
              Icon(Icons.mark_email_read_rounded, color: primary, size: 64),
              const SizedBox(height: AppSpacing.md),
              Text(
                '인증 메일을 확인해주세요',
                style: AppTextStyles.heading2.copyWith(
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                widget.email,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: primary,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                '받으신 6자리 코드를 입력해주세요.\n메일이 안 보이면 스팸함도 확인해주세요.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── OTP 입력 필드 ───────────────────────────
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: AppTextStyles.heading2.copyWith(
                  letterSpacing: 12,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '000000',
                  hintStyle: AppTextStyles.heading2.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 12,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.input),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.input),
                    borderSide: BorderSide(color: primary, width: 2),
                  ),
                ),
                onSubmitted: (_) => _verifyOtp(),
              ),

              if (_info != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _info!,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: AppSpacing.lg),

              // ── 검증 버튼 ───────────────────────────────
              ElevatedButton(
                onPressed: _isVerifying ? null : _verifyOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
                child: _isVerifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        '인증하기',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),

              const SizedBox(height: AppSpacing.sm),

              // ── 다시 보내기 (쿨다운) ────────────────────
              OutlinedButton(
                onPressed: (_isResending || _resendCooldown > 0)
                    ? null
                    : _sendOtp,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                ),
                child: Text(
                  _resendCooldown > 0
                      ? '다시 보내기 ($_resendCooldown초)'
                      : (_isResending ? '발송 중...' : '인증 메일 다시 보내기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
