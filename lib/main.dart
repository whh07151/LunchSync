import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/theme.dart';
import 'core/config/app_config.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/onboarding/profile_setup_screen.dart';
import 'features/onboarding/condition_setup_screen.dart';
import 'features/home/home_screen.dart';
import 'features/payment/payment_success_screen.dart';
import 'features/payment/payment_fail_screen.dart';
import 'features/payment/payment_web_bridge.dart';
import 'providers/user_provider.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 앱의 시작점(Entry Point)
//
// main() 함수:
//   Dart(Flutter)에서 프로그램이 실행될 때 가장 먼저 호출되는 함수입니다.
//   runApp()을 통해 LunchSyncApp 위젯을 화면에 띄웁니다.
//
// 전체 앱 구조:
//   main()
//    └→ ProviderScope (Riverpod 전역 상태 컨테이너)
//         └→ LunchSyncApp (앱 설정: 테마, 라우팅 등)
//              └→ _RootNavigator (첫 화면 결정)
//                   └→ SplashScreen (스플래시)
//                        ├→ 온보딩 화면 (처음 실행 시)
//                        └→ 홈 화면 (재실행 시)
//
// ProviderScope란?
//   Riverpod의 모든 Provider는 ProviderScope 안에서만 동작합니다.
//   앱 전체를 감싸야 어느 화면에서든 ref.read/watch 로 상태에 접근 가능합니다.
// ══════════════════════════════════════════════════════════

/// 앱의 진입점 — 이 함수가 가장 먼저 실행됨
void main() {
  // ── 카카오 SDK 초기화 ──────────────────────────────────────
  // runApp 전에 반드시 호출해야 합니다.
  // nativeAppKey: 카카오 개발자 콘솔에서 발급받은 Native 앱 키
  // 앱 키는 app_config.dart에서 관리 (.gitignore 처리됨)
  KakaoSdk.init(
    nativeAppKey: AppConfig.kakaoNativeAppKey,       // Android/iOS
    javaScriptAppKey: AppConfig.kakaoJavaScriptAppKey, // Web(Chrome)
  );

  // ProviderScope: Riverpod 상태 컨테이너. 앱 전체를 감싸야 함.
  runApp(const ProviderScope(child: LunchSyncApp()));
}


// ─────────────────────────────────────────────────────────
// LunchSyncApp: 앱 전체를 감싸는 최상위 위젯
//
// MaterialApp이란?
//   Flutter에서 Material Design 기반 앱을 만들 때 최상위에 넣는 위젯입니다.
//   테마, 라우팅, 언어 설정 등 앱 전체 설정을 담당합니다.
// ─────────────────────────────────────────────────────────
class LunchSyncApp extends StatelessWidget {
  const LunchSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LunchSync',             // 앱 이름 (기기의 최근 앱 목록 등에 표시됨)
      debugShowCheckedModeBanner: false, // 우측 상단 'debug' 빨간 띠 제거

      // TODO: 상태 관리 결정 후 — AppType을 로그인 상태에 따라 동적으로 전환
      // 현재는 손님앱 테마(주황)로 고정
      theme: AppTheme.of(AppType.customer),

      home: const _RootNavigator(), // 앱이 처음 보여줄 화면
    );
  }
}


// ─────────────────────────────────────────────────────────
// _RootNavigator: 앱의 첫 화면을 결정하고 라우팅을 담당하는 위젯
//
// 역할:
//   앱 실행 시 SharedPreferences의 'onboarding_done' 값을 읽어서
//   첫 실행인지 재실행인지 판단합니다.
//
//   첫 실행 (onboarding_done == false):
//     SplashScreen → LoginScreen → nextStep에 따라 화면 분기
//       "PROFILE_SETUP"   → CU-03 → CU-05 → HomeScreen
//       "CONDITION_SETUP" → CU-05 → HomeScreen (CU-03 완료 후 재진입)
//       "HOME"            → HomeScreen (온보딩 완료)
//
//   재실행 (onboarding_done == true):
//     SplashScreen 건너뜀 → LoginScreen → nextStep에 따라 동일 분기
//     (JWT가 인메모리라 앱 재실행 시 항상 로그인 필요)
//
// StatefulWidget을 쓰는 이유:
//   SharedPreferences 조회가 비동기(async)라 결과가 오기 전까지
//   로딩 상태를 표시해야 합니다. StatelessWidget은 상태 변경 불가.
// ─────────────────────────────────────────────────────────
class _RootNavigator extends ConsumerStatefulWidget {
  const _RootNavigator();

