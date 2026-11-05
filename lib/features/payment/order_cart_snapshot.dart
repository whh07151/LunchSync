import 'dart:convert';

/// Checkout items belong to one order; they must never clear an unrelated cart.
class OrderCartSnapshot {
  const OrderCartSnapshot({required this.orderId, required this.items});

  final String orderId;
  final List<({String menuItemId, int quantity})> items;

  static String storageKey(String orderId) => 'ls_order_items:$orderId';

  String encode() => jsonEncode({
    'orderId': orderId,
    'items': items
        .map((i) => {'menuItemId': i.menuItemId, 'quantity': i.quantity})
        .toList(),
  });

  static OrderCartSnapshot? decode(String? raw, String expectedOrderId) {
    if (raw == null || expectedOrderId.isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> ||
          data['orderId'] != expectedOrderId ||
          data['items'] is! List) {
        return null;
      }
      final items = <({String menuItemId, int quantity})>[];
      for (final item in data['items'] as List) {
        if (item is! Map<String, dynamic>) return null;
        final id = item['menuItemId'];
        final qty = item['quantity'];
        if (id is! String ||
            id.isEmpty ||
            qty is! int ||
            qty <= 0 ||
            qty > 999) {
          return null;
        }
        items.add((menuItemId: id, quantity: qty));
      }
      return items.isEmpty
          ? null
          : OrderCartSnapshot(
              orderId: expectedOrderId,
              items: List.unmodifiable(items),
            );
    } catch (_) {
      return null;
    }
  }
}
