import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/theme.dart';
import '../../core/debug/debug_toast.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-01 스플래시/서비스 소개 화면
//
// 디자인 컨셉 (2026-05-11 일관 정돈):
//   - 배경: primarySurface(주황 옅음) — 따뜻하고 친근한 첫인상
//   - 로고: primary 원형 + 살짝 그림자 + 아이콘
//   - 슬로건: 2줄, 부드러운 톤
//   - 권한 안내: 흰 카드 + 아이콘 + 짧은 설명
//   - CTA: 로그인 화면 진입 (카카오/이메일/휴대폰 선택)
//
// 일관성 규칙:
//   - 모든 픽셀은 AppSpacing/AppRadius 토큰만 사용
//   - 글씨체는 AppTextStyles (Noto Sans 기반)만 사용
//   - 색상은 AppColors / Theme.colorScheme 만 사용
//
// 동작 흐름:
//   onStart  → 로그인 화면 (카카오/이메일/휴대폰 선택)
// ══════════════════════════════════════════════════════════

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // 페이드 + 슬라이드 등장 애니메이션 — 700ms easeOut 으로 자연스럽게 진입
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    DebugToast.show(context, 'CU-01');
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: CustomerColors.primarySurface,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
              ),
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.xxl),
                  _buildLogo(primary),
                  const SizedBox(height: AppSpacing.xl),
                  _buildIntroText(),
                  const Spacer(),
                  _buildPermissionNotice(),
                  const SizedBox(height: AppSpacing.md),
                  _buildButtons(),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 로고 — primary 원형 + 살짝 그림자 ────────────────────
  Widget _buildLogo(Color primary) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: primary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: primary.withAlpha(60),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: const Center(
        child: Icon(Icons.lunch_dining_rounded, size: 48, color: Colors.white),
      ),
    );
  }

  // ── 앱 이름 + 슬로건 ──────────────────────────────────────
  Widget _buildIntroText() {
    return Column(
      children: [
        Text(
          'LunchSync',
          style: AppTextStyles.heading1.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'AI가 추천하는 우리 팀 점심,\n함께 고르고 함께 즐기세요',
          style: AppTextStyles.bodyLarge.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── 권한 안내 카드 — 흰 카드 + 아이콘 + 짧은 설명 ──────────
  Widget _buildPermissionNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '서비스 이용을 위해 다음 권한이 필요해요',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildPermissionItem(
            icon: Icons.location_on_outlined,
            label: '위치',
            description: '주변 식당 추천에 사용',
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          _buildPermissionItem(
            icon: Icons.notifications_none_rounded,
            label: '알림',
            description: '세션 초대·주문 현황 알림',
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required String label,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.xs + 2),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            description,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  // ── 하단 CTA — 실제 지원하는 로그인 화면으로 이동 ────
  Widget _buildButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: widget.onStart,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
            icon: const Icon(Icons.login_rounded, size: 20),
            label: Text(
              '로그인·회원가입',
              style: AppTextStyles.buttonLarge.copyWith(
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════
// markOnboardingDone(): 온보딩 완료 플래그를 영구 저장
//   호출 위치: 온보딩 마지막 화면의 "완료" 버튼
//   효과: 다음 앱 실행 시 스플래시 건너뛰고 자동 로그인 분기로
// ══════════════════════════════════════════════════════════
Future<void> markOnboardingDone() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('onboarding_done', true);
}
