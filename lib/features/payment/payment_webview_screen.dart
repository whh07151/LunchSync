import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
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
