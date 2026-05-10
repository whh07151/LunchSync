import { apiRequest } from "@/lib/api/client";
import type { Order, OrderStats, OrderStatus } from "@/lib/types";

// LUNCHSYNC_DTO.md §12, POS_BUILD_GUIDE.md §3
// 진행도 문서(LUNCHSYNC_PROGRESS.md)에는 백엔드 컨트롤러 경로가
//   GET /pos/restaurants/:id/orders 로 적혀있고
// POS_BUILD_GUIDE / DTO 명세에는
//   GET /pos/orders/:restaurantId 로 적혀있어 두 출처가 충돌.
// 우선 POS_BUILD_GUIDE / DTO 명세(공식 명세) 경로를 따른다.
// 실 백엔드와 어긋나면 backend/src/pos/pos.controller.ts 확인 후 이 파일에서 한 곳만 교체.

export async function getOrders(
  restaurantId: string,
  status?: OrderStatus
): Promise<Order[]> {
  return apiRequest<Order[]>(`/pos/orders/${restaurantId}`, {
    query: status ? { status } : undefined,
  });
}

export async function getOrderStats(restaurantId: string): Promise<OrderStats> {
  return apiRequest<OrderStats>(`/pos/orders/${restaurantId}/stats`);
}

export async function updateOrderStatus(
  orderId: string,
  status: OrderStatus
): Promise<{ id: string; status: OrderStatus; updatedAt: string }> {
  return apiRequest(`/pos/orders/${orderId}/status`, {
    method: "PATCH",
    body: { status },
  });
}

export async function cancelOrder(
  orderId: string,
  reason: string
): Promise<{ success: boolean; orderId: string }> {
  return apiRequest(`/pos/orders/${orderId}/cancel`, {
    method: "POST",
    body: { reason },
  });
}

// 단일 주문 상세 — POS-13 화면용. 백엔드는 GET /orders/:id (DTO §10).
export async function getOrderById(orderId: string): Promise<Order> {
  return apiRequest<Order>(`/orders/${orderId}`);
}
