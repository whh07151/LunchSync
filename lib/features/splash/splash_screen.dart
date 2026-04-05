import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/theme.dart';
import '../../core/debug/debug_toast.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-01 스플래시/서비스 소개 화면
//
// 와이어프레임 기준 구성 요소:
//   - 배경: 흰색/베이지 (주황 아님)
//   - 중앙 상단: 주황색 원형 로고
//   - 로고 아래: 앱 이름 + 서비스 소개 텍스트
//   - 하단: 권한 안내 문구
//   - 하단 버튼 2개: "카카오로 시작하기" (주요) + "서비스 둘러보기" (보조)
//
// 동작 흐름:
//   앱 실행 → 이 화면 표시
//   → "카카오로 시작하기" 탭: 로그인 화면으로 이동
//   → "서비스 둘러보기" 탭: 온보딩 없이 둘러보기 모드로 이동
//   → 첫 실행 여부는 SharedPreferences(내장 저장소)에 저장
//
// [수정 예정] 정확한 수치/문구가 확정되면 아래 주석의
//   "TODO: 수치 확정 시 수정" 부분을 업데이트해야 합니다.
//
// 상태 관리 라이브러리 무관:
//   어떤 상태 관리 라이브러리를 선택해도 이 파일은 수정 불필요.
//   main.dart의 콜백 함수만 교체하면 됩니다.
// ══════════════════════════════════════════════════════════

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.onStart,    // "카카오로 시작하기" 버튼 → 로그인 화면으로
    required this.onBrowse,   // "서비스 둘러보기" 버튼 → 둘러보기 모드로
  });

  /// "카카오로 시작하기" 버튼을 눌렀을 때 실행되는 함수
  /// → 카카오 로그인 화면 또는 온보딩으로 이동
  final VoidCallback onStart;

  /// "서비스 둘러보기" 버튼을 눌렀을 때 실행되는 함수
  /// → 로그인 없이 앱을 먼저 둘러볼 수 있는 화면으로 이동
  final VoidCallback onBrowse;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {

  // AnimationController: 애니메이션 재생을 제어하는 리모컨
  late AnimationController _animController;

  // _fadeAnim: 화면 전체가 서서히 나타나는 투명도 애니메이션 (0→1)
  late Animation<double> _fadeAnim;

  // _slideAnim: 콘텐츠가 살짝 아래에서 위로 올라오는 위치 애니메이션
  late Animation<Offset> _slideAnim;

  // SharedPreferences에 저장/불러올 때 사용하는 키 이름
  // markOnboardingDone() 함수와 반드시 동일한 문자열을 사용해야 함
  // ignore: unused_field — 추후 재실행 판단 로직 추가 시 사용 예정
  static const String _onboardingDoneKey = 'onboarding_done';

  // ── 생명주기: 화면이 처음 만들어질 때 ──────────────────
  @override
  void initState() {
    super.initState();
    DebugToast.show(context, 'CU-01');
    _setupAnimation();
  }

  // ── 애니메이션 설정 ─────────────────────────────────────
  void _setupAnimation() {
    _animController = AnimationController(
      vsync: this,
      // TODO: 수치 확정 시 수정 — 애니메이션 재생 시간 (현재 700ms = 0.7초 추정)
      duration: const Duration(milliseconds: 700),
    );

    // 투명도: 0(완전 투명)에서 1(완전 불투명)으로
    // easeOut: 빠르게 시작해서 천천히 끝남
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    // 위치: 살짝 아래(y=0.04 = 4%)에서 시작해서 제자리(y=0)로 올라옴
    // TODO: 수치 확정 시 수정 — 슬라이드 거리 (현재 4% 추정)
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    // 애니메이션 재생 시작
    _animController.forward();
  }

  // ── 생명주기: 화면이 사라질 때 ─────────────────────────
  @override
  void dispose() {
    _animController.dispose(); // 애니메이션 리소스 해제 (메모리 누수 방지)
    super.dispose();
  }

  // ── UI 구성 ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // 화면 전체 크기를 가져옴 (반응형 레이아웃을 위해)
    final screenHeight = MediaQuery.of(context).size.height;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      // TODO: 수치 확정 시 수정 — 배경색
      // 와이어프레임: 흰색/베이지 계열. 현재 순수 흰색(0xFFFFFFFF)으로 설정.
      // 베이지에 가깝다면 예) Color(0xFFFFF8F4) 로 변경
      backgroundColor: AppColors.background,

      body: FadeTransition(
        opacity: _fadeAnim, // 화면 전체 페이드인 효과

        child: SlideTransition(
          position: _slideAnim, // 살짝 위로 올라오는 효과

          child: SafeArea(
            // SafeArea: 노치(카메라 홈), 상태바, 하단 홈바 영역을 피해서 배치
            child: Padding(
              // TODO: 수치 확정 시 수정 — 화면 좌우 여백 (현재 24px 추정)
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [

                  // ── 상단 여백 ─────────────────────────────
                  // TODO: 수치 확정 시 수정 — 상단 여백 비율 (현재 화면 높이의 15% 추정)
                  SizedBox(height: screenHeight * 0.15),

                  // ── 로고 영역 ─────────────────────────────
                  _buildLogo(primary),

                  // TODO: 수치 확정 시 수정 — 로고와 텍스트 사이 간격 (현재 32px 추정)
                  const SizedBox(height: 32),

                  // ── 앱 이름 + 서비스 소개 텍스트 ──────────
                  _buildIntroText(),

                  // 남은 공간을 최대한 차지해서 버튼을 아래로 밀어냄
                  const Spacer(),

                  // ── 권한 안내 문구 ────────────────────────
                  _buildPermissionNotice(),

                  // TODO: 수치 확정 시 수정 — 권한 안내와 버튼 사이 간격 (현재 16px 추정)
                  const SizedBox(height: 16),

                  // ── 하단 버튼 영역 ────────────────────────
                  _buildButtons(primary),

                  // TODO: 수치 확정 시 수정 — 하단 여백 (현재 32px 추정)
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 로고 위젯 ─────────────────────────────────────────────
  Widget _buildLogo(Color primary) {
    return Column(
      children: [
        Container(
          // TODO: 수치 확정 시 수정 — 로고 원의 크기 (현재 100x100px 추정)
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: primary, // 주황색 원형 배경
            shape: BoxShape.circle, // 완전한 원 모양
            // TODO: 수치 확정 시 수정 — 그림자 여부 및 수치 (현재 없음으로 설정)
            // 그림자가 있다면 아래 boxShadow 주석을 해제하고 수치 조정
            // boxShadow: [
            //   BoxShadow(
            //     color: primary.withAlpha(60),
            //     blurRadius: 20,
            //     offset: const Offset(0, 8),
            //   ),
            // ],
          ),
          child: Center(
            // TODO: 수정 필요 — 실제 LunchSync 로고 이미지로 교체해야 함
            // 로고 이미지 파일(예: assets/images/logo.png)이 준비되면
            // 아래 Icon을 Image.asset('assets/images/logo.png')으로 교체
            child: Icon(
              Icons.lunch_dining_rounded, // 임시 아이콘
              size: 52,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // ── 앱 이름 + 서비스 소개 텍스트 위젯 ────────────────────
  Widget _buildIntroText() {
    return Column(
      children: [
        // 앱 이름
        // TODO: 수치 확정 시 수정 — 앱 이름 글자 크기 (현재 30px 추정)
        Text(
          'LunchSync AI',
          style: AppTextStyles.heading1.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            // TODO: 수치 확정 시 수정 — 글자 간격 (현재 -0.5 추정)
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),

        // TODO: 수치 확정 시 수정 — 앱 이름과 소개 문구 사이 간격 (현재 12px 추정)
        const SizedBox(height: 12),

        // 서비스 소개 문구
        // TODO: 수정 필요 — 실제 서비스 소개 문구로 교체 (현재 임시 문구)
        Text(
          'AI가 추천하는 우리 팀 점심,\n함께 고르고 함께 즐기세요',
          style: AppTextStyles.bodyLarge.copyWith(
            color: AppColors.textSecondary,
            // TODO: 수치 확정 시 수정 — 줄 간격 (현재 1.6 추정)
            height: 1.6,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── 권한 안내 문구 위젯 ────────────────────────────────────
  Widget _buildPermissionNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(
        // TODO: 수치 확정 시 수정 — 권한 안내 박스 안쪽 여백 (현재 12x16px 추정)
        vertical: 12,
        horizontal: 16,
      ),
      decoration: BoxDecoration(
        // TODO: 수치 확정 시 수정 — 권한 안내 박스 배경색 (현재 아주 연한 회색 추정)
        color: AppColors.backgroundGrey,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 권한 안내 제목
          Text(
            '서비스 이용을 위해 아래 권한이 필요합니다',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),

          // TODO: 수정 필요 — 실제 필요한 권한 항목으로 교체
          // (위치, 알림, 카메라 등 실제 사용할 권한만 표시)
          _buildPermissionItem('위치', '주변 식당 추천에 사용됩니다'),
          _buildPermissionItem('알림', '세션 초대 및 주문 현황 알림에 사용됩니다'),
        ],
      ),
    );
  }

  // 권한 항목 한 줄 (아이콘 + 설명)
  Widget _buildPermissionItem(String name, String description) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 점(•) 구분자
          Text('• ', style: AppTextStyles.caption.copyWith(
            color: AppColors.textHint,
          )),
          Expanded(
            child: Text(
              // TODO: 수정 필요 — 실제 권한명과 설명 문구
              '$name: $description',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textHint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 하단 버튼 2개 위젯 ────────────────────────────────────
  Widget _buildButtons(Color primary) {
    return Column(
      children: [
        // ── 주요 버튼: 카카오로 시작하기 ──────────────────
        // TODO: 수치 확정 시 수정 — 카카오 버튼 색상
        // 카카오 공식 색상: 배경 #FEE500 (노란색), 텍스트 #3C1E1E (거의 검정)
        // 현재는 임시로 primary(주황) 사용. 카카오 로고 추가 필요.
        SizedBox(
          width: double.infinity,
          height: 52, // TODO: 수치 확정 시 수정 — 버튼 높이 (현재 52px 추정)
          child: ElevatedButton.icon(
            onPressed: widget.onStart,
            style: ElevatedButton.styleFrom(
              // TODO: 수정 필요 — 카카오 공식 색상 #FEE500으로 교체
              backgroundColor: const Color(0xFFFEE500),
              foregroundColor: const Color(0xFF3C1E1E),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
            // TODO: 수정 필요 — 카카오 로고 이미지로 교체
            // Image.asset('assets/images/kakao_logo.png', width: 20)
            icon: const Icon(Icons.chat_bubble_rounded, size: 20),
            label: Text(
              '카카오로 시작하기',
              style: AppTextStyles.buttonLarge.copyWith(
                color: const Color(0xFF3C1E1E),
              ),
            ),
          ),
        ),

        // TODO: 수치 확정 시 수정 — 두 버튼 사이 간격 (현재 12px 추정)
        const SizedBox(height: 12),

        // ── 보조 버튼: 서비스 둘러보기 ───────────────────
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: widget.onBrowse,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
            child: Text(
              '서비스 둘러보기',
              style: AppTextStyles.buttonLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}


// ══════════════════════════════════════════════════════════
// markOnboardingDone(): 온보딩 완료를 내장 저장소에 저장하는 함수
//
// 호출 위치: 온보딩 마지막 화면의 "완료" 버튼을 눌렀을 때
// 효과: 다음 앱 실행 시 스플래시가 온보딩을 건너뛰고 홈으로 바로 이동
// ══════════════════════════════════════════════════════════
Future<void> markOnboardingDone() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('onboarding_done', true);
}
