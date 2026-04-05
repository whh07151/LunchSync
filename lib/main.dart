import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
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
//   SplashScreen에 콜백 함수를 넘겨줍니다.
//   SplashScreen이 판단을 마치면 여기서 정의한 함수가 실행되어
//   적절한 화면으로 이동합니다.
//
// 왜 콜백(callback) 방식을 쓰나?
//   SplashScreen이 "어디로 갈지"를 직접 알 필요가 없게 합니다.
//   나중에 상태 관리 라이브러리로 라우팅 방식이 바뀌어도
//   SplashScreen 코드는 수정 없이 이 파일만 바꾸면 됩니다.
// ─────────────────────────────────────────────────────────
class _RootNavigator extends StatelessWidget {
  const _RootNavigator();

  @override
  Widget build(BuildContext context) {
    return SplashScreen(
      // "카카오로 시작하기" 버튼: CU-02 로그인 화면으로 이동
      onStart: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (ctx) => LoginScreen(
              onLoginSuccess: ({required bool isNewUser}) {
                if (isNewUser) {
                  // ── 신규 유저: CU-03 프로필 설정으로 이동 ──────
                  Navigator.of(ctx).pushReplacement(
                    MaterialPageRoute(
                      builder: (ctx2) => ProfileSetupScreen(
                        onNext: () {
                          Navigator.of(ctx2).pushReplacement(
                            MaterialPageRoute(
                              builder: (ctx3) => ConditionSetupScreen(
                                onComplete: () {
                                  Navigator.of(ctx3).pushReplacement(
                                    MaterialPageRoute(
                                      // CU-06 홈 대시보드로 이동 (온보딩 완료)
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
                  // ── 기존 유저: 홈으로 바로 이동 ───────────────
                  // TODO: 안태환 씨 API 완성 후 활성화
                  // 현재는 isNewUser가 항상 true이므로 이 분기는 미도달
                  Navigator.of(ctx).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const HomeScreen(),
                    ),
                  );
                }
              },
            ),
          ),
        );
      },

      // "서비스 둘러보기" 버튼: 로그인 없이 둘러보기
      onBrowse: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            // TODO: 둘러보기 모드 화면 완성 후 교체
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
