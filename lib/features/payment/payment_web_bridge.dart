// ══════════════════════════════════════════════════════════
// 파일 역할: 결제 흐름에서 필요한 브라우저 연동 (Facade)
//
// 왜 분리하나?
//   결제 흐름은 토스 결제위젯 HTML(web/toss-checkout.html) 로
//   브라우저 전체 페이지를 리다이렉트하고 되돌아와야 합니다.
//   이를 위해 dart:html 의 window.location / sessionStorage 가
//   필요한데, dart:html 은 Flutter 웹 전용입니다.
//
//   모바일 빌드가 깨지지 않도록 조건부 import 패턴을 사용합니다:
//     - payment_web_bridge_stub.dart : 모바일/기본 (no-op, 에러)
//     - payment_web_bridge_html.dart : 웹 전용 (dart:html 실사용)
//
// 사용처:
//   features/payment/order_review_screen.dart → redirectToCheckout
//   features/payment/payment_success_screen.dart → read/clear session data
//   main.dart → 앱 시작 시 URL 쿼리 파라미터 확인
// ══════════════════════════════════════════════════════════

export 'payment_web_bridge_stub.dart'
    if (dart.library.html) 'payment_web_bridge_html.dart';
