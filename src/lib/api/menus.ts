// ══════════════════════════════════════════════════════════
// 파일 역할: POS 메뉴 CRUD API 클라이언트
//
// 백엔드 매핑 (LunchSync NestJS PosMenusController, 2026-05-12 신설):
//   GET    /api/pos/menus/:restaurantId   → list
//   POST   /api/pos/menus/:restaurantId   → create
//   PATCH  /api/pos/menus/item/:id        → update (품절 토글 포함)
//   DELETE /api/pos/menus/item/:id        → delete
//
// 모두 JWT 필요. apiRequest 가 localStorage accessToken 자동 첨부.
// 네트워크/404 등 실패 시 null/false 반환 — useMenu 훅이 localStorage 폴백 진입.
// ══════════════════════════════════════════════════════════

import { apiRequest, ApiError } from "@/lib/api/client";

export interface RemoteMenu {
  id: string;
  restaurantId: string;
  name: string;
  price: number;
  category: string | null;
  description: string | null;
  imageUrl: string | null;
  isAvailable: boolean;
}

export interface CreateMenuPayload {
  name: string;
  price: number;
  category?: string;
  description?: string;
  imageUrl?: string;
}

export interface UpdateMenuPayload {
  name?: string;
  price?: number;
  category?: string;
  description?: string;
  imageUrl?: string;
  isAvailable?: boolean;
}

/// 메뉴 목록 — 백엔드 호출 실패(네트워크/404/401) 시 null 반환.
export async function listMenus(restaurantId: string): Promise<RemoteMenu[] | null> {
  try {
    return await apiRequest<RemoteMenu[]>(`/pos/menus/${restaurantId}`);
  } catch (e) {
    if (e instanceof ApiError) return null;
    return null;
  }
}

/// 메뉴 추가 — 실패 시 null.
export async function createMenu(
  restaurantId: string,
  payload: CreateMenuPayload
): Promise<RemoteMenu | null> {
  try {
    return await apiRequest<RemoteMenu>(`/pos/menus/${restaurantId}`, {
      method: "POST",
      body: payload,
    });
  } catch {
    return null;
  }
}

/// 메뉴 수정 / 품절 토글 — 실패 시 null.
export async function updateMenu(
  menuId: string,
  payload: UpdateMenuPayload
): Promise<RemoteMenu | null> {
  try {
    return await apiRequest<RemoteMenu>(`/pos/menus/item/${menuId}`, {
      method: "PATCH",
      body: payload,
    });
  } catch {
    return null;
  }
}

/// 메뉴 삭제 — 성공 시 true, 실패 시 false (이미 주문에 사용된 메뉴는 백엔드가 거절).
export async function deleteMenu(menuId: string): Promise<boolean> {
  try {
    await apiRequest<{ id: string; deleted: boolean }>(
      `/pos/menus/item/${menuId}`,
      { method: "DELETE" }
    );
    return true;
  } catch {
    return false;
  }
}
