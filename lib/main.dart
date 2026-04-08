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
  KakaoSdk.init(nativeAppKey: AppConfig.kakaoNativeAppKey);

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
//     SplashScreen → LoginScreen → 온보딩(CU-03 → CU-05) → HomeScreen
//
//   재실행 (onboarding_done == true):
//     SplashScreen 건너뜀 → LoginScreen → HomeScreen
//     (JWT가 인메모리라 앱 재실행 시 항상 로그인 필요)
//
// StatefulWidget을 쓰는 이유:
//   SharedPreferences 조회가 비동기(async)라 결과가 오기 전까지
//   로딩 상태를 표시해야 합니다. StatelessWidget은 상태 변경 불가.
// ─────────────────────────────────────────────────────────
class _RootNavigator extends StatefulWidget {
  const _RootNavigator();

  @override
  State<_RootNavigator> createState() => _RootNavigatorState();
}

class _RootNavigatorState extends State<_RootNavigator> {

  // null: 아직 확인 중 / true: 온보딩 완료 / false: 첫 실행
  bool? _onboardingDone;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  // ── SharedPreferences에서 온보딩 완료 여부 확인 ──────────
  Future<void> _checkOnboardingStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('onboarding_done') ?? false;
    if (mounted) {
      setState(() => _onboardingDone = done);
    }
  }

  // ── 로그인 성공 후 isNewUser에 따라 화면 분기 ──────────────
  // context와 isNewUser를 받아 적절한 화면으로 이동.
  // 첫 실행(SplashScreen 경유)과 재실행(LoginScreen 직접) 모두 동일 로직 사용.
  void _handleLoginSuccess(BuildContext ctx, bool isNewUser) {
    if (isNewUser) {
      // 신규 유저: 프로필 설정 → 조건 설정 → 홈
      Navigator.of(ctx).pushReplacement(
        MaterialPageRoute(
          builder: (ctx2) => ProfileSetupScreen(
            onNext: ({required String name, required String org}) {
              Navigator.of(ctx2).pushReplacement(
                MaterialPageRoute(
                  builder: (ctx3) => ConditionSetupScreen(
                    profileName: name,
                    profileOrg: org,
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
    } else {
      // 기존 유저: 홈으로 바로 이동
      Navigator.of(ctx).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {

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
        onLoginSuccess: ({required bool isNewUser}) =>
            _handleLoginSuccess(context, isNewUser),
      );
    }

    // ── 첫 실행: 스플래시 화면 표시 ─────────────────────────
    return SplashScreen(
      onStart: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (ctx) => LoginScreen(
              onLoginSuccess: ({required bool isNewUser}) =>
                  _handleLoginSuccess(ctx, isNewUser),
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