  @override
  ConsumerState<_RootNavigator> createState() => _RootNavigatorState();
}

class _RootNavigatorState extends ConsumerState<_RootNavigator> {

  // null: 아직 확인 중 / true: 온보딩 완료 / false: 첫 실행
  bool? _onboardingDone;

  // ── 결제 왕복 리턴 처리용 플래그 ────────────────────────
  // 토스 결제위젯이 successUrl/failUrl 로 리다이렉트해 돌아오면
  // URL 에 paymentStatus=success|fail 쿼리가 붙어있음.
  // 이 경우 스플래시/로그인 흐름을 건너뛰고 결제 결과 화면으로 바로 진입.
  _PaymentReturnInfo? _paymentReturn;

  @override
  void initState() {
    super.initState();
    _restoreUserFromSession();
    _detectPaymentReturn();
    _checkOnboardingStatus();
  }

  // ── 앱 시작 시 sessionStorage 에서 유저 복원 ──────────────
  // 토스 결제 페이지로 전체 리다이렉트된 뒤 Flutter 앱이 다시
  // 로드되면 Riverpod 의 userProvider 가 초기 상태(null)로 돌아갑니다.
  // OrderReviewScreen 이 결제 직전에 백업해둔 ls_jwt/ls_user_* 가 있으면
  // 그대로 userProvider 에 복원해서 로그인 상태를 이어갑니다.
  //
  // 동작 조건:
  //   - 웹 빌드에서만 실제 값이 들어옴 (모바일 스텁은 항상 null 반환)
  //   - sessionStorage 가 비었으면 no-op
  void _restoreUserFromSession() {
    final savedJwt = PaymentWebBridge.getSessionItem('ls_jwt');
    if (savedJwt == null || savedJwt.isEmpty) return;

    ref.read(userProvider.notifier).restoreFromSession(
          accessToken: savedJwt,
          userId: PaymentWebBridge.getSessionItem('ls_user_id'),
          name: PaymentWebBridge.getSessionItem('ls_user_name'),
          profileImage: PaymentWebBridge.getSessionItem('ls_user_profile'),
        );
  }

  // ── 앱 시작 시 URL 쿼리에서 결제 리턴 여부 감지 ──────────
  // 웹에서만 의미 있음 (모바일 스텁 구현은 빈 맵 반환)
  void _detectPaymentReturn() {
    final params = PaymentWebBridge.currentQueryParams();
    final status = params['paymentStatus'];
    if (status == 'success') {
      final paymentKey = params['paymentKey'] ?? '';
      final orderId = params['orderId'] ?? '';
      final amount = int.tryParse(params['amount'] ?? '0') ?? 0;
      if (paymentKey.isNotEmpty && orderId.isNotEmpty && amount > 0) {
        _paymentReturn = _PaymentReturnInfo.success(
          paymentKey: paymentKey,
          orderId: orderId,
          amount: amount,
        );
      }
    } else if (status == 'fail') {
      _paymentReturn = _PaymentReturnInfo.fail(
        code: params['code'],
        message: params['message'],
        orderId: params['orderId'],
      );
    }
  }

