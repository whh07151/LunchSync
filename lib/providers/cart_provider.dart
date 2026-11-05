import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/menu_item.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 장바구니 전역 상태 관리 (Riverpod) — CU-16 연관
//
// 담당 범위:
// //   CU-16(메뉴 목록/장바구니) → 담기/수량 변경/삭제 조작
// //   CU-20(그룹 주문 검토, 안태환 담당) → 장바구니 내용 읽기
// //   CU-21(주문/결제, 우현호 담당) → 총 금액 읽기
// //
// // 왜 전역 상태가 필요한가?
// //   메뉴 목록 화면(CU-16)에서 담은 항목이 주문 화면(CU-20/21)까지 유지되어야 합니다.
//   또한 같은 세션의 여러 멤버가 각자 장바구니를 구성한 결과를
//   그룹 주문 화면(CU-20)에서 합산해 보여줘야 하므로 전역 관리가 필요합니다.
//
// CartItem 구조:
//   한 메뉴 항목(MenuItem)과 선택된 수량(quantity)을 함께 묶은 단위입니다.
// ══════════════════════════════════════════════════════════

// ── 장바구니 항목 하나의 데이터 ────────────────────────────
class CartItem {
  const CartItem({
    required this.item, // 메뉴 정보 (이름, 가격 등)
    required this.quantity, // 선택 수량 (최소 1)
  });

  final MenuItem item;
  final int quantity;

  // ── 항목 소계 ────────────────────────────────────────────
  // 이 항목의 가격 × 수량 = 소계
  int get subtotal => item.price * quantity;

  // ── 불변 복사 헬퍼 ───────────────────────────────────────
  // 수량만 바꾸는 경우에 사용
  CartItem copyWith({int? quantity}) {
    return CartItem(item: item, quantity: quantity ?? this.quantity);
  }
}

// ── CartNotifier: 장바구니 상태를 조작하는 비즈니스 로직 ───
class CartNotifier extends Notifier<List<CartItem>> {
  final Set<String> _consumedOrderIds = {};

  /// A repeated payment callback must not subtract a new cart for the same order.
  void consumeOrderSnapshot(
    String orderId,
    List<({String menuItemId, int quantity})> items,
  ) {
    if (orderId.isEmpty ||
        items.isEmpty ||
        _consumedOrderIds.contains(orderId)) {
      return;
    }
    consumeOrderedItems(items);
    _consumedOrderIds.add(orderId);
  }

  /// Provider 초기 상태: 빈 장바구니
  @override
  List<CartItem> build() => const [];

  String? get currentRestaurantId =>
      state.isEmpty ? null : state.first.item.restaurantId;

  bool hasDifferentRestaurant(String restaurantId) =>
      state.any((item) => item.item.restaurantId != restaurantId);

  void setItemQuantity(MenuItem item, int quantity) =>
      setQuantity(item, quantity);

  // ── 메뉴 담기 (수량 1 추가) ─────────────────────────────
  // 이미 담긴 메뉴면 수량 +1, 처음 담는 메뉴면 새 항목으로 추가.
  // 서로 다른 식당의 메뉴가 섞이지 않도록 식당 전환 시 기존 다른 식당 항목을 정리한다.
  void addItem(MenuItem item) {
    final baseList = state
        .where((e) => e.item.restaurantId == item.restaurantId)
        .toList();
    final index = baseList.indexWhere((e) => e.item.id == item.id);

    if (index >= 0) {
      final nextQty = (baseList[index].quantity + 1).clamp(1, 99);
      baseList[index] = baseList[index].copyWith(quantity: nextQty);
      state = List.unmodifiable(baseList);
    } else {
      state = List.unmodifiable([
        ...baseList,
        CartItem(item: item, quantity: 1),
      ]);
    }
  }

  /// 특정 메뉴의 수량을 지정 값으로 설정 (0 이하면 제거, 서버 동기화 실패 롤백 등에 사용)
  void setQuantity(MenuItem item, int quantity) {
    final baseList = state
        .where((e) => e.item.restaurantId == item.restaurantId)
        .toList();
    final index = baseList.indexWhere((e) => e.item.id == item.id);
    if (quantity <= 0) {
      if (index >= 0) {
        baseList.removeAt(index);
        state = List.unmodifiable(baseList);
      }
      return;
    }
    final clamped = quantity.clamp(1, 99);
    if (index >= 0) {
      baseList[index] = baseList[index].copyWith(quantity: clamped);
    } else {
      baseList.add(CartItem(item: item, quantity: clamped));
    }
    state = List.unmodifiable(baseList);
  }

