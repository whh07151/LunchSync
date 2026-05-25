11// ══════════════════════════════════════════════════════════
// 파일 역할: app_config.dart 템플릿 (팀원 셋업용)
//
// 사용 방법:
//   1. 이 파일을 복사해서 같은 폴더에 app_config.dart로 저장
//   2. 카카오 개발자 콘솔(developers.kakao.com)에서
//      내 애플리케이션 → 앱 키 → Native 앱 키 값을 입력
// ══════════════════════════════════════════════════════════

class AppConfig {
  AppConfig._();

  /// 카카오 Native 앱 키 — 카카오 개발자 콘솔에서 확인 후 입력
  static const String kakaoNativeAppKey = 'f';

  /// 카카오 JavaScript 앱 키 (Web)
  static const String kakaoJavaScriptAppKey = '<your-kakao-js-key>';

  /// 백엔드 기본 URL
  static const String backendBaseUrl = 'http://localhost:3000/api';

  /// 토스페이먼츠 테스트 클라이언트 키 (test_ck_...)
  /// https://developers.tosspayments.com/ → API 키 → 테스트 → 클라이언트 키
  static const String tossClientKey = '<your-toss-test-client-key>';

  static const String tossSuccessUrl = 'http://localhost:8080/payment/success';
  static const String tossFailUrl = 'http://localhost:8080/payment/fail';
}