import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/theme.dart';
import 'core/config/app_config.dart';
import 'core/api/api_auth_hooks.dart';
import 'firebase_options.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/owner_pending_screen.dart';
import 'features/onboarding/profile_setup_screen.dart';
import 'features/onboarding/condition_setup_screen.dart';
import 'features/home/home_screen.dart';
import 'features/owner/owner_home_screen.dart';
import 'features/payment/payment_success_screen.dart';
import 'features/payment/payment_fail_screen.dart';
import 'features/payment/payment_web_bridge.dart';
import 'providers/user_provider.dart';
import 'services/users_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 앱의 시작점 + 전역 라우팅
//
// 회원가입/인증 결정(2026-05-07) 반영:
//   1. 자동 로그인 — SharedPreferences에 저장된 JWT가 있으면
//      GET /users/me 검증 후 role/status에 맞는 홈으로 자동 진입
//   2. 동적 테마 — userProvider의 role에 따라 손님(주황)/사장(청록) 테마 자동 전환
//   3. nextStep 분기 확장 — OWNER_PENDING / OWNER_HOME 추가
//
// 부팅 시 화면 결정 우선순위:
//   1. 결제 왕복 리턴 URL → 결제 결과 화면
//   2. 자동 로그인 가능 → 손님/사장 홈
//   3. 자동 로그인 실패 + 온보딩 미완료 → 스플래시
//   4. 자동 로그인 실패 + 온보딩 완료 → 로그인 화면
// ══════════════════════════════════════════════════════════

Future<void> main() async {
  // Flutter 바인딩이 Firebase 초기화 전에 준비되도록 보장
  WidgetsFlutterBinding.ensureInitialized();

  // ── 카카오 SDK 초기화 ────────────────────────────────
  KakaoSdk.init(
    nativeAppKey: AppConfig.kakaoNativeAppKey,
    javaScriptAppKey: AppConfig.kakaoJavaScriptAppKey,
  );

  // ── Firebase 초기화 ────────────────────────────────
  // 휴대폰 인증(Phone Auth) 진입 전 반드시 1회 실행. 실패해도 앱은 동작하도록
  // try/catch — iOS 미설정 환경 등에서 무리하게 죽지 않게.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // 로그만 남기고 진행 — 휴대폰 인증 화면 진입 시 다시 에러 처리
    debugPrint('Firebase 초기화 실패: $e');
  }

  runApp(const ProviderScope(child: LunchSyncApp()));
}


// ─────────────────────────────────────────────────────────
// LunchSyncApp: 앱 전체를 감싸는 최상위 위젯
//
// ConsumerWidget으로 변경한 이유:
//   userProvider의 role 값에 따라 테마(주황/청록)를 동적으로 전환하기 위해
//   build에서 ref.watch(userProvider) 필요.
// ─────────────────────────────────────────────────────────
class LunchSyncApp extends ConsumerWidget {
  const LunchSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // user role에 따라 손님/사장 테마 결정
    // 로그인 전엔 손님 테마(주황)가 기본
    final user = ref.watch(userProvider);
    final appType = user.role == 'OWNER' ? AppType.owner : AppType.customer;

    return MaterialApp(
      title: 'LunchSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.of(appType),
      home: const _RootNavigator(),
    );
  }
}


// ─────────────────────────────────────────────────────────
// _RootNavigator: 첫 화면 결정 + 라우팅
// ─────────────────────────────────────────────────────────
class _RootNavigator extends ConsumerStatefulWidget {
  const _RootNavigator();

  @override
  ConsumerState<_RootNavigator> createState() => _RootNavigatorState();
}

class _RootNavigatorState extends ConsumerState<_RootNavigator> {

  // ── 부팅 단계별 상태 ─────────────────────────────────
  // null  : 확인 중 (로딩 표시)
  // false : 첫 실행 (스플래시 보여줘야 함)
  // true  : 재실행 (스플래시 건너뜀)
  bool? _onboardingDone;

  // ── 자동 로그인 결과 ─────────────────────────────────
  // null  : 자동 로그인 안 시도했거나 실패 → 로그인 화면
  // 'HOME'         : 손님 홈으로
  // 'OWNER_HOME'   : 사장 홈으로
  // 'OWNER_PENDING': 사장 승인 대기 안내로
  String? _autoLoginNextStep;

  // ── 결제 왕복 리턴 ─────────────────────────────────
  _PaymentReturnInfo? _paymentReturn;

  @override
  void initState() {
    super.initState();
    // 401 자동 로그아웃 글로벌 콜백 등록 — 토큰 만료 시 userProvider 자동 클리어.
    // _RootNavigator 상태에 있을 때는 setState 로 build() 재호출 → LoginScreen 으로
    // 자연 전환. 다른 화면(HomeScreen 등) 에 있으면 토큰만 클리어되고, 사용자가
    // 앱 재시작 또는 다음 진입 시 LoginScreen 으로 빠짐.
    ApiAuthHooks.onUnauthorized = () async {
      debugPrint('[ApiAuthHooks] 401 감지 → userProvider clear');
      await ref.read(userProvider.notifier).clear();
      if (mounted) {
        setState(() {
          _autoLoginNextStep = null;
        });
      }
    };
    _detectPaymentReturn();
    _bootSequence();
  }

