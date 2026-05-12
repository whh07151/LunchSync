// ══════════════════════════════════════════════════════════
// 파일 역할: Firebase Phone Auth 휴대폰 본인확인 화면
//
// 화면 단계 (단일 Scaffold 내 step 전환):
//   1) PHONE  — 전화번호 입력 → signInWithPhoneNumber() → SMS 발송
//                + 웹은 RecaptchaVerifier 자동 표시
//                + 테스트번호(+82 10-1234-5678 / 123456)는 SMS 안 가고
//                  Firebase 콘솔 등록값으로 자동 통과
//   2) OTP    — 6자리 OTP 입력 → confirmationResult.confirm() → idToken 획득
//                → 백엔드 POST /auth/verify-phone 호출
//
// 사용 시점:
//   회원가입 직후 본인확인 (existingUserId 있음, "휴대폰 등록 모드")
//   또는 로그인 화면에서 "전화로 로그인" (existingUserId 없음, "전화 로그인 모드")
//
// 건너뛰기:
//   회원가입 흐름에서 진입 시 "나중에 인증하기" 허용. 사용자 경험 우선.
// ══════════════════════════════════════════════════════════

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../providers/user_provider.dart';
import '../../services/auth_api_service.dart';

class PhoneVerifyScreen extends ConsumerStatefulWidget {
  const PhoneVerifyScreen({
    super.key,
    required this.nextStep,
    required this.onComplete,
    this.existingUserId,
    this.allowSkip = true,
  });

  /// 검증/건너뛰기 후 라우팅할 다음 단계
  final String nextStep;

  /// 화면 종료 콜백 — main.dart 의 _handleLoginSuccess 와 동일 시그니처
  final void Function({required String nextStep}) onComplete;

  /// 현재 로그인된 사용자에 휴대폰을 붙이는 경우 user.id 전달.
  /// 미전달 시: 전화번호로 로그인/가입 흐름으로 진입.
  final String? existingUserId;

  /// 회원가입 흐름에선 true(생략 가능), 단독 로그인 화면에선 false(필수).
  final bool allowSkip;

  @override
  ConsumerState<PhoneVerifyScreen> createState() => _PhoneVerifyScreenState();
}

enum _Step { phone, otp }

class _PhoneVerifyScreenState extends ConsumerState<PhoneVerifyScreen> {
  static const _authApi = AuthApiService();

  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  _Step _step = _Step.phone;
  bool _isSending = false;
  bool _isVerifying = false;

  String? _info;   // 정보성 안내 (SMS 발송됨 등)
  String? _error;  // 에러 메시지 (번호 형식 오류 등)

  /// signInWithPhoneNumber 가 반환한 confirmation 핸들. confirm(code) 로 검증.
  /// Web 전용. 모바일은 verifyPhoneNumber 의 verificationId 를 사용.
  ConfirmationResult? _confirmationResult;

