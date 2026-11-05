import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../models/menu_item.dart';
import '../../providers/cart_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/menus_api_service.dart';
import '../../services/restaurants_api_service.dart';
import '../../services/sessions_api_service.dart';
import '../../services/votes_api_service.dart';
import '../../services/orders_api_service.dart';
import '../orders/order_tracking_screen.dart';
import '../payment/order_review_screen.dart';
import 'menu_swipe_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-16 메뉴 목록 / 장바구니 화면
//
// [데이터 소스]
//   - 진입 시 받은 widget.restaurantId 로
//     GET /api/restaurants/:id/menus 호출 → MenuItemDto 리스트 수신
//   - 백엔드 응답을 MenuItem 모델로 매핑해서 _menuItems 상태에 저장
//   - 카테고리 탭 변경 시 _filteredMenuItems getter 로 필터링
//
// [버그 히스토리]
//   - 2026-05-13 이전: 어느 식당에 들어가도 항상 시드 RESTAURANT_ID
//     ('11111111-...') 의 하드코딩된 12개 mock 메뉴만 보였음.
//     restaurant_detail_screen.dart 가 restaurantId 를 안 넘기고,
//     이 화면이 하드코딩 메뉴 상수만 그려서 발생.
//   - 2026-05-13 수정: restaurantId 인자 추가 + 실 API 연동 + 빈 상태 처리.
//   - 2026-05-13 추가 수정(C1): "주문하기" 버튼이 시드 sessionId
//     ('22222222-...') 를 하드코딩하던 문제 해결. 활성 세션(WAITING/
//     VOTING/ORDERED) 이 있을 때만 주문 가능하도록 가드 추가.
//     - sessionId 인자 우선 사용(호출부에서 명시 전달).
//     - 미전달 시 GET /api/sessions/today 로 활성 세션 자동 조회.
//     - 활성 세션이 없으면 주문 버튼 비활성 + "먼저 점심 세션을
//       만들어 봐요" 안내. 시드 fallback 절대 사용 금지.
//   - 2026-05-30 인계 정리(docs/menu_separate.md): 다단 폴백
//     (seed 필터링 / mock 12개) 흔적과 관련 import·상수·주석을 완전히
//     제거하고, 데이터 소스를 단일 1단계(API)로 단순화. 빈 상태
//     카피도 "메뉴 정보를 준비 중이에요" 로 통일.
//
// 와이어프레임 기준 구성 요소 (브레이크다운 v3 CU-16):
//   - 상단 앱바: 식당 이름 + 뒤로가기
//   - 카테고리 탭바: 전체 / 추천 / 밥류 / 면류 / 분식 / 음료
//   - 메뉴 항목 목록:
//       이미지 영역 + 이름 + 설명 + 가격 + 담기/수량 조절 버튼
//   - 하단 고정 바:
//       총 담긴 수량 + 총 금액 + "주문하기" 버튼
//
// 동작 흐름:
//   홈(CU-06) 식당 카드 탭
//     → CU-13 식당 상세 (전체 보기 버튼)
//       → 이 화면 (restaurantId 로 메뉴 조회 + 장바구니 구성)
//         → "주문하기" 버튼
//           → CU-17 그룹 주문 검토 (OrderReviewScreen)
//
// Riverpod 연동:
//   장바구니 상태(담기/수량변경/제거)는 cartProvider로 전역 관리합니다.
//   이 화면이 닫혀도 장바구니 내용이 유지되어
//   CU-20(그룹 주문 검토)에서 내용을 이어받을 수 있습니다.
// ══════════════════════════════════════════════════════════

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({
    super.key,
    required this.restaurantId, // 현재 진입한 식당의 UUID
    required this.restaurantName, // 식당 이름 (앱바 제목으로 표시)
    this.sessionId, // 주문을 묶을 점심 세션 ID (없으면 자동 조회)
  });

  /// 메뉴를 조회할 식당의 UUID
  /// (restaurant_detail_screen.dart 에서 widget.restaurantId 전달)
  final String restaurantId;

  /// 상단에 표시할 식당 이름
  final String restaurantName;

  /// 주문을 어느 점심 세션에 묶을지 결정하는 세션 UUID.
  ///
  /// [전달 규칙]
  ///   - 호출부(restaurant_detail_screen 등)에서 명시적으로 활성 세션 ID 를
  ///     전달하면 그 값을 그대로 사용.
  ///   - null 이면 화면 진입 시 GET /api/sessions/today 로 자동 조회 후,
  ///     활성 세션(WAITING/VOTING/ORDERED) 첫 번째를 사용.
  ///   - 끝까지 활성 세션을 찾지 못하면 "주문하기" 버튼은 비활성 상태로
  ///     유지되며, 시연용 시드 UUID fallback 은 절대 사용하지 않는다.
  final String? sessionId;

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ── 카테고리 탭 컨트롤러 ────────────────────────────────
  // SingleTickerProviderStateMixin: TabController 애니메이션에 필요한 Ticker 제공
  late final TabController _tabController;

  // ── 현재 선택된 카테고리 ─────────────────────────────────
  // 탭 변경 시 이 값을 기준으로 메뉴 목록을 필터링합니다.
  MenuCategory _selectedCategory = MenuCategory.all;

  // ── 식당/메뉴/세션 API 서비스 ────────────────────────────
  static const _restaurantsApi = RestaurantsApiService();
  static const _votesApi = VotesApiService();
  static const _ordersApi = OrdersApiService();

  List<SessionOrderMemberDto> _sessionOrders = const [];
  List<SharedCartItemDto> _sharedCartItems = const [];
  Timer? _pollTimer;
  bool _isPollingInFlight = false;
  int _consecutivePollFailures = 0;
  bool _isAppForeground = true;
  bool _didHydrateMyServerCart = false;
  Future<void> _cartSyncTail = Future<void>.value();
  final Map<String, MenuItem> _pendingCartItems = {};
  DateTime _nextPollAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _startPollingIfNeeded() {
    _pollTimer?.cancel();
    final sessionId = _resolvedSessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || !_isAppForeground) return;
      final sid = _resolvedSessionId;
      if (sid == null || sid.isEmpty) return;
      _loadSessionOrders(sid, silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppForeground = state == AppLifecycleState.resumed;
    if (_isAppForeground) {
      final sid = _resolvedSessionId;
      if (sid != null && sid.isNotEmpty) {
        _loadSessionOrders(sid, silent: true);
      }
    }
  }

  void _hydrateMyCartFromServerIfNeeded(List<SharedCartItemDto> serverItems) {
    if (_didHydrateMyServerCart) return;
    final menus = _menuItems;
    if (menus == null || menus.isEmpty) return;
    final myId = ref.read(userProvider).userId;
    if (myId == null || myId.isEmpty) return;

    final cartNotifier = ref.read(cartProvider.notifier);
    final currentRestaurantId = cartNotifier.currentRestaurantId;
    if (currentRestaurantId != null &&
        currentRestaurantId != widget.restaurantId) {
      return;
    }

    final myServerItems = serverItems.where(
      (item) => item.userId == myId && item.quantity > 0,
    );
    if (myServerItems.isEmpty) {
      _didHydrateMyServerCart = true;
      return;
    }

    final menuById = <String, MenuItem>{for (final m in menus) m.id: m};
    if (ref.read(cartProvider).isEmpty) {
      for (final sc in myServerItems) {
        final matched = menuById[sc.menuItemId];
        if (matched != null && !matched.isSoldOut) {
          cartNotifier.setItemQuantity(matched, sc.quantity);
        }
      }
    }
    _didHydrateMyServerCart = true;
  }

  Future<bool> _confirmSwitchRestaurantCartIfNeeded() async {
    final cartNotifier = ref.read(cartProvider.notifier);
    if (!cartNotifier.hasDifferentRestaurant(widget.restaurantId)) {
      return true;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('장바구니 식당 변경'),
        content: const Text(
          '다른 식당의 메뉴가 장바구니에 담겨 있습니다.\n기존 장바구니를 비우고 현재 식당 메뉴를 담을까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('비우고 담기'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      cartNotifier.clear();
      return true;
    }
    return false;
  }

  Future<void> _onIncrementMenuItem(MenuItem item) async {
    final canProceed = await _confirmSwitchRestaurantCartIfNeeded();
    if (!canProceed || !mounted) return;
    ref.read(cartProvider.notifier).addItem(item);
    setState(() {});
    await _syncCartItemToServer(item);
  }

  Future<void> _onDecrementMenuItem(MenuItem item) async {
    ref.read(cartProvider.notifier).decreaseItem(item.id);
    setState(() {});
    await _syncCartItemToServer(item);
  }

  Future<void> _syncCartItemToServer(MenuItem item) async {
    final sessionId = _resolvedSessionId;
    final token = ref.read(userProvider).accessToken;
    if (sessionId == null ||
        sessionId.isEmpty ||
        token == null ||
        token.isEmpty) {
      return;
    }
    final qty = ref.read(cartProvider.notifier).quantityOf(item.id);
    _pendingCartItems[item.id] = item;
    final previous = _cartSyncTail;
    final completion = Completer<void>();
    _cartSyncTail = completion.future;
    await previous;
    try {
      final list = await _sessionsApi.upsertSharedCartItem(
        accessToken: token,
        sessionId: sessionId,
        menuItemId: item.id,
        menuName: item.name,
        price: item.price,
        quantity: qty,
      );
      if (!mounted) return;
      if (ref.read(cartProvider.notifier).quantityOf(item.id) == qty) {
        _pendingCartItems.remove(item.id);
      }
      setState(() => _sharedCartItems = list);
    } on SharedCartApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      completion.complete();
    }
  }

  Future<bool> _syncAllLocalCartItemsToServer(String sessionId) async {
    final token = ref.read(userProvider).accessToken;
    if (token == null || token.isEmpty || sessionId.isEmpty) return false;
    await _cartSyncTail;
    final toSync = <String, MenuItem>{..._pendingCartItems};
    for (final ci in ref.read(cartProvider)) {
      if (ci.item.restaurantId == widget.restaurantId) {
        toSync[ci.item.id] = ci.item;
      }
    }
    for (final item in toSync.values) {
      await _syncCartItemToServer(item);
    }
    return _pendingCartItems.isEmpty;
  }

  Future<void> _mergeColleagueCartIntoMine() async {
    final canProceed = await _confirmSwitchRestaurantCartIfNeeded();
    if (!canProceed || !mounted) return;

    final myId = ref.read(userProvider).userId;
    final allMenus = _menuItems ?? const <MenuItem>[];
    final mergedMenuItems = <String, MenuItem>{};
    int addedCount = 0;
    for (final sc in _sharedCartItems) {
      if (sc.userId == myId || sc.quantity <= 0) continue;
      MenuItem? matched;
      for (final m in allMenus) {
        if (m.id == sc.menuItemId) {
          matched = m;
          break;
        }
      }
      if (matched != null && !matched.isSoldOut) {
        for (int i = 0; i < sc.quantity; i++) {
          ref.read(cartProvider.notifier).addItem(matched);
          addedCount++;
        }
        mergedMenuItems[matched.id] = matched;
      }
    }
    setState(() {});
    for (final item in mergedMenuItems.values) {
      await _syncCartItemToServer(item);
    }
    if (addedCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('동료가 담은 메뉴 $addedCount개를 내 장바구니로 합쳤어요!'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _loadSessionOrders(
    String sessionId, {
    bool silent = false,
  }) async {
    final token = ref.read(userProvider).accessToken;
    if (token == null || token.isEmpty || sessionId.isEmpty) return;
    if (_isPollingInFlight) return;
    if (_pendingCartItems.isNotEmpty) return;
    if (silent && DateTime.now().isBefore(_nextPollAt)) return;

    _isPollingInFlight = true;
    try {
      final list = await _ordersApi.getSessionOrders(
        accessToken: token,
        sessionId: sessionId,
      );
      final sharedCart = await _sessionsApi.getSharedCart(
        accessToken: token,
        sessionId: sessionId,
      );
      _consecutivePollFailures = 0;
      _nextPollAt = DateTime.fromMillisecondsSinceEpoch(0);
      if (!mounted) return;
      _hydrateMyCartFromServerIfNeeded(sharedCart);
      setState(() {
        _sessionOrders = list;
        _sharedCartItems = sharedCart;
      });
    } catch (_) {
      _consecutivePollFailures++;
      final exponent = _consecutivePollFailures.clamp(1, 5);
      _nextPollAt = DateTime.now().add(Duration(seconds: 8 * (1 << exponent)));
    } finally {
      _isPollingInFlight = false;
    }
  }

  bool _isCreatingQuickSession = false;

  Future<void> _handleProceedToOrder() async {
    if (_isCreatingQuickSession) return;
    var activeSessionId = _resolvedSessionId;

    if (activeSessionId == null || activeSessionId.isEmpty) {
      final token = ref.read(userProvider).accessToken;
      if (token == null || token.isEmpty) return;

      setState(() => _isCreatingQuickSession = true);
      try {
        final created = await _sessionsApi.createSession(
          accessToken: token,
          name: '${widget.restaurantName} 바로 주문',
          radius: 500,
          budget: 15000,
          returnMinutes: 30,
        );
        if (created != null) {
          final decided = await _votesApi.decide(
            accessToken: token,
            sessionId: created.id,
            restaurantId: widget.restaurantId,
          );
          if (decided != null) {
            activeSessionId = created.id;
            if (mounted) {
              setState(() => _resolvedSessionId = created.id);
              _startPollingIfNeeded();
            }
          }
        }
      } finally {
        if (mounted) {
          setState(() => _isCreatingQuickSession = false);
        }
      }
    }

    if (!mounted) return;
    if (activeSessionId == null || activeSessionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('주문 세션을 준비하지 못했어요. 잠시 후 다시 시도해 주세요.')),
      );
      return;
    }

    final synced = await _syncAllLocalCartItemsToServer(activeSessionId);
    if (!mounted) return;
    if (!synced) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('장바구니 저장을 완료하지 못했어요. 연결을 확인하고 다시 주문해 주세요.'),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderReviewScreen(
          sessionId: activeSessionId!,
          restaurantName: widget.restaurantName,
        ),
      ),
    );
    if (!mounted) return;
    await _loadSessionOrders(activeSessionId, silent: true);
  }

  static const _sessionsApi = SessionsApiService();
  // CORE-09(2026-05-31): 알레르기 충돌 검증기
  static const _menusApi = MenusApiService();

  // ── 메뉴 상태 ────────────────────────────────────────────
  // null = 아직 로딩 중, [] = 빈 응답(메뉴 없음), [..] = 정상 응답
  List<MenuItem>? _menuItems;
  bool _isLoading = true;
  String? _loadError;

  // ── 활성 점심 세션 상태 ──────────────────────────────────
  // C1 수정: 주문 버튼이 어느 세션에 주문을 박을지 결정하기 위한 캐시.
  //
  // [상태 의미]
  //   - _resolvedSessionId == null && _isResolvingSession == true:
  //       sessions/today 응답을 기다리는 중. 주문 버튼은 비활성.
  //   - _resolvedSessionId == null && _isResolvingSession == false:
  //       활성 세션이 없음. 주문 버튼 비활성 + 안내 토스트 트리거.
  //   - _resolvedSessionId != null:
  //       이 UUID 로 OrderReviewScreen 진입.
  //
  // [우선순위]
  //   1) widget.sessionId 가 명시 전달되어 있으면 즉시 그대로 사용
  //   2) 아니면 GET /api/sessions/today 호출 후 활성 세션 첫 번째 채택
  String? _resolvedSessionId;
  bool _isResolvingSession = true;

  // ── 현재 카테고리에 맞게 필터링된 메뉴 목록 ─────────────
  // getter: 탭 선택 때마다 재계산
  List<MenuItem> get _filteredMenuItems {
    final items = _menuItems ?? const <MenuItem>[];
    if (_selectedCategory == MenuCategory.all) return items;
    return items.where((item) => item.category == _selectedCategory).toList();
  }

  // ── 생명주기: 화면 초기화 ───────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // TabController 초기화
    // length: 탭 수 = MenuCategory의 값 수
    // vsync: 애니메이션 타이밍을 위해 this(Ticker) 전달
    _tabController = TabController(
      length: MenuCategory.values.length,
      vsync: this,
    );

    // 탭이 바뀔 때마다 _selectedCategory 업데이트 → UI 재빌드
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return; // 애니메이션 중엔 무시
      setState(() {
        _selectedCategory = MenuCategory.values[_tabController.index];
      });
    });

    // 첫 프레임 이후 토스트 + 메뉴 로딩 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-16');
      _loadMenus();
      _resolveActiveSession();
    });
  }

  // ── 활성 점심 세션 자동 조회 ────────────────────────────
  // C1 수정: 호출부에서 sessionId 를 명시 전달하지 않은 경우,
  // 손님이 어느 세션에 주문을 박을지 결정해 줘야 한다.
  //
  // [흐름]
  //   1) widget.sessionId 가 이미 있으면 그대로 채택 (네트워크 호출 생략)
  //   2) 토큰 없으면 비활성 처리 (로그인 안 된 상태)
  //   3) GET /api/sessions/today 호출
  //   4) 응답 중 WAITING/VOTING/ORDERED 상태인 첫 세션 채택
  //      (DONE 은 이미 끝난 세션이므로 후보에서 제외)
  //   5) 끝까지 활성 세션을 못 찾으면 _resolvedSessionId == null 유지.
  //      → 주문 버튼은 계속 비활성 + 안내 카피 노출.
  Future<void> _resolveActiveSession() async {
    // 1) 명시 전달 케이스: 그대로 채택
    final passed = widget.sessionId;
    if (passed != null && passed.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _resolvedSessionId = passed;
        _isResolvingSession = false;
      });
      _startPollingIfNeeded();
      _loadSessionOrders(passed);
      return;
    }

    // 2) 로그인 안 된 케이스: 자동 조회 불가
    final token = ref.read(userProvider).accessToken;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _resolvedSessionId = null;
        _isResolvingSession = false;
      });
      return;
    }

    // 3) sessions/today 호출 → 현재 식당으로 확정(ORDERED)된 활성 세션만 재사용.
    // 다른 식당 세션이나 미확정 세션을 끌어다 쓰면 ORDER_RESTAURANT_MISMATCH 가 발생하므로
    // 조건에 맞는 세션이 없으면 null 로 두어 주문 시 현재 식당 전용 세션을 생성하게 한다.
    final sessions = await _sessionsApi.getTodaySessions(accessToken: token);
    if (!mounted) return;

    final matchedActive = sessions
        .where(
          (s) =>
              s.status == 'ORDERED' &&
              s.winnerRestaurantId == widget.restaurantId,
        )
        .toList();

    setState(() {
      _resolvedSessionId = matchedActive.isEmpty
          ? null
          : matchedActive.first.id;
      _isResolvingSession = false;
    });
    if (matchedActive.isNotEmpty) {
      _startPollingIfNeeded();
      _loadSessionOrders(matchedActive.first.id);
    }
  }

  // ── 메뉴 목록 로딩 ──────────────────────────────────────
  // 백엔드의 GET /api/restaurants/:id/menus 를 호출해서
  // 현재 진입한 식당의 실제 메뉴를 받아옵니다.
  // - JWT 없으면 로그인 안내 상태로 종료
  // - 응답 카테고리 문자열을 MenuCategory enum 으로 매핑
  Future<void> _loadMenus() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = '로그인 정보가 없어 메뉴를 불러올 수 없어요.';
      });
      return;
    }

    final dtoList = await _restaurantsApi.getMenus(
      accessToken: token,
      restaurantId: widget.restaurantId,
    );

    if (!mounted) return;

    // DTO → 화면용 MenuItem 모델 변환
    // - 백엔드 category 문자열을 enum 으로 매핑
    // - description 누락 시 빈 문자열로 폴백
    // 외부 수집·AI 추정 메뉴의 가격은 확인되지 않았으므로 장바구니에 담지 않는다.
    final mapped = dtoList
        .where((dto) => dto.source == 'MANUAL')
        .map(
          (dto) => MenuItem(
            id: dto.id,
            restaurantId: widget.restaurantId,
            name: dto.name,
            description: dto.description ?? '',
            price: dto.price,
            category: _mapCategory(dto.category),
            imageUrl: dto.imageUrl,
            prepTimeMinutes: dto.prepTimeMinutes,
            ingredients: dto.ingredients,
          ),
        )
        .toList();

    setState(() {
      _menuItems = mapped;
      _isLoading = false;
      _loadError = null;
    });
    if (_sharedCartItems.isNotEmpty) {
      _hydrateMyCartFromServerIfNeeded(_sharedCartItems);
      setState(() {});
    }

    // CORE-09(2026-05-31): 메뉴 로딩이 끝났다면 알레르기 충돌도 함께 조회.
    // 별도 호출이지만 사용자 알레르기가 비어있으면 백엔드가 즉시 빈 결과로
    // 떨어뜨리므로 비용은 사실상 1회 라운드트립.
    _resolveAllergenConflicts();
  }

  // ── 알레르기 충돌 메뉴 조회 (CORE-09) ───────────────────
  // _loadMenus 직후에 호출. _menuItems 가 채워진 상태에서 menuId 기준으로
  // 충돌 메뉴 카드에 matchedAllergens 를 덮어쓴다.
  //
  // [실패 정책]
  //   네트워크 실패 / userId 누락 등 어떤 사유로든 알레르기 표시는 부가 기능.
  //   사용자 흐름을 막지 않고, 충돌 정보 없이도 메뉴 카드는 정상 표시된다.
  Future<void> _resolveAllergenConflicts() async {
    final items = _menuItems;
    if (items == null || items.isEmpty) return;

    final auth = ref.read(userProvider);
    final token = auth.accessToken;
    if (token == null || token.isEmpty) return;

    final conflicts = await _menusApi.checkAllergens(
      accessToken: token,
      restaurantId: widget.restaurantId,
    );
    if (!mounted) return;
    if (conflicts.isEmpty) return; // 충돌 없음 → 기존 상태 유지

    // menuId → matchedAllergens 매핑 (O(1) 조회용)
    final byMenuId = <String, List<String>>{
      for (final c in conflicts) c.menuId: c.matchedAllergens,
    };

    // 기존 _menuItems 를 순회하며 충돌이 있는 메뉴만 덮어쓰기.
    final updated = items.map((m) {
      final matched = byMenuId[m.id];
      if (matched == null || matched.isEmpty) return m;
      return m.copyWithAllergenConflicts(matched);
    }).toList();

    setState(() {
      _menuItems = updated;
    });
  }

  // ── 백엔드 카테고리 문자열 → MenuCategory enum 매핑 ─────
  // 백엔드에서 어떤 키워드로 카테고리를 내려주는지에 따라
  // 적절한 enum 으로 변환.
  //
  // ⚠️ 2026-05-14 변경 (m1 사후 정리):
  //   기존: 매칭 실패 시 MenuCategory.recommended (추천) 로 떨어뜨려
  //         "추천" 탭에 미매칭 메뉴가 우르르 쏟아져 본래 추천 메뉴와 섞이는
  //         문제 발생. 예) "양식"/"치킨"/"피자"/"카페"/"디저트" 모두 추천 탭으로.
  //   변경: ① 흔히 들어오는 키워드(면류 - 라멘/우동/파스타, 분식 - 떡볶이/김밥/
  //         라면, 음료 - 카페/디저트/베이커리)를 더 풍부하게 인식.
  //         ② 그래도 매칭 안 되면 MenuCategory.other("기타") 로 분리.
  //         이로써 "추천" 탭은 실제 추천 메뉴만 깔끔하게 유지됨.
  //
  // 매핑 규칙(우리 시드/팀 네이밍 컨벤션 + 흔한 외부 카테고리 키워드):
  //   "추천" / "recommended" / "베스트" / "인기"  → MenuCategory.recommended
  //   "밥" / "정식" / "덮밥" / "비빔밥" / "rice"  → MenuCategory.rice
  //   "면" / "국수" / "파스타" / "라멘" / "우동" / "noodle" → MenuCategory.noodle
  //   "분식" / "떡볶이" / "김밥" / "라면" / "튀김" / "snack" → MenuCategory.snack
  //   "음료" / "디저트" / "카페" / "커피" / "베이커리" / "케이크"
  //     / "drink" / "beverage" / "dessert" / "cafe"  → MenuCategory.drink
  //   그 외 / null  → MenuCategory.other ("기타" 탭)
  MenuCategory _mapCategory(String? raw) {
    if (raw == null || raw.isEmpty) return MenuCategory.other;
    final lower = raw.toLowerCase();

    // ── 1) 추천: 명시적 "추천/베스트/인기" 키워드만 인정 ──
    // 그 외 카테고리가 fall-through 로 떨어지지 않도록 가장 먼저 분기.
    if (raw.contains('추천') ||
        raw.contains('베스트') ||
        raw.contains('인기') ||
        lower.contains('recommend') ||
        lower.contains('best') ||
        lower.contains('popular')) {
      return MenuCategory.recommended;
    }

    // ── 2) 밥류: 한식 베이스의 밥·정식·덮밥·비빔밥 ──
    if (raw.contains('밥') ||
        raw.contains('정식') ||
        raw.contains('덮밥') ||
        raw.contains('비빔') ||
        lower.contains('rice')) {
      return MenuCategory.rice;
    }

    // ── 3) 면류: 국수·면·파스타·라멘·우동까지 확장 ──
    // 단 "라면"은 분식으로 분류해야 하므로 아래 분식 분기에서 먼저 잡힘.
    // (이 분기는 "라멘"/"우동"/"파스타" 같은 면류 위주 메뉴를 잡음)
    if (raw.contains('국수') ||
        raw.contains('파스타') ||
        raw.contains('라멘') ||
        raw.contains('우동') ||
        raw.contains('쌀국수') ||
        lower.contains('noodle') ||
        lower.contains('pasta') ||
        lower.contains('ramen') ||
        lower.contains('udon')) {
      return MenuCategory.noodle;
    }

    // ── 4) 분식: 떡볶이·김밥·라면·튀김 등 한국식 분식 ──
    // "라면"은 분식 카테고리가 더 자연스러워 여기서 먼저 매칭.
    if (raw.contains('분식') ||
        raw.contains('떡볶이') ||
        raw.contains('김밥') ||
        raw.contains('라면') ||
        raw.contains('튀김') ||
        raw.contains('순대') ||
        lower.contains('snack')) {
      return MenuCategory.snack;
    }

    // ── 5) 음료/디저트/카페 묶음 ──
    // 음료 단독 탭이지만 후식 성격(디저트/베이커리/카페)도 함께 묶어
    // 사용자가 "식후 한 잔" 흐름으로 자연스럽게 탐색하게 한다.
    if (raw.contains('음료') ||
        raw.contains('디저트') ||
        raw.contains('카페') ||
        raw.contains('커피') ||
        raw.contains('베이커리') ||
        raw.contains('빵') ||
        raw.contains('케이크') ||
        lower.contains('drink') ||
        lower.contains('beverage') ||
        lower.contains('dessert') ||
        lower.contains('cafe') ||
        lower.contains('coffee') ||
        lower.contains('bakery')) {
      return MenuCategory.drink;
    }

    // ── 6) 일반 면 키워드는 별도 분기로 마지막에 처리 ──
    // "면"이라는 글자 자체는 다른 카테고리(예: "면역", "면류") 오탐 가능성이
    // 낮지만, 위 키워드가 모두 빠진 뒤 마지막에 확인해 우선순위를 명확히 함.
    if (raw.contains('면')) {
      return MenuCategory.noodle;
    }

    // ── 7) 분류되지 않은 카테고리는 "기타" 탭으로 분리 ──
    //   예: "양식"/"중식"/"일식"/"치킨"/"피자"/"고기"/"샐러드" 등.
    //   추천 탭과 섞이지 않게 별도 탭에 모음. 사용자는 전체 탭에서도 볼 수 있음.
    return MenuCategory.other;
  }

  // ── 생명주기: 타이머·옵저버·TabController 메모리 해제 ─────
  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  // ── UI 최상위 구성 ──────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // cartProvider 감시: 장바구니가 바뀔 때마다 하단 바 및 버튼 UI 갱신
    final cartNotifier = ref.watch(cartProvider.notifier);
    final cartItems = ref.watch(cartProvider);

    // 총 담긴 수량과 총 금액 계산
    final totalCount = cartNotifier.totalCount;
    final totalPrice = cartNotifier.totalPrice;

    return Scaffold(
      backgroundColor: AppColors.background,

      // ── 상단 앱바 + 카테고리 탭바 ─────────────────────────
      appBar: _buildAppBarWithTabs(),

      // ── 본문: 로딩 / 에러 / 빈 상태 / 카테고리별 메뉴 목록 ─
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.sm,
              AppSpacing.screenHorizontal,
              0,
            ),
            child: RestaurantDataNotice(),
          ),

          // 메뉴 목록 (Expanded로 남은 공간 모두 차지)
          Expanded(child: _buildBody(cartItems)),

          // ── 하단 장바구니 요약 바 ─────────────────────────
          // 담긴 항목이 1개 이상일 때만 표시
          if (totalCount > 0) _buildCartBottomBar(totalCount, totalPrice),
        ],
      ),
    );
  }

  // ── 본문 분기 위젯 ──────────────────────────────────────
  // 로딩 / 에러 / 빈 / 정상 4가지 상태 처리
  Widget _buildBody(List<CartItem> cartItems) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            _loadError!,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }
    final allItems = _menuItems ?? const <MenuItem>[];
    if (allItems.isEmpty) {
      // 식당 자체에 메뉴가 1개도 없는 경우 (등록 전 식당 등)
      // 빈 상태 — 백엔드/사장님 메뉴 등록 대기 안내, 친근한 톤.
      // 인계 지시서(docs/menu_separate.md)가 지정한 카피로 통일.
      return Center(
        child: Text(
          '메뉴 정보를 준비 중이에요',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }
    return Column(
      children: [
        if (_sessionOrders.isNotEmpty || _sharedCartItems.isNotEmpty)
          _buildSessionOrdersBanner(),
        Expanded(child: _buildMenuList(cartItems)),
      ],
    );
  }

  Widget _buildSessionOrdersBanner() {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        8,
        AppSpacing.screenHorizontal,
        0,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primary.withAlpha(14),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: primary.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, size: 16, color: primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _sessionOrders.isNotEmpty
                      ? '같은 방 동료 주문 현황 (${_sessionOrders.length}건)'
                      : '같은 방 공동 장바구니 (${_sharedCartItems.length}건)',
                  style: AppTextStyles.label.copyWith(
                    color: primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_sessionOrders.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    if (_sessionOrders.isEmpty) return;
                    final firstOrderId = _sessionOrders.first.id;
                    if (firstOrderId.isEmpty) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            OrderTrackingScreen(orderId: firstOrderId),
                      ),
                    );
                  },
                  child: const Text('주문 추적 보기 →'),
                ),
            ],
          ),
          if (_sharedCartItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '🛒 공동 장바구니 (8초 주기 갱신): ${_sharedCartItems.map((c) => "${c.userName}(${c.menuName} x${c.quantity})").join(", ")}',
                    style: AppTextStyles.caption.copyWith(
                      color: primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 26),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: _mergeColleagueCartIntoMine,
                  child: const Text('동료 메뉴 합치기'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          ..._sessionOrders
              .take(3)
              .map(
                (so) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '• ${so.userName}: ${so.itemsSummary.isEmpty ? "메뉴 주문" : so.itemsSummary} (${_formatPrice(so.totalPrice)})',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget buildLegacyMenuList(List<CartItem> cartItems) {
    return _buildMenuList(cartItems);
  }

  // ── 앱바 + 탭바 위젯 ────────────────────────────────────
  // PreferredSizeWidget을 반환해야 Scaffold의 appBar에 사용 가능
  PreferredSizeWidget _buildAppBarWithTabs() {
    // 메뉴 개수: 로딩 중이면 "..." 로 표시
    final countLabel = _isLoading
        ? '메뉴 불러오는 중...'
        : '메뉴 ${(_menuItems ?? const []).length}개';

    // ── WOW#7: 스와이프 모드 토글 가용성 판단 ────────────────
    // 카드 5장 미만이면 스택이 너무 빈약해 UX 가치가 떨어지므로 비활성.
    // - 로딩 중에는 토글 자체를 보여주되 비활성 처리(Tooltip 안내).
    // - 5장 이상이면 정상 진입 가능.
    final menusForSwipe = (_menuItems ?? const <MenuItem>[])
        .where((m) => !m.isSoldOut)
        .toList();
    final canEnterSwipe = !_isLoading && menusForSwipe.length >= 5;
    final swipeTooltip = _isLoading
        ? '메뉴 불러오는 중…'
        : (menusForSwipe.length < 5
              ? '메뉴가 부족해요 (5개 이상 필요)'
              : '스와이프 모드로 메뉴 둘러보기');

    return AppBar(
      // 뒤로가기 버튼 자동 추가 (이전 화면으로 돌아갈 수 있음)
      leading: const BackButton(),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 식당 이름
          Text(widget.restaurantName, style: AppTextStyles.heading3),
          // 메뉴 개수 안내
          Text(
            countLabel,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),

      // ── 우측 액션: 스와이프 모드 토글 (WOW#7) ─────────────
      // 이 화면은 항상 리스트 모드, 스와이프는 별도 화면으로 push.
      // 그래서 아이콘은 늘 Icons.swipe 만 표시(상태 토글 X). 스와이프 화면 안에서
      // "리스트 모드로" 버튼으로 돌아오는 UX 가 자연스러움.
      actions: [
        Tooltip(
          message: swipeTooltip,
          child: IconButton(
            icon: const Icon(Icons.swipe),
            onPressed: canEnterSwipe
                ? () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MenuSwipeScreen(
                          restaurantId: widget.restaurantId,
                          restaurantName: widget.restaurantName,
                          menus: menusForSwipe,
                        ),
                      ),
                    );
                    if (!mounted) return;
                    final sid = _resolvedSessionId;
                    if (sid != null && sid.isNotEmpty) {
                      await _syncAllLocalCartItemsToServer(sid);
                    }
                  }
                : null,
          ),
        ),
      ],

      // 탭바: 카테고리 분류 탭 (앱바 하단에 붙음)
      bottom: TabBar(
        controller: _tabController,

        // 탭이 많으면 가로 스크롤 가능
        isScrollable: true,
        tabAlignment: TabAlignment.start, // 왼쪽 정렬
        // 선택된 탭 강조 색상
        labelColor: Theme.of(context).colorScheme.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: Theme.of(context).colorScheme.primary,
        indicatorWeight: 2.5,

        labelStyle: AppTextStyles.bodyMedium.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: AppTextStyles.bodyMedium,

        // MenuCategory enum의 모든 값을 탭으로 생성
        tabs: MenuCategory.values.map((cat) => Tab(text: cat.label)).toList(),
      ),
    );
  }

  // ── 메뉴 목록 위젯 ──────────────────────────────────────
  // 현재 카테고리에 해당하는 메뉴만 필터링하여 세로 목록으로 표시
  Widget _buildMenuList(List<CartItem> cartItems) {
    final items = _filteredMenuItems;

    // 해당 카테고리에 메뉴가 없을 때 (전체 식당에는 메뉴 있지만 탭 필터로 0개)
    if (items.isEmpty) {
      // 빈 상태 — 다른 탭에는 있을 수 있다는 점을 안내해 다음 액션 유도
      return Center(
        child: Text(
          '이 카테고리는 비어있어요. 다른 탭을 둘러보세요',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
        vertical: AppSpacing.md,
      ),
      itemCount: items.length,
      // 항목 사이 구분선
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: AppColors.divider),
      itemBuilder: (context, index) {
        // 이 메뉴가 장바구니에 몇 개 담겨 있는지
        final qty = ref.read(cartProvider.notifier).quantityOf(items[index].id);
        return _buildMenuItemCard(items[index], qty);
      },
    );
  }

  // ── 메뉴 항목 카드 위젯 하나 ────────────────────────────
  // 이미지 영역 + 이름/설명/가격 + 담기/수량 조절 버튼
  Widget _buildMenuItemCard(MenuItem item, int cartQty) {
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 메뉴 이미지 영역 ─────────────────────────────
          // [사장님 피드백 대응 — 2026-05-13]
          //   기존: imageUrl 이 있어도 Image.network 자체를 호출하지 않고
          //         항상 음식 아이콘만 그렸음 → 사진이 화면에 절대 노출되지 않음.
          //   개선: FoodImage 공통 위젯으로 교체.
          //         - imageUrl 이 있으면 실제 사진을 cover 로 표시
          //         - 빈/잘못된 URL 또는 로드 실패 시 카테고리 이모지 fallback
          //         - 품절 상태는 이미지 위에 반투명 오버레이로 표현
          //
          //   item.category.label = "밥류" / "면류" / "분식" / ... 등의 한글.
          //   FoodImage 의 resolveFoodEmoji 가 이 라벨을 보고 알맞은 이모지를 고른다.
          Stack(
            children: [
              // 사진(또는 카테고리 이모지) 본체
              FoodImage(
                imageUrl: item.imageUrl,
                categoryLabel: item.category.label,
                semanticLabel: '${item.name} 메뉴 사진',
              ),
              // ── 품절 오버레이 ───────────────────────────
              // 품절일 때만 사진 위에 반투명 회색 + "품절" 텍스트.
              // 색상 토큰은 backgroundGrey/textSecondary 그대로 사용.
              if (item.isSoldOut)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.backgroundGrey.withAlpha(210),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '품절',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              // ── 알레르기 충돌 배지 (CORE-09, 2026-05-31) ──
              // 사용자의 등록 알레르기와 메뉴 알레르기가 정확히 매칭된 경우에만 표시.
              // - 우상단 작은 원형 배지(⚠️ 이모지).
              // - 탭 시 BottomSheet 로 매칭 키워드 펼쳐 보여줌.
              // - Semantics 로 라벨 제공 → 시각장애 접근성 확보.
              if (item.allergenConflicts.isNotEmpty)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Semantics(
                    button: true,
                    label: '알레르기 충돌 ${item.allergenConflicts.length}건. 자세히 보기',
                    child: GestureDetector(
                      onTap: () => _showAllergenSheet(item),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          // 위험 시그널 색상 — 디자인 토큰의 경고 컬러가 있다면
                          // 추후 교체. 캡스톤 단계는 인라인 컬러 + 흰 글자로 충분히 가독.
                          color: const Color(0xFFFF5252),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Text(
                          '⚠️',
                          style: TextStyle(fontSize: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(width: AppSpacing.md),

          // ── 메뉴 정보 + 버튼 영역 ────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 메뉴 이름 ──────────────────────────────
                Text(
                  item.name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    // 품절이면 텍스트를 흐리게 표시
                    color: item.isSoldOut
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),

                const SizedBox(height: 4),

                // ── 메뉴 설명 ──────────────────────────────
                Text(
                  item.description,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis, // 2줄 초과 시 ... 처리
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    item.ingredients.isNotEmpty
                        ? '⏱ 약 ${item.prepTimeMinutes}분 · 재료: ${item.ingredients.join(", ")}'
                        : '⏱ 예상 조리 약 ${item.prepTimeMinutes}분',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                const SizedBox(height: AppSpacing.sm),

                // ── 가격 + 담기 버튼 행 ───────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 가격 표시
                    Text(
                      item.formattedPrice,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: item.isSoldOut
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),

                    // ── 장바구니 조작 버튼 영역 ───────────
                    // 품절이면 "품절" 뱃지, 담기지 않았으면 "담기" 버튼,
                    // 1개 이상 담겼으면 수량 조절(- / 수량 / +) 버튼
                    if (item.isSoldOut)
                      // 품절 상태 배지
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundGrey,
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                        ),
                        child: Text(
                          '품절',
                          style: AppTextStyles.label.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    else if (cartQty == 0)
                      // ── "담기" 버튼 (장바구니에 없을 때) ─
                      GestureDetector(
                        onTap: () {
                          _onIncrementMenuItem(item);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: primary,
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                          ),
                          child: Text(
                            '담기',
                            style: AppTextStyles.label.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    else
                      // ── 수량 조절 버튼 (이미 담긴 경우) ──
                      // [ -  수량  + ] 형태의 인라인 컨트롤
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 수량 감소 버튼 (0이 되면 항목 자동 제거 + 서버 0 동기화)
                          _buildQuantityButton(
                            icon: Icons.remove_rounded,
                            onTap: () {
                              _onDecrementMenuItem(item);
                            },
                          ),

                          // 현재 수량 표시
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              '$cartQty',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: primary,
                              ),
                            ),
                          ),

                          // 수량 증가 버튼
                          _buildQuantityButton(
                            icon: Icons.add_rounded,
                            onTap: () {
                              _onIncrementMenuItem(item);
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 수량 조절 공통 버튼 위젯 ───────────────────────────────
  // - / + 버튼에 공통으로 사용하는 원형 아이콘 버튼
  Widget _buildQuantityButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: primary.withAlpha(20), // 연한 주황 배경
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: primary),
      ),
    );
  }

  // ── 하단 장바구니 요약 바 위젯 ─────────────────────────────
  // 담긴 메뉴 수량 + 총 금액 + "주문하기" 버튼
  // 장바구니에 1개 이상 담겼을 때만 표시됨
  Widget _buildCartBottomBar(int totalCount, int totalPrice) {
    // 총 금액 포맷: MenuItem.formattedPrice와 동일한 방식
    final formattedTotal = _formatPrice(totalPrice);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        12,
        AppSpacing.screenHorizontal,
        32, // 하단 SafeArea 여백
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 총 수량 + 총 금액 요약 행 ─────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 담긴 총 메뉴 수
              Text(
                '총 $totalCount개',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),

              // 총 금액 (강조 표시)
              Text(
                '합계 $formattedTotal',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── "주문하기" 버튼 ───────────────────────────────
          // CU-17 주문 검토 화면으로 이동 → CU-18/19 토스 결제로 이어짐
          //
          // [C1 가드 — 시드 sessionId 하드코딩 제거]
          //   이전엔 어떤 식당이든 '22222222-...' 시드 세션으로 주문이
          //   박혀 사장 화면(OW-10) 에 잘못 노출될 위험이 있었다.
          //   이제는 widget.sessionId 또는 sessions/today 자동 조회로
          //   확보한 _resolvedSessionId 가 있을 때만 주문을 진행하고,
          //   없으면 버튼을 비활성 상태로 두고 친근한 카피로 안내한다.
          //
          //   - _isResolvingSession == true: 활성 세션 조회 중 → 비활성
          //   - _resolvedSessionId == null: 활성 세션 없음 → 비활성 +
          //     탭 시 "먼저 점심 세션을 만들어 봐요" 안내 토스트
          //   - _resolvedSessionId != null: 정상 진입
          Builder(
            builder: (_) {
              final resolved = _resolvedSessionId;
              final canOrder = !_isResolvingSession && !_isCreatingQuickSession;

              // 2026-05-15 UX 미세 개선 (배민 패턴):
              //   기존: 비활성 시 라벨이 "먼저 점심 세션을 만들어 봐요"로 바뀜 → 혼란
              //   변경: 라벨은 "주문하기" 항상 유지, 비활성 시 상단 안내 줄 1행 추가.
              //         배민/쿠팡이츠도 비활성 사유는 별도 텍스트로 분리.
              final label = _isResolvingSession
                  ? '세션 확인 중…'
                  : '주문하기 ($formattedTotal)';
              final disabledHint =
                  (resolved == null || resolved.isEmpty) && !_isResolvingSession
                  ? '활성 점심 세션이 없어도 주문하기를 누르면 바로 주문이 시작돼요'
                  : null;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (disabledHint != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: AppColors.textHint,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          disabledHint,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  AppPrimaryButton(
                    label: label,
                    // canOrder == false 면 onPressed 를 null 로 두어
                    // AppPrimaryButton 의 기본 비활성 스타일을 그대로 활용.
                    onPressed: canOrder ? _handleProceedToOrder : null,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ── 알레르기 충돌 BottomSheet (CORE-09) ──────────────────
  // 메뉴 카드의 ⚠️ 배지를 탭했을 때 호출.
  //
  // [디자인]
  //   - 상단 핸들 + 메뉴 이름 + 안내 카피.
  //   - 매칭된 알레르기 키워드는 Wrap 으로 칩 형태로 나열.
  //   - 우측 하단 닫기 버튼(Material 기본 BottomSheet drag-to-dismiss 와 병행).
  //
  // [카피 정책]
  //   - "포함된 알레르기 성분" — 사장/추천 엔진이 등록한 알레르기와
  //     사용자가 회피하고 싶은 알레르기가 정확히 매칭됐다는 사실만 전달.
  //   - 의료 자문 톤은 피하고, "주문 전 확인해 주세요" 정도로 부드럽게.
  void _showAllergenSheet(MenuItem item) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              12,
              AppSpacing.screenHorizontal,
              20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단 드래그 핸들
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // 타이틀: ⚠️ + 메뉴명
                Row(
                  children: [
                    const Text('⚠️ ', style: TextStyle(fontSize: 18)),
                    Expanded(
                      child: Text(
                        item.name,
                        style: AppTextStyles.heading3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '내 알레르기와 겹치는 성분이 있어요. 주문 전 한 번만 확인해 주세요.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                // 매칭 키워드 칩 나열
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: item.allergenConflicts
                      .map(
                        (a) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x1AFF5252), // 연한 빨강 배경
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                            border: Border.all(
                              color: const Color(0xFFFF5252),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            a,
                            style: AppTextStyles.label.copyWith(
                              color: const Color(0xFFD32F2F),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('확인'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 가격 포맷 헬퍼 ──────────────────────────────────────────
  // 세 자리마다 쉼표를 추가해 "14,500원" 형태로 반환
  String _formatPrice(int price) {
    final parts = <String>[];
    var n = price;
    while (n >= 1000) {
      parts.insert(0, (n % 1000).toString().padLeft(3, '0'));
      n ~/= 1000;
    }
    parts.insert(0, n.toString());
    return '${parts.join(',')}원';
  }
}
