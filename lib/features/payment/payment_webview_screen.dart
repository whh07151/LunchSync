import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../core/theme/theme.dart';
import 'payment_success_screen.dart';
import 'payment_fail_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 모바일 전용 Toss 결제 WebView 화면
//
// 웹 빌드에서는 사용되지 않음 (웹은 브라우저 리다이렉트 방식)
// Android/iOS 에서 toss-checkout.html 을 인앱 WebView 로 로드
//
// 흐름:
//   OrderReviewScreen → 이 화면 (checkoutUrl 전달)
//   → WebView 에서 toss-checkout.html 로드
//   → 결제 완료 시 successUrl 로 이동 시도
//   → NavigationDelegate 에서 가로채서 PaymentSuccessScreen 으로 전환
//   → 결제 실패/취소 시 failUrl 가로채서 PaymentFailScreen 으로 전환
// ══════════════════════════════════════════════════════════

class PaymentWebViewScreen extends StatefulWidget {
  const PaymentWebViewScreen({
    super.key,
    required this.checkoutUrl,
    required this.successUrlPrefix,
    required this.failUrlPrefix,
  });

  /// toss-checkout.html 의 전체 URL (쿼리 파라미터 포함)
  final String checkoutUrl;

  /// 결제 성공 시 리다이렉트되는 URL 의 prefix (가로채기용)
  final String successUrlPrefix;

  /// 결제 실패 시 리다이렉트되는 URL 의 prefix (가로채기용)
  final String failUrlPrefix;

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return; // 웹에서는 사용하지 않음

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // 2026-05-30: 토스 결제위젯이 일부 분기에서 모바일 UA 검사 후 위젯을
      // 그리지 않는 케이스가 있어 공기계에서 빈 화면이 노출됨. 표준 안드로이드
      // Chrome UA 를 명시해 위젯 분기를 안정화.
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Pixel 9) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Mobile Safari/537.36 LunchSync/1.0',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: (request) {
            final url = request.url;

            // 결제 성공 URL 가로채기
            if (url.startsWith(widget.successUrlPrefix)) {
              _handleSuccess(url);
              return NavigationDecision.prevent;
            }

            // 결제 실패 URL 가로채기
            if (url.startsWith(widget.failUrlPrefix)) {
              _handleFail(url);
              return NavigationDecision.prevent;
            }

            // intent:// 또는 비표준 스킴 — 시스템(Android)으로 위임
            // 토스, 카카오페이 등 앱 딥링크가 이 경로로 들어옴
            final scheme = Uri.tryParse(url)?.scheme ?? '';
            if (scheme != 'http' && scheme != 'https') {
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));

    // ── Android 전용 WebView 세팅 ────────────────────────
    // 2026-05-30 공기계에서 토스 결제위젯이 안 뜨는 문제 대응:
    //   1) MixedContentMode.compatibilityMode
    //      토스 v2 위젯이 iframe 으로 HTTP/HTTPS 혼합 리소스를 로드할 때
    //      Android 기본 정책(MIXED_CONTENT_NEVER_ALLOW) 이면 차단되어
    //      위젯이 흰 박스로 표시됨. compatibilityMode = 안전한 자원만 허용.
    //   2) setMediaPlaybackRequiresUserGesture(false)
    //      일부 결제 SDK 의 로딩 인디케이터/사운드가 user gesture 요구로
    //      막혀 init 단에서 멈추는 케이스 회피.
    // iOS 는 WKWebView 가 기본적으로 위 정책을 안전하게 처리하므로 미적용.
    if (!kIsWeb && Platform.isAndroid) {
      final platform = _controller.platform;
      if (platform is AndroidWebViewController) {
        platform.setMediaPlaybackRequiresUserGesture(false);
        platform.setMixedContentMode(MixedContentMode.compatibilityMode);
      }
    }
  }

  // ── 결제 성공 처리 ──────────────────────────────────────
  void _handleSuccess(String url) {
    final uri = Uri.parse(url);
    final paymentKey = uri.queryParameters['paymentKey'] ?? '';
    final orderId = uri.queryParameters['orderId'] ?? '';
    final amount = int.tryParse(uri.queryParameters['amount'] ?? '0') ?? 0;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PaymentSuccessScreen(
          paymentKey: paymentKey,
          orderId: orderId,
          amount: amount,
        ),
      ),
    );
  }

  // ── 결제 실패 처리 ──────────────────────────────────────
  void _handleFail(String url) {
    final uri = Uri.parse(url);
    final code = uri.queryParameters['code'];
    final message = uri.queryParameters['message'];
    final orderId = uri.queryParameters['orderId'];

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PaymentFailScreen(
          code: code,
          message: message,
          orderId: orderId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Scaffold(
        body: Center(child: Text('웹에서는 지원되지 않는 화면입니다.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('결제', style: AppTextStyles.heading3),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
