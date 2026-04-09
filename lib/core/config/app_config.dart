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

  /// 카카오 Native 앱 키 (Android/iOS)
  /// https://developers.kakao.com → 내 애플리케이션 → 앱 키 → Native 앱 키
  static const String kakaoNativeAppKey = '1a8f618f7a89644f824c091c4c9c085a';

  /// 카카오 JavaScript 앱 키 (Web/Chrome)
  /// https://developers.kakao.com → 내 애플리케이션 → 앱 키 → JavaScript 앱 키
  static const String kakaoJavaScriptAppKey = '4873cbbe1f8110a38bb487677405a6ac';

  /// LunchSync 백엔드 서버 기본 URL
  ///
  /// 실기기 테스트 시: PC의 로컬 IP 주소로 변경 (예: http://192.168.0.5:3000/api)
  /// 에뮬레이터 테스트 시: http://10.0.2.2:3000/api (Android 에뮬레이터 → 호스트 PC)
  /// TODO: 배포 시 실제 서버 도메인으로 교체
  static const String backendBaseUrl = 'http://192.168.45.15:3000/api';
}