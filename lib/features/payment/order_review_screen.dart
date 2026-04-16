import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../providers/cart_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/orders_api_service.dart';
import 'payment_web_bridge.dart';
import 'payment_webview_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-17 그룹 주문 검토 / 결제 시작 화면
//
// 티켓:
//   CU-17 — 그룹 주문 검토 (우현호)
//   CU-18 — 결제 방식 선택 (우현호, 여기선 토스 결제위젯 자동 전개)
//   CU-19 — 결제 호출 (우현호)
//
// 주요 기능:
//   1) 장바구니(cartProvider) 내용 요약 + 총 금액 표시
//   2) "결제하기" 버튼 → 백엔드 POST /api/orders (paymentMethod=TOSS)
//   3) 생성된 orderId + totalPrice 로 토스 결제위젯 HTML 리다이렉트
//      (web/toss-checkout.html) — successUrl/failUrl 은 Flutter 앱 루트
//
// 웹 전용:
//   이 화면의 결제 버튼은 브라우저 리다이렉트를 사용하므로
//   Flutter 웹 빌드에서만 동작합니다. 모바일에선 안내 후 차단.
//
// 데이터 흐름:
//   cartProvider → items → CreateOrderItem 리스트 → /api/orders 호출
//   → orderId/totalPrice 확보 → sessionStorage 에 JWT/orderId 백업
//   → window.location.assign('/toss-checkout.html?...')
// ══════════════════════════════════════════════════════════

class OrderReviewScreen extends ConsumerStatefulWidget {
  const OrderReviewScreen({
    super.key,
    required this.sessionId,
    required this.restaurantName,
  });

  /// 점심 세션 UUID — /api/orders 의 sessionId 로 전달
  /// TODO: 실제 세션 흐름 연결 시 sessionProvider 에서 읽어오도록 변경
  final String sessionId;

  /// 상단 표시용 식당명 (주문명 orderName 에도 사용)
  final String restaurantName;

  @override
  ConsumerState<OrderReviewScreen> createState() => _OrderReviewScreenState();
}

class _OrderReviewScreenState extends ConsumerState<OrderReviewScreen> {
  // 주문 생성 + 토스 리다이렉트 진행 중인지 여부 (중복 클릭 방지)
  bool _isProcessing = false;

  // 에러 메시지 (주문 생성 실패 등)
  String? _errorMessage;