  // ── SharedPreferences에서 온보딩 완료 여부 확인 ──────────
  Future<void> _checkOnboardingStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('onboarding_done') ?? false;
    if (mounted) {
      setState(() => _onboardingDone = done);
    }
  }

  // ── 로그인 성공 후 nextStep에 따라 화면 분기 ───────────────
  // nextStep: 서버가 지정한 다음 화면
  //   "PROFILE_SETUP"   → CU-03 기본 프로필 설정 (신규 유저)
  //   "CONDITION_SETUP" → CU-05 기본 조건 설정 (CU-03 완료 후 재진입한 유저)
  //   "HOME" (그 외)    → 홈 대시보드로 바로 이동 (온보딩 완료 유저)
  //
  // 왜 switch인가?
  //   isNewUser bool 분기와 달리, 서버가 추가 단계를 내려줄 수 있음.
  //   새로운 nextStep 값이 생겨도 case 하나만 추가하면 됨.
  void _handleLoginSuccess(BuildContext ctx, String nextStep) {
    switch (nextStep) {

      // ── CU-03: 기본 프로필 설정 ───────────────────────────
      case 'PROFILE_SETUP':
        Navigator.of(ctx).pushReplacement(
          MaterialPageRoute(
            builder: (ctx2) => ProfileSetupScreen(
              // name/org는 ProfileSetupScreen이 서버에 직접 저장하므로
              // 여기서 받아서 넘길 필요 없음 (VoidCallback)
              onNext: () {
                Navigator.of(ctx2).pushReplacement(
                  MaterialPageRoute(
                    builder: (ctx3) => ConditionSetupScreen(
                      onComplete: () {
                        Navigator.of(ctx3).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const HomeScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        );

      // ── CU-05: 기본 조건 설정 (프로필 완료 후 재진입) ──────
      // CU-03에서 이름/소속이 이미 서버에 저장돼 있으므로
      // profileName/profileOrg props 없이 바로 진입 가능
      case 'CONDITION_SETUP':
        Navigator.of(ctx).pushReplacement(
          MaterialPageRoute(
            builder: (ctx3) => ConditionSetupScreen(
              onComplete: () {
                Navigator.of(ctx3).pushReplacement(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                );
              },
            ),
          ),
        );

      // ── 홈: 온보딩 완료 유저 ─────────────────────────────
      default: // 'HOME' 또는 알 수 없는 값
        Navigator.of(ctx).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {

    // ── 결제 왕복 리턴: 스플래시/로그인 건너뛰고 바로 결과 화면 ──
    // 토스 결제위젯이 돌려보낸 쿼리(paymentStatus=success|fail)를
    // _detectPaymentReturn 에서 파싱했으면 그 화면을 먼저 보여준다.
    if (_paymentReturn != null) {
      final info = _paymentReturn!;
      if (info.isSuccess) {
        return PaymentSuccessScreen(
          paymentKey: info.paymentKey!,
          orderId: info.orderId!,
          amount: info.amount!,
        );
      } else {
        return PaymentFailScreen(
          code: info.code,
          message: info.message,
          orderId: info.orderId,
        );
      }
    }

    // ── SharedPreferences 조회 중: 로딩 표시 ───────────────
    if (_onboardingDone == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // ── 재실행 (온보딩 완료): 스플래시 건너뜀 → 로그인 화면 ─
    if (_onboardingDone!) {
      return LoginScreen(
        onLoginSuccess: ({required String nextStep}) =>
            _handleLoginSuccess(context, nextStep),
      );
    }

    // ── 첫 실행: 스플래시 화면 표시 ─────────────────────────
    return SplashScreen(
      onStart: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (ctx) => LoginScreen(
              onLoginSuccess: ({required String nextStep}) =>
                  _handleLoginSuccess(ctx, nextStep),
            ),
          ),
        );
      },
      onBrowse: () {
        // TODO: 둘러보기 모드 화면 완성 후 교체
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const _PlaceholderScreen(title: '둘러보기 (준비 중)'),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────
// _PaymentReturnInfo: 결제 왕복 후 URL 쿼리에서 복원한 결과 정보
//
// success: paymentKey/orderId/amount 가 모두 존재
// fail   : code/message/orderId 중 일부만 존재해도 허용
// ─────────────────────────────────────────────────────────
class _PaymentReturnInfo {
  const _PaymentReturnInfo._({
    required this.isSuccess,
    this.paymentKey,
    this.orderId,
    this.amount,
    this.code,
    this.message,
  });

  final bool isSuccess;
  final String? paymentKey;
  final String? orderId;
  final int? amount;
  final String? code;
  final String? message;

  factory _PaymentReturnInfo.success({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) =>
      _PaymentReturnInfo._(
        isSuccess: true,
        paymentKey: paymentKey,
        orderId: orderId,
        amount: amount,
      );

  factory _PaymentReturnInfo.fail({
    String? code,
    String? message,
    String? orderId,
  }) =>
      _PaymentReturnInfo._(
        isSuccess: false,
        code: code,
        message: message,
        orderId: orderId,
      );
}


// ─────────────────────────────────────────────────────────
// _PlaceholderScreen: 아직 만들지 않은 화면을 임시로 대체하는 화면
//
// 각 기능 화면이 완성되면 _RootNavigator에서 이 위젯을 해당 화면으로 교체합니다.
// 앱을 실행하고 동작 흐름을 테스트할 때 유용합니다.
// ─────────────────────────────────────────────────────────
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});

  final String title; // 임시 화면에 표시할 이름

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(title, style: AppTextStyles.bodyLarge),
      ),
    );
  }
}