  /// 주문 완료 시 주문에 포함된 스냅샷 품목·수량만 차감하고,
  /// 결제 도중 새로 추가된 항목이나 추가 수량은 보존한다.
  void consumeOrderedItems(
    List<({String menuItemId, int quantity})> orderedSnapshot,
  ) {
    if (orderedSnapshot.isEmpty) return;
    final remainingByMenu = <String, int>{};
    for (final ord in orderedSnapshot) {
      if (ord.quantity > 0) {
        remainingByMenu[ord.menuItemId] =
            (remainingByMenu[ord.menuItemId] ?? 0) + ord.quantity;
      }
    }
    final next = <CartItem>[];
    for (final ci in state) {
      final toConsume = remainingByMenu[ci.item.id] ?? 0;
      if (toConsume <= 0) {
        next.add(ci);
      } else if (ci.quantity > toConsume) {
        next.add(ci.copyWith(quantity: ci.quantity - toConsume));
        remainingByMenu.remove(ci.item.id);
      } else {
        remainingByMenu[ci.item.id] = toConsume - ci.quantity;
      }
    }
    state = List.unmodifiable(next);
  }

  // ── 수량 1 감소 (0이 되면 자동으로 항목 제거) ─────────────
  // 메뉴 항목의 수량 - 버튼에 연결
  void decreaseItem(String menuId) {
    final index = state.indexWhere((e) => e.item.id == menuId);
    if (index < 0) return; // 장바구니에 없는 항목이면 무시

    if (state[index].quantity <= 1) {
      // 수량이 1이었으면 → 항목 전체 제거
      final updated = [...state]..removeAt(index);
      state = List.unmodifiable(updated);
    } else {
      // 수량이 2 이상이면 → 1 감소
      final updated = [...state];
      updated[index] = updated[index].copyWith(
        quantity: updated[index].quantity - 1,
      );
      state = List.unmodifiable(updated);
    }
  }

  // ── 항목 직접 제거 ───────────────────────────────────────
  // 메뉴 항목의 삭제(X) 버튼에 연결
  void removeItem(String menuId) {
    state = List.unmodifiable(state.where((e) => e.item.id != menuId).toList());
  }

  // ── 장바구니 전체 비우기 ────────────────────────────────
  // 주문 완료 또는 세션 종료 시 호출.
  // 결제 성공 후 payment_success_screen 에서 호출되어 다음 주문 시 깨끗한 상태로 진입.
  void clear() {
    state = const [];
  }

  // ── 특정 메뉴의 현재 담긴 수량 조회 ────────────────────────
  // 메뉴 목록 화면에서 "이 메뉴가 몇 개 담겨 있는지" 표시할 때 사용
  int quantityOf(String menuId) {
    // firstWhere는 없으면 예외를 던지므로, try-catch 대신 직접 검색
    for (final cartItem in state) {
      if (cartItem.item.id == menuId) return cartItem.quantity;
    }
    return 0; // 담기지 않은 메뉴면 0 반환
  }

  // ── 장바구니 총 금액 ─────────────────────────────────────
  // 모든 항목의 subtotal 합산
  int get totalPrice =>
      state.fold(0, (sum, cartItem) => sum + cartItem.subtotal);

  // ── 장바구니 총 수량 ─────────────────────────────────────
  // 하단 배지나 "X개 담음" 표시에 사용
  int get totalCount =>
      state.fold(0, (sum, cartItem) => sum + cartItem.quantity);
}

// ── cartProvider: 앱 전역에서 접근하는 Provider 인스턴스 ────
//
// 사용 방법:
//   - 장바구니 항목 읽기: ref.watch(cartProvider)
//   - 총 금액 읽기:       ref.watch(cartProvider.notifier).totalPrice
//   - 담기:               ref.read(cartProvider.notifier).addItem(item)
//   - 수량 감소:          ref.read(cartProvider.notifier).decreaseItem(id)
//   - 제거:               ref.read(cartProvider.notifier).removeItem(id)
//
// 사용 화면:
//   - CU-16 menu_screen.dart → 담기/수량 변경/제거 조작 + UI 반영
//   - CU-20 group_order_screen.dart (안태환 담당) → 장바구니 내용 읽기
//   - CU-21 payment_screen.dart (우현호 담당) → 총 금액, 완료 후 clear() 호출
final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);
