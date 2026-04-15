// ══════════════════════════════════════════════════════════
// 파일 역할: 앱 민감 설정값 보관
//
// ⚠️ 주의: 이 파일은 .gitignore에 등록되어 있습니다.
//    GitHub 등 공개 저장소에 절대 올리지 마세요.
//    팀원에게는 카카오 개발자 콘솔에서 직접 앱 키를 확인하도록 안내하세요.
//
// 팀원 셋업 방법:
//   1. lib/core/config/app_config.example.dart 파일을 복사
//   2. 이름을 app_config.dart로 변경
//   3. 카카오 개발자 콘솔에서 Native 앱 키를 입력
// ══════════════════════════════════════════════════════════

class AppConfig {
  AppConfig._(); // 인스턴스 생성 방지 (모든 값을 static으로만 사용)

  // ignore: do_not_use_environment
  static const bool _isWeb = bool.fromEnvironment('dart.library.html', defaultValue: false);

  /// 카카오 Native 앱 키 (Android/iOS)
  /// https://developers.kakao.com → 내 애플리케이션 → 앱 키 → Native 앱 키
  static const String kakaoNativeAppKey = '1a8f618f7a89644f824c091c4c9c085a';

  /// 카카오 JavaScript 앱 키 (Web/Chrome)
  /// https://developers.kakao.com → 내 애플리케이션 → 앱 키 → JavaScript 앱 키
  static const String kakaoJavaScriptAppKey =
      '4873cbbe1f8110a38bb487677405a6ac';

  /// LunchSync 백엔드 서버 기본 URL
  ///
  /// 실기기 테스트 시: PC의 로컬 IP 주소로 변경 (예: http://192.168.0.5:3000/api)
  /// 에뮬레이터 테스트 시: http://10.0.2.2:3000/api (Android 에뮬레이터 → 호스트 PC)
  ///
  /// 🟢 현재: 로컬 개발 서버 (결제/주문 모듈 AWS 미배포 상태라 localhost 사용)
  /// 🔴 AWS 배포본: http://13.125.165.80:3000/api
  ///    → AWS 재배포 완료 후 위 주소로 복귀

  // 빌드 시 --dart-define=BACKEND_HOST=<IP> 로 주입
  // 예) flutter run --dart-define=BACKEND_HOST=192.168.45.105
  // BACKEND_HOST 미입력 시 기본값: 192.168.45.105
  static const String _backendHost = String.fromEnvironment(
    'BACKEND_HOST',
    defaultValue: '0.0.0.0',
  );

  // 플랫폼에 따라 자동 분기 (web: localhost, iOS/Android: 로컬 IP)
  static const String backendBaseUrl = _isWeb
      ? 'http://localhost:3000/api'           // AndroidStudio Chrome(web)
      : 'http://$_backendHost:3000/api';      // iOS / Android 실기기

  // ══════════════════════════════════════════════════════════
  // 토스페이먼츠 (결제위젯 v2)
  // ══════════════════════════════════════════════════════════
  // 개발자센터: https://developers.tosspayments.com/
  //
  // ⚠️ 클라이언트 키만 여기에 둡니다.
  //    시크릿 키(test_sk_...)는 절대 프론트에 넣지 않습니다.
  //    시크릿 키는 backend/.env → TOSS_SECRET_KEY 로만 관리합니다.
  //
  // 💡 테스트 키(test_ck_...)로도 모든 결제수단 UI가 실제와 동일하게 동작하며,
  //    실결제는 발생하지 않습니다. 라이브 전환 시 live_ck_... 로만 교체.
  // ══════════════════════════════════════════════════════════

  /// 토스페이먼츠 테스트 클라이언트 키
  /// https://developers.tosspayments.com/ → API 키 → 테스트 → 클라이언트 키
  static const String tossClientKey = 'test_gck_docs_Ovk5rk1EwkEbP0W43n07xlzm';

  /// 결제 성공 시 리다이렉트될 경로 (Flutter 웹 라우트)
  /// 토스 결제창에서 승인 완료 후 이 URL로 paymentKey, orderId, amount가 쿼리스트링으로 전달됨
  static const String tossSuccessUrl = 'http://localhost:8080/payment/success';

  /// 결제 실패 시 리다이렉트될 경로
  static const String tossFailUrl = 'http://localhost:8080/payment/fail';
}
