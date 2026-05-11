"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  createReservation as apiCreateReservation,
  deleteReservation as apiDeleteReservation,
  listReservations as apiListReservations,
  updateReservationStatus as apiUpdateStatus,
} from "@/lib/api/reservations";
import type {
  CreateReservationPayload,
  ReservationStatus,
  RemoteReservation,
} from "@/lib/api/reservations";

// ══════════════════════════════════════════════════════════
// 파일 역할: 예약/웨이팅 상태 관리 훅
//
// 동작 방식 (2026-05-14 백엔드 연동):
//   - mount 시 GET /pos/reservations/:restaurantId 시도 → 백엔드 모드 진입.
//   - 실패 시 localStorage 폴백.
//   - 모든 mutation 은 백엔드 우선 호출, 실패 시 로컬에만 반영.
//
// 외부 시그니처는 기존 예약 페이지가 그대로 사용하도록 유지.
// ══════════════════════════════════════════════════════════

const STORAGE_KEY = (rid: string) => `ls_pos_reservations_${rid}`;

export type { ReservationStatus };
export type ReservationKind = "WAITING" | "RESERVATION";

// 기존 페이지 호환용 — useReservations 외부 시그니처는 Reservation 인터페이스 유지
export interface Reservation {
  id: string;
  kind: ReservationKind;
  customerName: string;
  partySize: number;
  scheduledAt?: string;
  note?: string;
  createdAt: string;
  status: ReservationStatus;
}

function toReservation(r: RemoteReservation): Reservation {
  return {
    id: r.id,
    kind: r.kind,
    customerName: r.customerName,
    partySize: r.partySize,
    scheduledAt: r.scheduledAt ?? undefined,
    note: r.note ?? undefined,
    status: r.status,
    createdAt: r.createdAt,
  };
}

function newId(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID();
  }
  return `r-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
}

export function useReservations(restaurantId: string | null) {
  const [list, setList] = useState<Reservation[]>([]);
  const [ready, setReady] = useState(false);
  const usingBackendRef = useRef(false);

  // ── 초기 로드 ─────────────────────────────────────────
  useEffect(() => {
    if (!restaurantId) {
      setReady(true);
      return;
    }
    let cancelled = false;
    (async () => {
      const remote = await apiListReservations(restaurantId);
      if (cancelled) return;
      if (remote !== null) {
        usingBackendRef.current = true;
        setList(remote.map(toReservation));
        setReady(true);
        return;
      }
      // localStorage 폴백
      usingBackendRef.current = false;
      if (typeof window !== "undefined") {
        try {
          const raw = window.localStorage.getItem(STORAGE_KEY(restaurantId));
          if (raw) {
            const parsed = JSON.parse(raw) as Reservation[];
            if (Array.isArray(parsed)) setList(parsed);
          }
        } catch {
          // ignore
        }
      }
      setReady(true);
    })();
    return () => {
      cancelled = true;
    };
  }, [restaurantId]);

  const persist = useCallback(
    (next: Reservation[]) => {
      setList(next);
      if (!restaurantId || typeof window === "undefined") return;
      try {
        window.localStorage.setItem(
          STORAGE_KEY(restaurantId),
          JSON.stringify(next),
        );
      } catch {
        // ignore
      }
    },
    [restaurantId],
  );

  const add = useCallback(
    async (input: Omit<Reservation, "id" | "createdAt" | "status">) => {
      if (usingBackendRef.current && restaurantId) {
        const payload: CreateReservationPayload = {
          kind: input.kind,
          customerName: input.customerName,
          partySize: input.partySize,
          scheduledAt: input.scheduledAt,
          note: input.note,
        };
        const remote = await apiCreateReservation(restaurantId, payload);
        if (remote) {
          const r = toReservation(remote);
          persist([...list, r]);
          return r;
        }
      }
      // 로컬 폴백
      const r: Reservation = {
        ...input,
        id: newId(),
        createdAt: new Date().toISOString(),
        status: "OPEN",
      };
      persist([...list, r]);
      return r;
    },
    [persist, list, restaurantId],
  );

  const updateStatus = useCallback(
    async (id: string, status: ReservationStatus) => {
      if (usingBackendRef.current) {
        const remote = await apiUpdateStatus(id, status);
        if (remote) {
          persist(
            list.map((r) => (r.id === id ? toReservation(remote) : r)),
          );
          return;
        }
      }
      persist(list.map((r) => (r.id === id ? { ...r, status } : r)));
    },
    [persist, list],
  );

  const remove = useCallback(
    async (id: string) => {
      if (usingBackendRef.current) {
        const ok = await apiDeleteReservation(id);
        if (!ok) return; // 백엔드 실패 시 변경 없음
      }
      persist(list.filter((r) => r.id !== id));
    },
    [persist, list],
  );

  const stats = useMemo(() => {
    const open = list.filter((r) => r.status === "OPEN");
    return {
      waiting: open.filter((r) => r.kind === "WAITING").length,
      reservations: open.filter((r) => r.kind === "RESERVATION").length,
    };
  }, [list]);

  return { list, ready, stats, add, updateStatus, remove };
}