  /// 모바일 verifyPhoneNumber 콜백 경로용 — 인증 ID
  String? _verificationId;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // ── 1단계: 전화번호 → SMS 발송 ─────────────────────────
  Future<void> _sendCode() async {
    if (_isSending) return;

    final raw = _phoneController.text.trim();
    final e164 = _normalizeToE164(raw);
    if (e164 == null) {
      setState(() => _error = '휴대폰 번호 형식이 올바르지 않아요. (예: 010-1234-5678)');
      return;
    }

    setState(() {
      _isSending = true;
      _error = null;
      _info = null;
    });

    try {
      if (kIsWeb) {
        // Web: signInWithPhoneNumber 가 reCAPTCHA 자동 처리 후 ConfirmationResult 반환
        final confirmation =
            await FirebaseAuth.instance.signInWithPhoneNumber(e164);
        if (!mounted) return;
        setState(() {
          _confirmationResult = confirmation;
          _step = _Step.otp;
          _info = '인증 번호를 보냈어요. 6자리 코드를 입력해주세요.';
          _isSending = false;
        });
      } else {
        // Android/iOS: verifyPhoneNumber + 콜백 4종
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: e164,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (PhoneAuthCredential credential) async {
            // Android 자동 검증(SMS 가로채기). 자동으로 OTP 입력 단계 건너뛰고 검증.
            await _signInAndVerifyWithBackend(credential);
          },
          verificationFailed: (FirebaseAuthException e) {
            if (!mounted) return;
            setState(() {
              _isSending = false;
              _error = _humanizeFirebaseError(e);
            });
          },
          codeSent: (String verificationId, int? resendToken) {
            if (!mounted) return;
            setState(() {
              _verificationId = verificationId;
              _step = _Step.otp;
              _info = '인증 번호를 보냈어요. 6자리 코드를 입력해주세요.';
              _isSending = false;
            });
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            _verificationId = verificationId;
          },
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _error = _humanizeFirebaseError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _error = '인증번호 발송 중 오류가 발생했어요. ($e)';
      });
    }
  }

  // ── 2단계: OTP 입력 → confirm → 백엔드 검증 ────────────
  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = '인증 코드 6자리를 입력해주세요.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    try {
      UserCredential? credential;
      if (kIsWeb) {
        if (_confirmationResult == null) {
          throw StateError('confirmationResult 가 없습니다 — 처음부터 다시 시도해주세요.');
        }
        credential = await _confirmationResult!.confirm(code);
      } else {
        if (_verificationId == null) {
          throw StateError('verificationId 가 없습니다 — 처음부터 다시 시도해주세요.');
        }
        final phoneCredential = PhoneAuthProvider.credential(
          verificationId: _verificationId!,
          smsCode: code,
        );
        credential =
            await FirebaseAuth.instance.signInWithCredential(phoneCredential);
      }

      // ID 토큰 추출 → 백엔드로 전달
      final idToken = await credential.user?.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Firebase ID 토큰을 얻지 못했어요.');
      }

      await _callBackendVerify(idToken);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _error = _humanizeFirebaseError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _error = '인증 중 오류가 발생했어요. ($e)';
      });
    }
  }

  // ── Android 자동 검증 콜백 전용 분기 ─────────────────────
  // SMS 자동 가로채기로 PhoneAuthCredential 이 곧바로 전달됐을 때.
  Future<void> _signInAndVerifyWithBackend(
    PhoneAuthCredential credential,
  ) async {
    try {
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final idToken = await userCredential.user?.getIdToken();
      if (idToken == null || idToken.isEmpty) return;
      if (!mounted) return;
      setState(() => _isVerifying = true);
      await _callBackendVerify(idToken);
    } catch (_) {
      // 자동 검증 실패는 사용자가 OTP 수동 입력 흐름을 그대로 사용하도록 무시
    }
  }

  // ── 백엔드 호출: idToken → AuthResponse 처리 ────────────
  Future<void> _callBackendVerify(String idToken) async {
    final result = await _authApi.verifyPhone(
      firebaseIdToken: idToken,
      existingUserId: widget.existingUserId,
    );

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (!result.isSuccess) {
      setState(() => _error = result.errorMessage ?? '서버 검증 실패');
      return;
    }

    // 새 JWT 로 Riverpod 갱신 (전화 로그인일 때는 새 세션, 본인확인일 때는 토큰만 갱신)
    await ref.read(userProvider.notifier).setUser(result.response!);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('휴대폰 인증을 완료했어요.'),
        backgroundColor: AppColors.success,
      ),
    );

    // 백엔드가 nextStep 을 새로 줬으면 그것을 우선 사용 (전화 로그인 시 유용).
    // 회원가입 흐름에선 위젯에 들어온 nextStep 을 그대로 사용.
    final next = widget.existingUserId != null
        ? widget.nextStep
        : result.response!.nextStep;
    widget.onComplete(nextStep: next);
  }

  // ── 사용자 입력을 E.164(+82...) 형식으로 정규화 ────────
  // '010-1234-5678' / '01012345678' / '+821012345678' 모두 허용.
  // 잘못된 입력이면 null 반환.
  String? _normalizeToE164(String raw) {
    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digitsOnly.isEmpty) return null;

    if (digitsOnly.startsWith('+82')) {
      // 이미 E.164 형식
      if (digitsOnly.length < 12) return null;
      return digitsOnly;
    }

    // 010… 으로 시작하는 한국 휴대폰 번호 → +82 + 앞 0 제거
    if (digitsOnly.startsWith('010')) {
      if (digitsOnly.length != 11) return null;
      return '+82${digitsOnly.substring(1)}';
    }

    // 그 외 — 캡스톤 범위에선 국내 010 번호만 지원
    return null;
  }

  String _humanizeFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return '휴대폰 번호 형식이 올바르지 않아요.';
      case 'too-many-requests':
        return '요청이 너무 많아요. 잠시 후 다시 시도해주세요.';
      case 'invalid-verification-code':
      case 'invalid-code':
        return '인증 코드가 올바르지 않아요.';
      case 'session-expired':
      case 'code-expired':
        return '인증 시간이 만료됐어요. 처음부터 다시 시도해주세요.';
      case 'quota-exceeded':
        return '오늘 인증 한도를 초과했어요. 내일 다시 시도해주세요.';
      default:
        return e.message ?? '인증 오류 (${e.code})';
    }
  }

  void _skip() {
    widget.onComplete(nextStep: widget.nextStep);
  }

  // ── UI ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('휴대폰 인증'),
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
              Icon(
                _step == _Step.phone
                    ? Icons.smartphone_rounded
                    : Icons.sms_rounded,
                color: primary,
                size: 64,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _step == _Step.phone
                    ? '휴대폰 번호를 입력해주세요'
                    : '받은 인증 코드를 입력해주세요',
                style: AppTextStyles.heading2.copyWith(
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                _step == _Step.phone
                    ? '본인확인용 SMS 가 전송돼요.\n테스트 번호(010-1234-5678)는 코드 123456으로 통과.'
                    : '메시지가 안 오면 1~2분 후 다시 시도해주세요.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.xl),

              if (_step == _Step.phone)
                _buildPhoneField(primary)
              else
                _buildCodeField(primary),

              if (_info != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _info!,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
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

              // ── 주 액션 버튼 ────────────────────────────
              ElevatedButton(
                onPressed: _step == _Step.phone
                    ? (_isSending ? null : _sendCode)
                    : (_isVerifying ? null : _verifyCode),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
                child: (_isSending || _isVerifying)
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        _step == _Step.phone ? '인증번호 받기' : '확인',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),

              // ── 보조 버튼 ───────────────────────────────
              if (_step == _Step.otp) ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  onPressed: _isSending
                      ? null
                      : () {
                          setState(() {
                            _step = _Step.phone;
                            _codeController.clear();
                            _error = null;
                            _info = null;
                          });
                        },
                  child: const Text('번호 다시 입력하기'),
                ),
              ],

              if (widget.allowSkip) ...[
                const SizedBox(height: AppSpacing.lg),
                TextButton(
                  onPressed: _skip,
                  child: Text(
                    '나중에 인증하기',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneField(Color primary) {
    return TextField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]')),
        LengthLimitingTextInputFormatter(20),
      ],
      style: AppTextStyles.heading2.copyWith(fontWeight: FontWeight.w600),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        hintText: '010-1234-5678',
        hintStyle: AppTextStyles.heading2.copyWith(
          color: AppColors.textSecondary,
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
      onSubmitted: (_) => _sendCode(),
    );
  }

  Widget _buildCodeField(Color primary) {
    return TextField(
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
      onSubmitted: (_) => _verifyCode(),
    );
  }
}