  // ── 부팅 시퀀스 ──────────────────────────────────────
  // 결제 리턴이 아니면 자동 로그인 시도 → 온보딩 상태 확인 순서
  Future<void> _bootSequence() async {
    // 결제 리턴 처리 중엔 자동 로그인 건너뜀 (sessionStorage 복원이 우선)
    if (_paymentReturn != null) {
      _restoreUserFromSession();
      await _checkOnboardingStatus();
      return;
    }

    // 1) 영속 토큰 복원 시도
    final restored =
        await ref.read(userProvider.notifier).restoreFromStorage();

    // 2) 토큰이 있으면 서버에 검증 요청 → role/status 최신화
    if (restored) {
      final token = ref.read(userProvider).accessToken!;
      final profile = await const UsersApiService().getMe(token);

      if (profile != null) {
        // 토큰 유효 → state에 최신 정보 반영 (restaurantId prefs 동기화 위해 await)
        await ref.read(userProvider.notifier).setFromProfile(profile);
        _autoLoginNextStep = _resolveAutoLoginNextStep(profile);
      } else {
        // 토큰 만료/무효 → 정리 후 로그인 화면으로
        await ref.read(userProvider.notifier).clear();
      }
    }

    await _checkOnboardingStatus();
  }

  // ── 자동 로그인 후 어느 화면으로 갈지 결정 ──────────────
  String _resolveAutoLoginNextStep(UserProfile profile) {
    final role = profile.role ?? 'CUSTOMER';
    final status = profile.status ?? 'APPROVED';

    if (role == 'OWNER') {
      if (status != 'APPROVED') return 'OWNER_PENDING';
      return 'OWNER_HOME';
    }
    // CUSTOMER: 온보딩 진행 상태에 따라
    if (profile.org == null || (profile.org?.isEmpty ?? true)) {
      return 'PROFILE_SETUP';
    }
    if (profile.budget == null || profile.speed == null) {
      return 'CONDITION_SETUP';
    }
    return 'HOME';
  }

  // ── sessionStorage(웹) 에서 결제 직전 백업 복원 ─────────
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

  Future<void> _checkOnboardingStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('onboarding_done') ?? false;
    if (mounted) setState(() => _onboardingDone = done);
  }

  // ══════════════════════════════════════════════════════
  // nextStep 분기 라우팅
  // 로그인/회원가입 성공 콜백, 자동 로그인 결과 둘 다 이 메서드로 통일.
  // ══════════════════════════════════════════════════════
  void _handleLoginSuccess(BuildContext ctx, String nextStep) {
    switch (nextStep) {
      // ── OWNER 분기 ──
      case 'OWNER_PENDING':
        Navigator.of(ctx).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OwnerPendingScreen()),
          (route) => false,
        );

      case 'OWNER_HOME':
        Navigator.of(ctx).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OwnerHomeScreen()),
          (route) => false,
        );

      // ── CUSTOMER: CU-03 프로필 설정 ──
      case 'PROFILE_SETUP':
        Navigator.of(ctx).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (ctx2) => ProfileSetupScreen(
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
          (route) => false,
        );

      // ── CUSTOMER: CU-05 조건 설정 (CU-03 완료 후 재진입) ──
      case 'CONDITION_SETUP':
        Navigator.of(ctx).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (ctx3) => ConditionSetupScreen(
              onComplete: () {
                Navigator.of(ctx3).pushReplacement(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                );
              },
            ),
          ),
          (route) => false,
        );

      // ── CUSTOMER 홈 (기본/HOME) ──
      default:
        Navigator.of(ctx).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {

    // ── 1. 결제 리턴 우선 ────────────────────────────
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

    // ── 2. 부팅 중 (로딩 인디케이터) ────────────────────
    if (_onboardingDone == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // ── 3. 자동 로그인 성공 → 해당 화면으로 ───────────────
    // 온보딩 미완료 사용자도 적절한 단계로 정확히 진입하도록 분기.
    if (_autoLoginNextStep != null) {
      switch (_autoLoginNextStep) {
        case 'OWNER_PENDING':
          return const OwnerPendingScreen();
        case 'OWNER_HOME':
          return const OwnerHomeScreen();
        case 'PROFILE_SETUP':
          // CU-03 → 끝나면 CU-05 → HomeScreen 순으로 자동 연결
          return ProfileSetupScreen(
            onNext: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (ctx) => ConditionSetupScreen(
                    onComplete: () {
                      Navigator.of(ctx).pushReplacement(
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                      );
                    },
                  ),
                ),
              );
            },
          );
        case 'CONDITION_SETUP':
          // CU-03 는 이미 끝났고 CU-05 만 남은 케이스
          return ConditionSetupScreen(
            onComplete: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            },
          );
        case 'HOME':
          return const HomeScreen();
        default:
          return const HomeScreen();
      }
    }

    // ── 4. 재실행(온보딩 완료) → 로그인 화면 ─────────────
    if (_onboardingDone!) {
      return LoginScreen(
        onLoginSuccess: ({required String nextStep}) =>
            _handleLoginSuccess(context, nextStep),
      );
    }

    // ── 5. 첫 실행 → 스플래시 → 로그인 ───────────────────
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
// _PaymentReturnInfo / _PlaceholderScreen — 기존 그대로
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


class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});

  final String title;

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