  // Orders API 서비스 싱글턴
  final OrdersApiService _ordersApi = const OrdersApiService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-17');
    });
  }

  // ── 결제 시작 핸들러 ──────────────────────────────────
  // 흐름:
  //   1) JWT 확인 (없으면 중단)
  //   2) 장바구니 비어있는지 확인
  //   3) /api/orders 호출 — 주문 생성 (PENDING 상태)
  //   4) sessionStorage 에 JWT / orderId / amount 백업 (리로드 대비)
  //   5) /toss-checkout.html?... 로 전체 페이지 리다이렉트
  Future<void> _startPayment() async {
    if (_isProcessing) return;

    final user = ref.read(userProvider);
    final cart = ref.read(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    // ── 1. JWT 확인 ────────────────────────────────────
    final accessToken = user.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      setState(() => _errorMessage = '로그인 정보가 없습니다. 다시 로그인해주세요.');
      return;
    }

    // ── 2. 장바구니 확인 ──────────────────────────────
    if (cart.isEmpty) {
      setState(() => _errorMessage = '장바구니가 비어 있습니다.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // ── 3. 주문 생성 API 호출 ────────────────────────
      // cartProvider 의 CartItem 들을 CreateOrderItem 으로 변환
      final orderItems = cart
          .map((ci) => CreateOrderItem(
                menuItemId: ci.item.id,
                quantity: ci.quantity,
              ))
          .toList();

      final result = await _ordersApi.createOrder(
        accessToken: accessToken,
        sessionId: widget.sessionId,
        items: orderItems,
        paymentMethod: 'TOSS',
      );

      if (result == null) {
        setState(() {
          _isProcessing = false;
          _errorMessage =
              '주문 생성에 실패했습니다.\n메뉴가 DB 에 등록되어 있는지 확인해주세요.';
        });
        return;
      }

      // 백엔드가 계산한 총 금액 vs 프론트 계산 금액 비교 (위변조 방지 체크)
      if (result.totalPrice != cartNotifier.totalPrice) {
        // 서버 금액을 신뢰 — 로그만 남기고 진행
        // ignore: avoid_print
        print(
          '[OrderReview] 금액 불일치: '
          'server=${result.totalPrice} local=${cartNotifier.totalPrice}',
        );
      }

      // ── 4. 리다이렉트 전 상태 백업 ──────────────────
      // Flutter 웹은 토스 결제 페이지로 전체 리다이렉트될 때
      // 앱이 새로 로드돼 Riverpod(userProvider) 상태가 초기화됩니다.
      // 복원 가능하도록 JWT 뿐 아니라 유저 기본정보도 함께 저장.
      PaymentWebBridge.setSessionItem('ls_jwt', accessToken);
      if (user.userId != null) {
        PaymentWebBridge.setSessionItem('ls_user_id', user.userId!);
      }
      if (user.name != null) {
        PaymentWebBridge.setSessionItem('ls_user_name', user.name!);
      }
      if (user.profileImage != null) {
        PaymentWebBridge.setSessionItem(
          'ls_user_profile',
          user.profileImage!,
        );
      }
      PaymentWebBridge.setSessionItem('ls_order_id', result.id);
      PaymentWebBridge.setSessionItem(
        'ls_order_amount',
        result.totalPrice.toString(),
      );
      PaymentWebBridge.setSessionItem(
        'ls_order_name',
        '${widget.restaurantName} 외 ${cart.length - 1}건',
      );

      // ── 5. 토스 결제위젯으로 이동 ─────────────────────
      final customerKey = user.userId ?? 'ANONYMOUS';
      final orderName = _composeOrderName(cart.length);

      if (kIsWeb) {
        // 웹: 브라우저 전체 페이지 리다이렉트
        final origin = PaymentWebBridge.origin();
        final successUrl = Uri.parse(origin).replace(queryParameters: {
          'paymentStatus': 'success',
        }).toString();
        final failUrl = Uri.parse(origin).replace(queryParameters: {
          'paymentStatus': 'fail',
        }).toString();

        final checkoutUrl = Uri.parse('$origin/toss-checkout.html').replace(
          queryParameters: {
            'orderId': result.id,
            'orderName': orderName,
            'amount': result.totalPrice.toString(),
            'clientKey': AppConfig.tossClientKey,
            'customerKey': customerKey,
            'successUrl': successUrl,
            'failUrl': failUrl,
          },
        ).toString();

        PaymentWebBridge.redirect(checkoutUrl);
        // redirect 이후 코드는 실행되지 않음 (페이지 전환됨)
      } else {
        // 모바일: 인앱 WebView 로 결제 진행
        // 백엔드 서버의 toss-checkout.html 을 사용
        final backendOrigin = AppConfig.backendBaseUrl.replaceAll('/api', '');
        final successUrlPrefix = '$backendOrigin/payment-success';
        final failUrlPrefix = '$backendOrigin/payment-fail';

        final checkoutUrl = Uri.parse('$backendOrigin/toss-checkout.html').replace(
          queryParameters: {
            'orderId': result.id,
            'orderName': orderName,
            'amount': result.totalPrice.toString(),
            'clientKey': AppConfig.tossClientKey,
            'customerKey': customerKey,
            'successUrl': '$successUrlPrefix?paymentStatus=success',
            'failUrl': '$failUrlPrefix?paymentStatus=fail',
          },
        ).toString();

        if (!mounted) return;
        setState(() => _isProcessing = false);

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PaymentWebViewScreen(
              checkoutUrl: checkoutUrl,
              successUrlPrefix: successUrlPrefix,
              failUrlPrefix: failUrlPrefix,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = '결제 시작 중 오류가 발생했습니다.\n$e';
      });
    }
  }

  // ── 주문명 조립 헬퍼 ─────────────────────────────────
  // 토스 orderName 은 2~100자. 단일 메뉴면 메뉴명, 여러 개면 "메뉴 외 N건"
  String _composeOrderName(int itemCount) {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return 'LunchSync 주문';
    final first = cart.first.item.name;
    if (itemCount <= 1) return first;
    return '$first 외 ${itemCount - 1}건';
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.watch(cartProvider.notifier);
    final totalPrice = cartNotifier.totalPrice;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('주문 검토', style: AppTextStyles.heading3),
        leading: const BackButton(),
      ),
      body: Column(
        children: [
          // ── 식당 정보 ─────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('주문 식당', style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                )),
                const SizedBox(height: 4),
                Text(widget.restaurantName, style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w700,
                )),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── 장바구니 목록 ─────────────────────────────
          Expanded(
            child: cart.isEmpty
                ? Center(
                    child: Text(
                      '장바구니가 비어 있습니다',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenHorizontal,
                      vertical: AppSpacing.md,
                    ),
                    itemCount: cart.length,
                    separatorBuilder: (context, index) => const Divider(
                      height: 1,
                      color: AppColors.divider,
                    ),
                    itemBuilder: (context, index) {
                      final ci = cart[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ci.item.name,
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '수량 ${ci.quantity}개',
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${_formatPrice(ci.subtotal)}원',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // ── 에러 메시지 ───────────────────────────────
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0EE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                style: AppTextStyles.bodySmall.copyWith(
                  color: const Color(0xFFD4351C),
                ),
              ),
            ),

          // ── 하단 결제 바 ─────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              12,
              AppSpacing.screenHorizontal,
              32,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: AppColors.divider, width: 1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '총 결제 금액',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${_formatPrice(totalPrice)}원',
                      style: AppTextStyles.heading3.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppPrimaryButton(
                  label: _isProcessing
                      ? '결제 준비 중...'
                      : '${_formatPrice(totalPrice)}원 결제하기',
                  isLoading: _isProcessing,
                  isEnabled: cart.isNotEmpty && !_isProcessing,
                  onPressed: _startPayment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 가격 포맷 헬퍼 (천 단위 콤마) ─────────────────────
  String _formatPrice(int price) {
    final parts = <String>[];
    var n = price;
    while (n >= 1000) {
      parts.insert(0, (n % 1000).toString().padLeft(3, '0'));
      n ~/= 1000;
    }
    parts.insert(0, n.toString());
    return parts.join(',');
  }
}
