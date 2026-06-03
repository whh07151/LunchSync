// ══════════════════════════════════════════════════════════
// 파일 역할: 앱 민감 설정값 보관
//
// ⚠️ 주의: 이 파일은 .gitignore에 등록되어 있습니다.
//    GitHub 등 공개 저장소에 절대 올리지 마세요.
//    팀원에게는 카카오 개발자 콘솔에서 직접 앱 키를 확인하도록 안내하세요.
//
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
  /// 🟢 현재 기본값: AWS EC2 배포 서버 (http://13.125.165.80:3000/api)
  ///
  /// 로컬 개발 시 dart-define 으로 오버라이드:
  ///   에뮬레이터: --dart-define=BACKEND_HOST=10.0.2.2
  ///   실기기:     --dart-define=BACKEND_HOST=(PC의 로컬 IP)
  ///   완전 URL:   --dart-define=BACKEND_URL=http://localhost:3000/api

  // ── 백엔드 URL 빌드 환경별 분기 ──────────────────────────
  //
  // 우선순위: BACKEND_URL > BACKEND_HOST > 기본값(EC2)
  //
  //   1) BACKEND_URL=<full url>      — 완전 URL 직접 지정 (HTTPS도 OK)
  //      예) --dart-define=BACKEND_URL=http://localhost:3000/api
  //   2) BACKEND_HOST=<IP or domain> — 호스트만 지정 (포트 3000, HTTP 자동)
  //      예) --dart-define=BACKEND_HOST=10.0.2.2
  //   3) 둘 다 미지정                — EC2 기본값 사용

  static const String _backendUrlOverride = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: '',
  );

  static const String _backendHost = String.fromEnvironment(
    'BACKEND_HOST',
    defaultValue: '',
  );

  // 우선순위: BACKEND_URL > BACKEND_HOST(http:3000) > DuckDNS 도메인(HTTPS, 기본)
  //   2026-06-03: 기본값을 직접 IP(13.125.165.80) → DuckDNS 도메인으로 변경.
  //   EC2 퍼블릭 IP가 바뀌어도(Stop/Start 등) 도메인은 그대로라 앱 재설정 불필요.
  static const String backendBaseUrl = _backendUrlOverride.length > 0
      ? _backendUrlOverride
      : (_backendHost.length > 0
          ? 'http://$_backendHost:3000/api'
          : 'https://lunchsync-api.duckdns.org/api');

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

  // ── 결제 콜백 URL — 빌드 환경별 dart-define 우선 ────────
  //
  // 운영(HTTPS) 빌드 시:
  //   --dart-define=TOSS_SUCCESS_URL=https://<도메인>/payment/success
  //   --dart-define=TOSS_FAIL_URL=https://<도메인>/payment/fail
  //
  // 미지정 시 로컬 개발 기본값 사용.
  static const String _tossSuccessOverride = String.fromEnvironment(
    'TOSS_SUCCESS_URL',
    defaultValue: '',
  );
  static const String _tossFailOverride = String.fromEnvironment(
    'TOSS_FAIL_URL',
    defaultValue: '',
  );

  /// 결제 성공 시 리다이렉트될 경로 (Flutter 웹 라우트)
  /// 토스 결제창에서 승인 완료 후 이 URL로 paymentKey, orderId, amount가 쿼리스트링으로 전달됨
  static const String tossSuccessUrl = _tossSuccessOverride.length > 0
      ? _tossSuccessOverride
      : 'http://localhost:8080/payment/success';

  /// 결제 실패 시 리다이렉트될 경로
  static const String tossFailUrl = _tossFailOverride.length > 0
      ? _tossFailOverride
      : 'http://localhost:8080/payment/fail';

  // ══════════════════════════════════════════════════════════
  // 네트워크 안정성 (프론트 에이전트 권장 — 2026-05-11)
  // ══════════════════════════════════════════════════════════

  /// 모든 HTTP 호출 기본 타임아웃 — 느린 네트워크에서 무한 로딩 방지
  static const Duration apiTimeout = Duration(seconds: 10);

  /// 401 응답 시 자동 로그아웃 처리 활성화 여부
  static const bool autoLogoutOn401 = true;
}
