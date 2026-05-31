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

// POS-09 (2026-05-31) — 환불 시뮬레이션.
//   OW-10 이 백엔드에 POST /pos/orders/:id/refund-sim 라우트를 추가 중.
//   라우트 명세는 cancelOrder 와 동일한 응답 형태로 합의됨:
//     body : { reason: string }
//     resp : { success: true, orderId, status: 'REFUNDED', updatedAt }
//   여기서는 cancel 과 동일한 형태로 받아 dashboard/orders 페이지가 새로
//   고침 후 REFUNDED 칩으로 표시할 수 있도록 한다.
//
// 실제 Toss 결제 환불은 미연결 — 백엔드가 DB status 만 REFUNDED 로 갱신.
// 캡스톤 시연 시나리오에서 사장이 "환불 처리"를 누른 사실을 기록하는 용도.
export async function refundOrderSim(
  orderId: string,
  reason: string,
): Promise<{
  success: boolean;
  orderId: string;
  status: OrderStatus;
  updatedAt: string;
}> {
  return apiRequest(`/pos/orders/${orderId}/refund-sim`, {
    method: "POST",
    body: { reason },
  });
}

// 단일 주문 상세 — POS-13 화면용. 백엔드는 GET /orders/:id (DTO §10).
export async function getOrderById(orderId: string): Promise<Order> {
  return apiRequest<Order>(`/orders/${orderId}`);
}

// ══════════════════════════════════════════════════════════
// 2026-05-31 WOW#2: 사장 라이브 카메라 1장
//
// 흐름:
//   - "조리 완료" 옆 카메라 아이콘 탭 → input[capture=environment] 으로 단말
//     카메라 즉시 호출 → File 객체 획득 → 이 함수가 multipart/form-data 로
//     백엔드에 전송 → 백엔드가 Supabase Storage 업로드 + URL 저장.
//   - 손님 어플은 3초 폴링 도중 completionPhotoUrl 을 받으면 페이드인.
//
// 왜 백엔드 경유?
//   · supabase-js 클라이언트 의존성 없이 동작 (서비스 단순화)
//   · service_role 키가 클라이언트에 노출되지 않아 안전
//   · 매장 권한(assertPosAccessTo) 을 백엔드가 검증 → 다른 매장 사진 차단
// ══════════════════════════════════════════════════════════

import {
  ApiError,
  getAccessToken,
} from "@/lib/api/client";

export interface CompletionPhotoUploadResult {
  id: string;
  completionPhotoUrl: string;
  updatedAt: string;
}

/// 조리 완료 사진 업로드.
/// apiRequest 는 JSON body 전제라 multipart 는 직접 fetch 로 처리.
export async function uploadCompletionPhoto(
  orderId: string,
  photo: File,
): Promise<CompletionPhotoUploadResult> {
  const baseUrl =
    process.env.NEXT_PUBLIC_BACKEND_BASE_URL ?? "http://localhost:3000/api";
  const url = `${baseUrl.replace(/\/$/, "")}/pos/orders/${orderId}/completion-photo`;

  const headers: Record<string, string> = {};
  const token = getAccessToken();
  if (token) headers["Authorization"] = `Bearer ${token}`;
  // Content-Type 은 브라우저가 boundary 포함해서 자동 설정 → 명시 X.

  const form = new FormData();
  form.append("photo", photo);

  let res: Response;
  try {
    res = await fetch(url, { method: "POST", headers, body: form });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "네트워크 오류";
    throw new ApiError(msg, "NETWORK_ERROR", 0);
  }

  const text = await res.text();
  let parsed: unknown = null;
  if (text) {
    try {
      parsed = JSON.parse(text);
    } catch {
      throw new ApiError("응답 파싱 실패", "PARSE_ERROR", res.status);
    }
  }

  if (!res.ok) {
    const err = parsed as { error?: { code?: string; message?: string } } | null;
    if (err?.error?.message) {
      throw new ApiError(
        err.error.message,
        err.error.code ?? "HTTP_ERROR",
        res.status,
      );
    }
    throw new ApiError(
      `사진 업로드 실패 (${res.status})`,
      res.status === 401 ? "UNAUTHORIZED" : "HTTP_ERROR",
      res.status,
    );
  }

  const body = parsed as
    | { success: true; data: CompletionPhotoUploadResult }
    | { success: false; error: { code: string; message: string } }
    | null;
  if (!body) {
    throw new ApiError("빈 응답", "EMPTY_BODY", res.status);
  }
  if (!body.success) {
    throw new ApiError(body.error.message, body.error.code, res.status);
  }
  return body.data;
}
