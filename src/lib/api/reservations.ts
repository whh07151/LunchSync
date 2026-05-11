// ══════════════════════════════════════════════════════════
// 파일 역할: POS 예약/웨이팅 모듈 API 클라이언트
//
// 백엔드 매핑 (LunchSync NestJS PosReservationsController, 2026-05-14 신설):
//   GET    /api/pos/reservations/:restaurantId    → list
//   POST   /api/pos/reservations/:restaurantId    → create
//   PATCH  /api/pos/reservations/item/:id/status  → 상태 변경
//   DELETE /api/pos/reservations/item/:id         → 삭제
//
// JWT 필요. 실패 시 null/false 반환 — useReservations 훅 localStorage 폴백.
// ══════════════════════════════════════════════════════════

import { apiRequest, ApiError } from "@/lib/api/client";

export type ReservationKind = "WAITING" | "RESERVATION";
export type ReservationStatus = "OPEN" | "SEATED" | "CANCELLED";

export interface RemoteReservation {
  id: string;
  restaurantId: string;
  kind: ReservationKind;
  customerName: string;
  partySize: number;
  scheduledAt: string | null;
  note: string | null;
  status: ReservationStatus;
  createdAt: string;
}

export interface CreateReservationPayload {
  kind: ReservationKind;
  customerName: string;
  partySize: number;
  scheduledAt?: string;
  note?: string;
}

export async function listReservations(
  restaurantId: string,
): Promise<RemoteReservation[] | null> {
  try {
    return await apiRequest<RemoteReservation[]>(
      `/pos/reservations/${restaurantId}`,
    );
  } catch (e) {
    if (e instanceof ApiError) return null;
    return null;
  }
}

export async function createReservation(
  restaurantId: string,
  payload: CreateReservationPayload,
): Promise<RemoteReservation | null> {
  try {
    return await apiRequest<RemoteReservation>(
      `/pos/reservations/${restaurantId}`,
      { method: "POST", body: payload },
    );
  } catch {
    return null;
  }
}

export async function updateReservationStatus(
  id: string,
  status: ReservationStatus,
): Promise<RemoteReservation | null> {
  try {
    return await apiRequest<RemoteReservation>(
      `/pos/reservations/item/${id}/status`,
      { method: "PATCH", body: { status } },
    );
  } catch {
    return null;
  }
}

export async function deleteReservation(id: string): Promise<boolean> {
  try {
    await apiRequest<{ id: string; deleted: boolean }>(
      `/pos/reservations/item/${id}`,
      { method: "DELETE" },
    );
    return true;
  } catch {
    return false;
  }
}
