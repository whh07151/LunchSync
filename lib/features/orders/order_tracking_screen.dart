import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../providers/user_provider.dart';
import '../../services/orders_api_service.dart';
import '../../services/sessions_api_service.dart';
import '../../services/reviews_api_service.dart';
// 2026-05-31 WOW#5 단골 랭킹 — COMPLETED 직후 단골 토스트 표출용.
import '../../services/restaurants_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-20 주문 추적 화면
//
// 폴링 3초 간격으로 주문 상태를 새로고침하여 변화 감지.
// 앱이 백그라운드로 가면 폴링 중단, 포그라운드 복귀 시 재시작.
//
// 주문 상태 흐름:
//   PENDING → PAID → PREPARING → READY → COMPLETED
//   CANCELLED (어느 상태에서든 전이 가능)
//
// 단계별 UI:
//   진행 중 상태(PREPARING, READY 등)는 진행 스텝 바로 표시
//   COMPLETED / CANCELLED는 최종 상태 배지만 표시
// ══════════════════════════════════════════════════════════

class OrderTrackingScreen extends ConsumerStatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen>
    with WidgetsBindingObserver {
  static const _api = OrdersApiService();
  static const _pollInterval = Duration(seconds: 3);

  // 주문 상태 단계 순서 (진행 스텝 바의 인덱스로 사용)
  // 2026-05-14 정정: 실제 백엔드 사용 값 = PENDING/PAID/PREPARING/READY/COMPLETED
  //   - orders.service.ts:17-18 주석에 명시된 전이 흐름
  //   - DTO 명세서(LUNCHSYNC_DTO.md L775) statusStep 매핑 동일
  //   - CLAUDE.md의 ACCEPTED/DONE은 옛 표기 (잘못된 정보)
  static const _steps = <String>['PENDING', 'PAID', 'PREPARING', 'READY', 'COMPLETED'];

  OrderDetailDto? _order;
  bool _isLoading = true;
  Timer? _poller;

  // 더치페이 명세서를 위한 세션 멤버 수 (sessionId 로 조회)
  // null = 미조회 / 0 = 조회 실패 / 1+ = 멤버 수
  int? _memberCount;

  // ── 별점/리뷰 로컬 상태 (2026-05-15) ──────────────────
  // Optimistic UI 패턴: 바텀시트에서 등록 성공 시 즉시 카드 숨김.
  // 폴링 응답이 review_score 를 반영하기 전 깜빡임을 막기 위해 로컬 캐싱.
  // null = 미작성 / 1~5 = 작성 완료
  int? _localReviewScore;

  /// 리뷰 제출 중 중복 클릭 방지 + 버튼 스피너 표시.
  bool _submittingReview = false;

  static const _reviewsApi = ReviewsApiService();

  // ── 단골 토스트 1회성 가드 (WOW#5, 2026-05-31) ─────────
  //
  // 폴링이 3초마다 _load() 를 부르는데, 한 번 COMPLETED 가 되면
  // 매 틱마다 토스트가 재발화하지 않도록 표출 후 true 로 잠근다.
  // 화면을 재진입(initState)하면 다시 false 로 시작 — 의도된 동작.
  bool _loyaltyToastShown = false;
  static const _restaurantsApi = RestaurantsApiService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-20');
      _load();
      _startPolling();
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── 앱 생명주기: 백그라운드 진입 시 폴링 중단 (배터리 보호) ──
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _poller?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _load();
      _startPolling();
    }
  }

  // ── 폴링 시작 (기존 타이머가 있으면 재시작) ────────────
  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(_pollInterval, (_) => _load());
  }

  // ── 주문 상세 조회 ─────────────────────────────────────
  Future<void> _load() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    final detail = await _api.getOrderById(
      accessToken: token,
      orderId: widget.orderId,
    );
    if (!mounted) return;
    setState(() {
      _order = detail;
      _isLoading = false;
    });

    // 주문이 최종 상태에 도달하면 폴링 중단 (불필요한 API 호출 회피)
    // 실제 백엔드 사용 값: COMPLETED(픽업 완료) 또는 CANCELLED(취소)
    if (detail != null &&
        (detail.status == 'COMPLETED' || detail.status == 'CANCELLED')) {
      _poller?.cancel();
    }

    // 세션 멤버 수 조회 (한 번만) — 더치페이 명세서 계산용
    if (detail != null && _memberCount == null) {
      _loadMemberCount(token, detail.sessionId);
    }

    // ── WOW#5 단골 토스트 (2026-05-31) ──────────────────
    //
    // COMPLETED 진입 직후 한 번만 "이 식당의 N번째 단골이 되셨어요" 토스트.
    // restaurantId 가 있을 때만 의미 있음(없으면 어느 식당인지 모름).
    // 폴링 재진입 시 _loyaltyToastShown 가드로 1회로 제한.
    if (detail != null &&
        detail.status == 'COMPLETED' &&
        detail.restaurantId != null &&
        detail.restaurantId!.isNotEmpty &&
        !_loyaltyToastShown) {
      _loyaltyToastShown = true; // 가드 먼저 — 조회 실패해도 재시도 안 함
      _showLoyaltyToastForCompleted(token, detail);
    }
  }

  // ── 단골 토스트 표출 (COMPLETED 직후 1회) ────────────────
  //
  // 백엔드 GET /restaurants/:id/loyalty?userId=:userId 호출.
  // visitCount 가 1 이상이면 친근 카피로 SnackBar 표시.
  // 실패/null = 토스트 미표시 (조용히 폴백 — 사용자 흐름 방해 X).
  Future<void> _showLoyaltyToastForCompleted(
    String token,
    OrderDetailDto order,
  ) async {
    final userId = ref.read(userProvider).userId;
    if (userId == null || userId.isEmpty) return;

    final loyalty = await _restaurantsApi.getLoyalty(
      accessToken: token,
      restaurantId: order.restaurantId!,
      userId: userId,
    );

    if (!mounted || loyalty == null || loyalty.visitCount <= 0) return;

    final message = loyalty.toastMessage();
    if (message.isEmpty) return;

    // 등급에 따라 토스트 배경 톤만 살짝 차이 — 디자인 토큰은 그대로.
    final amber = Colors.amber.shade700;
    final isVip = loyalty.rank == 'VIP';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isVip ? amber : null,
        content: Text(
          message,
          style: TextStyle(
            color: isVip ? Colors.white : null,
            fontWeight: FontWeight.w600,
          ),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ── 세션 멤버 수 조회 (더치페이 계산) ───────────────────
  // 멤버가 1명이면 명세서 미노출 (혼자 먹은 주문이므로 N분의1 의미 없음).
  Future<void> _loadMemberCount(String token, String sessionId) async {
    final result = await const SessionsApiService().getSessionMembers(
      accessToken: token,
      sessionId: sessionId,
    );
    if (!mounted) return;
    setState(() {
      _memberCount = result?.members.length ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(showBack: true, title: '주문 추적'),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _order == null
                ? _buildNotFound()
                : _buildContent(_order!),
      ),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Text(
        '주문 정보를 찾을 수 없어요',
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildContent(OrderDetailDto order) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 현재 상태 배지 + 주문 ID ────────────────────
          _buildStatusHeader(order),
          const SizedBox(height: AppSpacing.md),

          // ── 2026-05-31 WOW#2: 사장 라이브 카메라 1장 ────
          //   completionPhotoUrl 이 있으면 상단 hero 카드로 페이드인.
          //   "사장님이 보낸 음식 사진" 캡션 + aspect 4:3(약 320x240) + 둥근 모서리.
          //   AnimatedOpacity 300ms — 폴링 응답이 처음 도착할 때 부드럽게 등장.
          if (order.completionPhotoUrl != null &&
              order.completionPhotoUrl!.isNotEmpty) ...[
            _buildOwnerPhotoCard(order.completionPhotoUrl!),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── 진행 스텝 바 (CANCELLED 아닐 때만) ──────────
          if (order.status != 'CANCELLED') _buildStepBar(order.status),
          if (order.status != 'CANCELLED')
            const SizedBox(height: AppSpacing.lg),

          // ── 주문 항목 리스트 ────────────────────────────
          Text('주문 내역', style: AppTextStyles.heading3),
          const SizedBox(height: AppSpacing.sm),
          ...order.items.map(_buildItemRow),

          const Divider(height: 32),

          // ── 합계 ────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('합계', style: AppTextStyles.bodyMedium),
              Text(
                '${_formatComma(order.totalPrice)}원',
                style: AppTextStyles.heading3,
              ),
            ],
          ),

          // ── ETA 카드 (PAID/PREPARING 시) ────────
          // 2026-05-16 배민 패턴 — 예상 픽업 시각 표시.
          //   - 백엔드가 max(prep_time_minutes) + 기준시각 으로 계산
          //   - estimatedReadyAt 없으면 카드 숨김
          //   - 2026-05-30 P1 fix: ACCEPTED 는 CLAUDE.md 의 현재 ENUM 사용값
          //     아님 (옛 표기). READY 는 이미 준비 완료라 ETA 부적합.
          if (order.estimatedReadyAt != null &&
              const {'PAID', 'PREPARING'}.contains(order.status)) ...[
            const SizedBox(height: AppSpacing.md),
            _buildEtaCard(order.estimatedReadyAt!),
          ],

          // ── 더치페이 명세서 (2명 이상 세션일 때만) ─────────
          if (_memberCount != null && _memberCount! > 1) ...[
            const SizedBox(height: AppSpacing.md),
            _buildDutchPayCard(order.totalPrice, _memberCount!),
          ],

          // ── 별점 카드 (COMPLETED 도달 + 아직 미작성일 때만) ──
          // 2026-05-15 배민 패턴 — 주문 완료 직후 화면 하단에 카드 등장.
          //   - 카드 탭 → 바텀시트 (별 5개 + 리뷰 텍스트)
          //   - 등록 후 카드 숨김 (Optimistic UI, _localReviewScore 상태 갱신)
          if (order.status == 'COMPLETED' &&
              (order.reviewScore ?? _localReviewScore) == null) ...[
            const SizedBox(height: AppSpacing.md),
            _buildReviewPromptCard(order),
          ],

          const SizedBox(height: AppSpacing.md),

          // ── 자동 갱신 안내 ─────────────────────────────
          if (order.status != 'COMPLETED' && order.status != 'CANCELLED')
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sync_rounded,
                    size: 14, color: AppColors.textHint),
                const SizedBox(width: 4),
                Text(
                  '3초마다 자동 갱신 중',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── 상태 배지 + 주문 ID ──────────────────────────────
  Widget _buildStatusHeader(OrderDetailDto order) {
    final (label, color) = _statusLabel(order.status);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  label,
                  style: AppTextStyles.label.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '주문번호 ${order.id.substring(0, 8)}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_statusMessage(order.status), style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }

  // ── 진행 스텝 바 (5단계) ──────────────────────────────
  // 현재 상태의 인덱스까지 주황색, 그 이후는 회색.
  Widget _buildStepBar(String currentStatus) {
    final primary = Theme.of(context).colorScheme.primary;
    final currentIdx = _steps.indexOf(currentStatus);

    return Row(
      children: List.generate(_steps.length, (i) {
        final isDone = i <= currentIdx;
        final isLast = i == _steps.length - 1;

        return Expanded(
          child: Row(
            children: [
              // 스텝 원
              Column(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDone ? primary : AppColors.backgroundGrey,
                      shape: BoxShape.circle,
                    ),
                    child: isDone
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _stepShortLabel(_steps[i]),
                    style: AppTextStyles.caption.copyWith(
                      color: isDone ? primary : AppColors.textHint,
                      fontWeight: isDone ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
              // 연결선
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 18),
                    color: isDone ? primary : AppColors.divider,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  // ── 주문 항목 한 줄 ──────────────────────────────────
  Widget _buildItemRow(OrderItemDetailDto item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.menuName ?? '메뉴',
              style: AppTextStyles.bodyMedium,
            ),
          ),
          Text(
            '× ${item.quantity}',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${_formatComma(item.price * item.quantity)}원',
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── 상태 → 한글 레이블 + 색 ──────────────────────────
  (String, Color) _statusLabel(String status) {
    // 백엔드 ENUM order_status 실제 사용 값 (orders.service.ts:17-18)
    switch (status) {
      case 'PENDING':
        return ('결제 대기', Colors.grey);
      case 'PAID':
        return ('결제 완료', Colors.blue);
      case 'PREPARING':
        return ('준비 중', Colors.orange);
      case 'READY':
        return ('픽업 가능', Colors.green);
      case 'COMPLETED':
        return ('주문 완료', Colors.teal);
      case 'CANCELLED':
        return ('취소됨', Colors.red);
      default:
        return (status, Colors.grey);
    }
  }

  // ── 상태 → 안내 메시지 ───────────────────────────────
  // 백엔드 ENUM order_status 실제 사용 값
  String _statusMessage(String status) {
    switch (status) {
      case 'PENDING':
        return '결제가 진행 중이에요.';
      case 'PAID':
        return '결제가 완료됐어요. 식당이 준비를 시작할 거예요.';
      case 'PREPARING':
        return '식당에서 조리 중이에요.';
      case 'READY':
        return '픽업 준비가 끝났어요. 매장에서 받아 가세요!';
      case 'COMPLETED':
        return '주문이 완료됐어요. 맛있게 드셨길 바라요!';
      case 'CANCELLED':
        return '주문이 취소됐어요.';
      default:
        return '';
    }
  }

  // 스텝 바에서 보여줄 짧은 레이블
  String _stepShortLabel(String s) {
    switch (s) {
      case 'PENDING':
        return '결제';
      case 'PAID':
        return '결제완료';
      case 'PREPARING':
        return '준비중';
      case 'READY':
        return '픽업';
      case 'COMPLETED':
        return '완료';
      default:
        return s;
    }
  }

  String _formatComma(int value) {
    final s = value.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  // ── 더치페이 명세서 카드 ──────────────────────────────
  // 총금액 / 인원수 = 1인당 금액 (정수 올림)
  // "메시지 복사" 버튼 → 카카오톡 등 외부 앱에 붙여넣기 가능
  //
  // 디자인 가이드 (유사 앱 조사 결과):
  //   배민 1위 페인 "내 부담액 모름" 직격 → 결제 직후 인당 금액을 명확히 노출
  Widget _buildDutchPayCard(int totalPrice, int memberCount) {
    final perPerson = (totalPrice / memberCount).ceil();
    final primary = Theme.of(context).colorScheme.primary;
    final message =
        '점심 더치페이 안내\n총 ${_formatComma(totalPrice)}원 / $memberCount명\n'
        '1인당 ${_formatComma(perPerson)}원\n'
        '(LunchSync에서 자동 계산)';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: primary.withAlpha(15),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: primary.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_rounded, size: 18, color: primary),
              const SizedBox(width: 6),
              Text(
                '더치페이 자동 계산',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$memberCount명이 똑같이 나누면',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '1인당 ${_formatComma(perPerson)}원',
                style: AppTextStyles.heading3.copyWith(color: primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: message));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('더치페이 메시지가 복사됐어요.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
              label: const Text('카톡에 보내기'),
              style: OutlinedButton.styleFrom(
                foregroundColor: primary,
                side: BorderSide(color: primary.withAlpha(120)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // 사장 라이브 카메라 1장 (WOW#2 — 2026-05-31)
  // ══════════════════════════════════════════════════════════

  /// 사장이 POS 에서 보낸 음식 사진을 hero 카드로 표시.
  ///
  /// - aspect 4:3 (디자인 가이드 320x240 비율, 화면 가로 가득 채움)
  /// - 둥근 모서리 (AppRadius.card) + 살짝 그림자
  /// - AnimatedOpacity 300ms 페이드인 (첫 폴링 응답 도착 시 부드럽게)
  /// - 캡션 "사장님이 보낸 음식 사진" + 카메라 아이콘
  /// - 네트워크 로딩 실패 시 회색 placeholder 로 graceful 처리
  Widget _buildOwnerPhotoCard(String url) {
    final amber = Colors.amber.shade700;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, opacity, child) {
        return AnimatedOpacity(
          opacity: opacity,
          duration: const Duration(milliseconds: 300),
          child: child,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: amber.withAlpha(80)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 캡션 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                4,
              ),
              child: Row(
                children: [
                  Icon(Icons.camera_alt_rounded, size: 16, color: amber),
                  const SizedBox(width: 6),
                  Text(
                    '사장님이 보낸 음식 사진',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: amber,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            // 이미지 — Hero 위젯으로 감싸 추후 풀스크린 전환 확장 가능.
            // aspect 4:3 고정 → 가로 풀폭 + 세로 자동.
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Hero(
                tag: 'order-photo-${widget.orderId}',
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  // 로딩 중에는 회색 placeholder.
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: AppColors.backgroundGrey,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                  // 오류 시 작은 안내 — 흰 화면 대신 의미 있는 폴백.
                  errorBuilder: (ctx, err, stack) {
                    return Container(
                      color: AppColors.backgroundGrey,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image_outlined,
                              size: 32,
                              color: AppColors.textHint,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '사진을 불러오지 못했어요',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textHint,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // ETA 카드 (배민 패턴 — 2026-05-16 자율 발전 로드맵 단계 2)
  // ══════════════════════════════════════════════════════════

  /// 예상 픽업 시각 카드.
  /// - 백엔드가 max(prep_time_minutes) + 기준시각 으로 ISO8601 으로 내려줌
  /// - "약 N분 후 픽업" 형식, 시각이 지난 경우 "곧 픽업 가능" 으로 처리
  Widget _buildEtaCard(String etaIso) {
    final eta = DateTime.tryParse(etaIso);
    if (eta == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final diff = eta.difference(now);
    final mins = diff.inMinutes;
    final hh = eta.hour.toString().padLeft(2, '0');
    final mm = eta.minute.toString().padLeft(2, '0');
    final label = mins <= 0
        ? '곧 픽업 가능 (예정 $hh:$mm)'
        : '약 $mins분 후 픽업 가능 (예정 $hh:$mm)';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: CustomerColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CustomerColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined,
              size: 20, color: CustomerColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // 별점/리뷰 UI (배민 패턴 — 2026-05-15 자율 발전 로드맵)
  // ══════════════════════════════════════════════════════════

  // ── 별점 작성 유도 카드 ──────────────────────────────────
  // 주문 추적 화면 하단에 노출되는 콜투액션 카드.
  //   - amber 톤 (별점 표준 색) 으로 시선 유도
  //   - 한 줄 헤더 + 보조 카피 + Pen 아이콘
  //   - 카드 전체가 InkWell → 탭 시 바텀시트 오픈
  //
  // 기존 디자인 토큰만 사용 (AppRadius/AppSpacing/AppColors), 새 색상 추가 X.
  Widget _buildReviewPromptCard(OrderDetailDto order) {
    final amber = Colors.amber.shade600;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: _submittingReview ? null : () => _openReviewSheet(order),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: amber.withAlpha(15),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: amber.withAlpha(70)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: amber.withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.star_rounded, color: amber, size: 24),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '오늘 식사는 어땠어요?',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '별점을 남기면 다음 점심 추천에 반영돼요',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: amber,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 별점/리뷰 작성 바텀시트 ───────────────────────────────
  // 1) 별 5개 (1~5 클릭 가능). 클릭 시 인덱스만 setState — 등록 전엔 서버 호출 X.
  // 2) 선택 텍스트 입력 (TextField, maxLength 500).
  // 3) "등록" 버튼 → API 호출 (Optimistic UI).
  //
  // dispose 안전성 — controller 는 StatefulBuilder 내부에서 만들고
  // 닫힐 때 dispose. showModalBottomSheet 의 builder 안에서 만든
  // 컨트롤러는 sheet pop 시 자동 해제되지 않으므로 명시 dispose.
  Future<void> _openReviewSheet(OrderDetailDto order) async {
    int selectedScore = 5; // 기본값 5점 (긍정 가설 — 손님이 가장 자주 누르는 값)
    final textController = TextEditingController();
    final primary = Theme.of(context).colorScheme.primary;
    final amber = Colors.amber.shade600;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true, // 키보드 올라올 때 화면 가려지지 않게
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetCtx) {
          // StatefulBuilder 로 별 토글/제출 중 상태 관리.
          return StatefulBuilder(
            builder: (ctx, setSheetState) {
              final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  bottomInset + AppSpacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 핸들바
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // 헤더
                    Text(
                      '별점 남기기',
                      style: AppTextStyles.heading3,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '주문 #${order.id.substring(0, 8)}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // 별 5개 — 인덱스 1~5
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) {
                        final starIdx = i + 1;
                        final isFilled = starIdx <= selectedScore;
                        return IconButton(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          iconSize: 36,
                          onPressed: _submittingReview
                              ? null
                              : () => setSheetState(
                                    () => selectedScore = starIdx,
                                  ),
                          icon: Icon(
                            isFilled
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: isFilled ? amber : AppColors.iconInactive,
                          ),
                          tooltip: '$starIdx점',
                        );
                      }),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        _scoreLabel(selectedScore),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // 텍스트 입력 (선택)
                    TextField(
                      controller: textController,
                      maxLength: 500,
                      maxLines: 3,
                      minLines: 2,
                      enabled: !_submittingReview,
                      decoration: const InputDecoration(
                        labelText: '한 줄 후기 (선택)',
                        hintText: '맛, 양, 친절도 등 의견을 적어주세요',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // 등록 버튼
                    FilledButton.icon(
                      onPressed: _submittingReview
                          ? null
                          : () async {
                              setSheetState(() {});
                              await _submitReview(
                                orderId: order.id,
                                score: selectedScore,
                                text: textController.text.trim(),
                                onDone: () {
                                  if (sheetCtx.mounted) {
                                    Navigator.of(sheetCtx).pop();
                                  }
                                },
                              );
                            },
                      icon: _submittingReview
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(_submittingReview ? '등록 중...' : '등록'),
                      style: FilledButton.styleFrom(
                        backgroundColor: primary,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      // showModalBottomSheet 결과와 무관하게 컨트롤러 누수 방지.
      textController.dispose();
    }
  }

  // ── 별점 등록 API 호출 + Optimistic UI ────────────────────
  // 성공: 스낵바 "별점 등록 완료" + _localReviewScore 갱신 → 카드 자동 숨김
  // 실패: 스낵바 안내 + 카드 유지 (사용자가 다시 시도 가능)
  Future<void> _submitReview({
    required String orderId,
    required int score,
    required String text,
    required VoidCallback onDone,
  }) async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요해요')),
      );
      return;
    }

    setState(() => _submittingReview = true);

    final ok = await _reviewsApi.submitReview(
      accessToken: token,
      orderId: orderId,
      score: score,
      text: text.isEmpty ? null : text,
    );

    if (!mounted) return;
    setState(() => _submittingReview = false);

    if (ok) {
      // 카드 즉시 숨김 — 폴링이 review_score 를 가져오기 전 깜빡임 방지.
      setState(() => _localReviewScore = score);
      onDone();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('별점 등록 완료'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('별점 등록에 실패했어요. 잠시 후 다시 시도해주세요'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// 별점 숫자 → 사람 친화 라벨. 작성 동기 부여 + 입력 확인 보조.
  String _scoreLabel(int score) {
    switch (score) {
      case 1:
        return '많이 아쉬웠어요';
      case 2:
        return '아쉬웠어요';
      case 3:
        return '괜찮았어요';
      case 4:
        return '좋았어요';
      case 5:
        return '아주 좋았어요!';
      default:
        return '';
    }
  }
}
