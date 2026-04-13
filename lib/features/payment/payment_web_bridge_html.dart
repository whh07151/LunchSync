// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

// ══════════════════════════════════════════════════════════
// 파일 역할: 결제 브라우저 연동 — Flutter 웹 실제 구현
//
// 이 파일은 Flutter 웹 빌드에서만 컴파일/실행됩니다.
// (조건부 import 파사드: payment_web_bridge.dart)
//
// 제공 기능:
//   - 현재 URL 쿼리 파라미터 읽기 / 지우기
//   - sessionStorage 에 JWT 등 임시 상태 저장/조회/제거
//   - window.location 을 통한 전체 페이지 리다이렉트
//   - window.location.origin 조회 (성공/실패 URL 조립용)
//
// 사용 시나리오 (결제 왕복):
//   1) 주문 검토 화면(CU-17) → redirect('/toss-checkout.html?...')
//      이때 JWT 를 sessionStorage 에 백업
//   2) 토스 결제위젯에서 결제 완료 → successUrl 로 리다이렉트
//   3) Flutter 앱이 / 에서 재기동 → currentQueryParams() 확인 →
//      JWT 복원 → PaymentSuccessScreen 진입 → confirm API 호출
// ══════════════════════════════════════════════════════════

class PaymentWebBridge {
  const PaymentWebBridge._();

  // ── 현재 URL 의 쿼리 파라미터 가져오기 ─────────────────
  // Flutter 웹은 기본 hash 라우팅을 사용하므로 정규 쿼리스트링은
  // 보통 path 뒤 ("?..." 부분) 에 존재합니다.
  // Uri.base.queryParameters 로 접근합니다.
  static Map<String, String> currentQueryParams() {
    return Uri.base.queryParameters;
  }

  // ── URL 에서 쿼리 파라미터 제거 ────────────────────────
  // 결제 왕복 후 주소창에 paymentKey 같은 민감값이 남지 않도록
  // history.replaceState 로 쿼리 없는 URL 로 재작성합니다.
  static void clearQueryParams() {
    final origin = html.window.location.origin;
    // hash(#/...) 는 그대로 유지
    final hash = html.window.location.hash;
    html.window.history.replaceState(null, '', '$origin/$hash');
  }

  // ── sessionStorage 에 값 저장 ───────────────────────────
  // sessionStorage 는 탭이 닫히면 사라지므로 localStorage 보다 안전
  static void setSessionItem(String key, String value) {
    html.window.sessionStorage[key] = value;
  }

  // ── sessionStorage 에서 값 읽기 ────────────────────────
  static String? getSessionItem(String key) {
    return html.window.sessionStorage[key];
  }

  // ── sessionStorage 에서 값 제거 ────────────────────────
  static void removeSessionItem(String key) {
    html.window.sessionStorage.remove(key);
  }

  // ── 브라우저를 특정 URL 로 리다이렉트 ─────────────────
  // window.location.assign 은 브라우저 history 에 기록을 남김
  // (뒤로가기 하면 Flutter 앱으로 복귀 가능)
  static void redirect(String url) {
    html.window.location.assign(url);
  }

  // ── 현재 origin (예: http://localhost:8080) 반환 ──────
  static String origin() => html.window.location.origin;
}
