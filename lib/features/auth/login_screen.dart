import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/debug/debug_toast.dart';
import '../../services/kakao_auth_service.dart';
import '../../services/auth_api_service.dart';
import '../../providers/user_provider.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-02 카카오 로그인 화면
//
// 와이어프레임 기준 구성 요소:
//   - 앱 로고 + 서비스명
//   - 슬로건 문구
//   - 카카오 로그인 버튼 (카카오 공식 색상 #FEE500)
//
// 동작 흐름:
//   스플래시(CU-01) → 이 화면(CU-02)
//     → 로그인 성공 + 신규 유저 → CU-03 프로필 설정
//     → 로그인 성공 + 기존 유저 → CU-06 홈 대시보드
//
// 신규/기존 유저 분기:
//   현재: 항상 CU-03으로 이동 (백엔드 미연동 상태)
//   TODO: 안태환 씨 POST /auth/kakao API 완성 후
//         응답의 isNewUser 필드로 분기 처리
//
// KakaoAuthService 사용 이유:
//   카카오 SDK 코드를 UI에서 분리해 테스트 및 교체가 용이하도록 함
// ══════════════════════════════════════════════════════════

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    required this.onLoginSuccess, // 로그인 성공 시 실행 (신규/기존 유저 구분 포함)
  });

  /// 로그인 성공 콜백
  /// [isNewUser]: true면 CU-03으로, false면 홈으로 이동
  /// TODO: 현재는 항상 isNewUser=true로 호출 (백엔드 미연동)
  final void Function({required bool isNewUser}) onLoginSuccess;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {

  // ── 서비스 인스턴스 ──────────────────────────────────────
  static const _kakaoAuthService = KakaoAuthService();
  static const _authApiService = AuthApiService();

  // ── 로그인 진행 중 여부 ───────────────────────────────────
  // true: 버튼 비활성화 + 로딩 인디케이터 표시
  bool _isLoading = false;

  // ── 생명주기: 화면 초기화 ───────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-02');
    });
  }

  // ── 카카오 로그인 버튼 탭 핸들러 ───────────────────────────
  Future<void> _handleKakaoLogin() async {
    // 이미 로그인 진행 중이면 중복 호출 방지
    if (_isLoading) return;

    setState(() => _isLoading = true);

    // 카카오 로그인 시도
    final result = await _kakaoAuthService.login();

    // 화면이 이미 사라졌으면 setState 호출 금지 (메모리 오류 방지)
    if (!mounted) return;

    if (result.isSuccess) {
      // ── 카카오 토큰 → LunchSync 서버에 전달 ───────────────
      // POST /auth/kakao: 서버에서 유저 조회/생성 후 JWT + isNewUser 반환
      final authResponse = await _authApiService.loginWithKakao(
        result.kakaoAccessToken!,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (authResponse != null) {
        // ── 서버 응답 성공: 유저 정보 Riverpod에 저장 ────────
        ref.read(userProvider.notifier).setUser(authResponse);
        widget.onLoginSuccess(isNewUser: authResponse.isNewUser);
      } else {
        // ── 서버 통신 실패 ─────────────────────────────────
        // 카카오 인증은 됐지만 서버가 응답하지 않는 경우
        // (서버 미실행, 네트워크 오류 등)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '서버 연결에 실패했어요. 서버가 실행 중인지 확인해주세요.',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      setState(() => _isLoading = false);
      // ── 카카오 로그인 실패: 오류 메시지 스낵바 표시 ───────
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errorMessage ?? '로그인에 실패했어요.',
            style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ── UI 구성 ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          child: Column(
            children: [

              // ── 상단 로고 영역 (화면 중앙보다 약간 위) ────────
              const Spacer(flex: 3),

              _buildLogoSection(),

              const Spacer(flex: 4),

              // ── 하단 로그인 버튼 영역 ──────────────────────
              _buildLoginButton(),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  // ── 로고 + 슬로건 영역 위젯 ─────────────────────────────────
  Widget _buildLogoSection() {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [

        // ── 앱 아이콘 (원형 배경 + 음식 아이콘) ──────────────
        // TODO: 실제 앱 로고 이미지 완성 후 Image.asset으로 교체
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: primary.withAlpha(20),
            shape: BoxShape.circle,
            border: Border.all(color: primary.withAlpha(60), width: 2),
          ),
          child: Icon(
            Icons.lunch_dining_rounded,
            size: 52,
            color: primary,
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // ── 앱 이름 ────────────────────────────────────────
        Text(
          'LunchSync',
          style: AppTextStyles.heading1.copyWith(
            color: primary,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),

        const SizedBox(height: AppSpacing.sm),

        // ── 슬로건 ──────────────────────────────────────────
        // TODO: 수정 필요 — 실제 슬로건 문구 확정 시 교체
        Text(
          'AI가 추천하는 오늘의 점심',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // ── 카카오 로그인 버튼 위젯 ─────────────────────────────────
  Widget _buildLoginButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _handleKakaoLogin,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          // 카카오 공식 로그인 버튼 색상: #FEE500
          color: _isLoading
              ? const Color(0xFFFEE500).withAlpha(160) // 로딩 중: 흐리게
              : const Color(0xFFFEE500),
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            // ── 카카오 로고 아이콘 ────────────────────────────
            // TODO: 정식 카카오 로고 이미지(assets)로 교체 권장
            // 현재: 말풍선 아이콘으로 임시 대체
            Icon(
              Icons.chat_bubble_rounded,
              size: 22,
              color: Colors.black.withAlpha(210), // 카카오 공식 텍스트 색상
            ),

            const SizedBox(width: 8),

            // ── 버튼 텍스트 또는 로딩 인디케이터 ──────────────
            if (_isLoading)
              // 로그인 진행 중: 작은 로딩 원형 표시
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
                  // 카카오 공식 텍스트 색상: rgba(0,0,0,0.85)
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
