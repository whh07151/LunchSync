// ══════════════════════════════════════════════════════════
// 파일 역할: 결제 브라우저 연동 — 모바일/기본 스텁 구현
//
// 이 파일은 Flutter 모바일(Android/iOS) 빌드에서 선택됩니다.
// 현재 LunchSync 결제 흐름은 Flutter 웹 기준으로만 구현되어 있어
// 모바일에서는 아무것도 하지 않거나 에러를 던집니다.
//
// 웹 구현체: payment_web_bridge_html.dart
// 조건부 import 파사드: payment_web_bridge.dart
// ══════════════════════════════════════════════════════════

class PaymentWebBridge {
  const PaymentWebBridge._();

  // ── 현재 URL 의 쿼리 파라미터 가져오기 ─────────────────
  // 모바일은 URL 이 없으므로 항상 빈 맵 반환
  static Map<String, String> currentQueryParams() => const {};

  // ── 현재 URL 에서 쿼리 파라미터 제거 ────────────────────
  // 웹에서는 history.replaceState 로 주소창에서 결제 쿼리를 지움
  static void clearQueryParams() {}

  // ── sessionStorage 에 값 저장 ───────────────────────────
  // 결제 리다이렉트 전후로 JWT 를 보관할 때 사용
  static void setSessionItem(String key, String value) {}

  // ── sessionStorage 에서 값 읽기 ────────────────────────
  static String? getSessionItem(String key) => null;

  // ── sessionStorage 에서 값 제거 ────────────────────────
  static void removeSessionItem(String key) {}

  // ── 브라우저를 특정 URL 로 리다이렉트 ─────────────────
  // 모바일에서는 지원하지 않음
  static void redirect(String url) {
    throw UnsupportedError(
      '결제 리다이렉트는 Flutter 웹 빌드에서만 지원됩니다. '
      '(web/toss-checkout.html 경로 사용)',
    );
  }

  // ── 현재 origin (예: http://localhost:8080) 반환 ──────
  static String origin() => 'http://localhost:8080';
}
