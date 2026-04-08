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
    required this.item,     // 메뉴 정보 (이름, 가격 등)
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

  /// Provider 초기 상태: 빈 장바구니
  @override
  List<CartItem> build() => const [];

  // ── 메뉴 담기 (수량 1 추가) ─────────────────────────────
  // 이미 담긴 메뉴면 수량 +1, 처음 담는 메뉴면 새 항목으로 추가
  void addItem(MenuItem item) {
    // 같은 id의 항목이 이미 있는지 확인
    final index = state.indexWhere((e) => e.item.id == item.id);

    if (index >= 0) {
      // 이미 있는 메뉴: 수량만 1 증가
      // Riverpod 상태는 불변이므로 기존 리스트를 직접 수정하지 않고 새 리스트 생성
      final updated = [...state];
      updated[index] = updated[index].copyWith(
        quantity: updated[index].quantity + 1,
      );
      state = List.unmodifiable(updated);
    } else {
      // 처음 담는 메뉴: 수량 1로 새 항목 추가
      state = List.unmodifiable([...state, CartItem(item: item, quantity: 1)]);
    }
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
    state = List.unmodifiable(
      state.where((e) => e.item.id != menuId).toList(),
    );
  }

  // ── 장바구니 전체 비우기 ────────────────────────────────
  // 주문 완료 또는 세션 종료 시 호출
  // TODO: CU-21(결제 완료, 우현호 담당) 완성 후 결제 완료 화면에서 호출 연결
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
final cartProvider =
    NotifierProvider<CartNotifier, List<CartItem>>(CartNotifier.new);