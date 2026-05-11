// ══════════════════════════════════════════════════════════
// 파일 역할: 점주앱/POS 좌석 모듈 API 클라이언트
//
// 백엔드 매핑 (LunchSync NestJS PosSeatsController, 2026-05-14 신설):
//   GET    /api/pos/seats/:restaurantId   → list
//   POST   /api/pos/seats/:restaurantId   → create (label optional)
//   PATCH  /api/pos/seats/item/:seatId    → update
//   DELETE /api/pos/seats/item/:seatId    → delete
//
// 모두 JWT 필요. apiRequest 가 localStorage accessToken 자동 첨부.
// 네트워크/404 등 실패 시 null/false 반환 → useSeats 훅이 localStorage 폴백.
// ══════════════════════════════════════════════════════════

import { apiRequest, ApiError } from "@/lib/api/client";
import type { Seat, SeatItem, SeatStatus } from "@/lib/types";

// 백엔드 응답 — snake_case 가 아니라 camelCase 로 통일됨 (NestJS DTO 측에서 변환)
export interface RemoteSeat {
  id: string;
  restaurantId: string;
  label: string;
  status: SeatStatus;
  startedAt: string | null;
  items: SeatItem[];
  sortOrder: number;
}

export interface UpdateSeatPayload {
  label?: string;
  status?: SeatStatus;
  startedAt?: string | null;
  items?: SeatItem[];
  sortOrder?: number;
}

// 백엔드 응답 → 프론트 Seat 타입으로 변환 (startedAt null/undefined 정리)
function toSeat(r: RemoteSeat): Seat {
  return {
    id: r.id,
    label: r.label,
    status: r.status,
    items: r.items ?? [],
    startedAt: r.startedAt ?? undefined,
  };
}

// 좌석 목록 — 실패 시 null
export async function listSeats(restaurantId: string): Promise<Seat[] | null> {
  try {
    const remote = await apiRequest<RemoteSeat[]>(`/pos/seats/${restaurantId}`);
    return remote.map(toSeat);
  } catch (e) {
    if (e instanceof ApiError) return null;
    return null;
  }
}

// 좌석 추가
export async function createSeat(
  restaurantId: string,
  label?: string,
): Promise<Seat | null> {
  try {
    const remote = await apiRequest<RemoteSeat>(`/pos/seats/${restaurantId}`, {
      method: "POST",
      body: { label },
    });
    return toSeat(remote);
  } catch {
    return null;
  }
}

// 좌석 갱신 (items 변경, 점유/해제 등 단일 PATCH)
export async function updateSeat(
  seatId: string,
  payload: UpdateSeatPayload,
): Promise<Seat | null> {
  try {
    const remote = await apiRequest<RemoteSeat>(`/pos/seats/item/${seatId}`, {
      method: "PATCH",
      body: payload,
    });
    return toSeat(remote);
  } catch {
    return null;
  }
}

// 좌석 삭제 — 점유 중이면 백엔드가 거부
export async function deleteSeat(seatId: string): Promise<boolean> {
  try {
    await apiRequest<{ id: string; deleted: boolean }>(
      `/pos/seats/item/${seatId}`,
      { method: "DELETE" },
    );
    return true;
  } catch {
    return false;
  }
}
