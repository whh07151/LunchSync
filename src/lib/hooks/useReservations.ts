"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

// pos_memo §6-3, §8-2 — 웨이팅 / 예약 관리.
// 백엔드 모델 미구현 → localStorage. 백엔드 합의 후 API 교체.

const STORAGE_KEY = (rid: string) => `ls_pos_reservations_${rid}`;

export type ReservationKind = "WAITING" | "RESERVATION";

export interface Reservation {
  id: string;
  kind: ReservationKind;
  customerName: string;
  partySize: number;
  scheduledAt?: string; // RESERVATION 만 (예약 시각)
  note?: string;
  createdAt: string;
  status: "OPEN" | "SEATED" | "CANCELLED";
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

  useEffect(() => {
    if (!restaurantId || typeof window === "undefined") {
      setReady(true);
      return;
    }
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY(restaurantId));
      if (raw) {
        const parsed = JSON.parse(raw) as Reservation[];
        if (Array.isArray(parsed)) setList(parsed);
      }
    } catch {
      // ignore
    }
    setReady(true);
  }, [restaurantId]);

  const persist = useCallback(
    (next: Reservation[]) => {
      setList(next);
      if (!restaurantId || typeof window === "undefined") return;
      try {
        window.localStorage.setItem(
          STORAGE_KEY(restaurantId),
          JSON.stringify(next)
        );
      } catch {
        // ignore
      }
    },
    [restaurantId]
  );

  const add = useCallback(
    (input: Omit<Reservation, "id" | "createdAt" | "status">) => {
      const r: Reservation = {
        ...input,
        id: newId(),
        createdAt: new Date().toISOString(),
        status: "OPEN",
      };
      persist([...list, r]);
      return r;
    },
    [persist, list]
  );

  const updateStatus = useCallback(
    (id: string, status: Reservation["status"]) => {
      persist(list.map((r) => (r.id === id ? { ...r, status } : r)));
    },
    [persist, list]
  );

  const remove = useCallback(
    (id: string) => persist(list.filter((r) => r.id !== id)),
    [persist, list]
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
