"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { Seat, SeatItem } from "@/lib/types";

// pos_memo.md §2 — 좌석은 백엔드 모델 미정.
// 현재 구현은 localStorage 전용 (식당 ID별 분리 키).
// 백엔드 합의 후 useSeats 내부의 read/write 구현만 API 호출로 교체하면 외부 시그니처 동일.

const STORAGE_KEY = (restaurantId: string) => `ls_pos_seats_${restaurantId}`;
const DEFAULT_COUNT = 8;
const MIN_COUNT = 1;
const MAX_COUNT = 32;

function buildSeat(index: number): Seat {
  return {
    id: `T${index + 1}`,
    label: `${index + 1}번`,
    status: "empty",
    items: [],
  };
}

function makeInitial(count: number): Seat[] {
  return Array.from({ length: count }, (_, i) => buildSeat(i));
}

interface AddItemArgs {
  menuId: string;
  name: string;
  price: number;
}

export function useSeats(restaurantId: string | null) {
  const [seats, setSeats] = useState<Seat[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (!restaurantId || typeof window === "undefined") {
      setReady(true);
      return;
    }
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY(restaurantId));
      if (raw) {
        const parsed = JSON.parse(raw) as Seat[];
        if (Array.isArray(parsed) && parsed.length > 0) {
          setSeats(parsed);
          setReady(true);
          return;
        }
      }
    } catch {
      // 파싱 실패 → 초기화
    }
    setSeats(makeInitial(DEFAULT_COUNT));
    setReady(true);
  }, [restaurantId]);

  const persist = useCallback(
    (next: Seat[]) => {
      setSeats(next);
      if (!restaurantId || typeof window === "undefined") return;
      try {
        window.localStorage.setItem(
          STORAGE_KEY(restaurantId),
          JSON.stringify(next)
        );
      } catch {
        // 저장 실패는 무시 (할당 초과 등)
      }
    },
    [restaurantId]
  );

  const addSeat = useCallback(() => {
    if (seats.length >= MAX_COUNT) return;
    persist([...seats, buildSeat(seats.length)]);
  }, [persist, seats]);

  const removeLastSeat = useCallback(() => {
    if (seats.length <= MIN_COUNT) return;
    // 사용중인 좌석은 보호
    const last = seats[seats.length - 1];
    if (last.status === "occupied") return;
    persist(seats.slice(0, -1));
  }, [persist, seats]);

  const addItem = useCallback(
    (seatId: string, item: AddItemArgs) => {
      const now = new Date().toISOString();
      persist(
        seats.map((s) => {
          if (s.id !== seatId) return s;
          const existing = s.items.find((x) => x.menuId === item.menuId);
          let items: SeatItem[];
          if (existing) {
            items = s.items.map((x) =>
              x.menuId === item.menuId
                ? { ...x, quantity: x.quantity + 1 }
                : x
            );
          } else {
            items = [...s.items, { ...item, quantity: 1, addedAt: now }];
          }
          return {
            ...s,
            status: "occupied",
            startedAt: s.startedAt ?? now,
            items,
          };
        })
      );
    },
    [persist, seats]
  );

  const decreaseItem = useCallback(
    (seatId: string, menuId: string) => {
      persist(
        seats.map((s) => {
          if (s.id !== seatId) return s;
          const items = s.items
            .map((x) =>
              x.menuId === menuId ? { ...x, quantity: x.quantity - 1 } : x
            )
            .filter((x) => x.quantity > 0);
          // 모두 비면 상태 자동 정리
          if (items.length === 0) {
            return { ...s, items, status: "empty" as const, startedAt: undefined };
          }
          return { ...s, items };
        })
      );
    },
    [persist, seats]
  );

  const removeItem = useCallback(
    (seatId: string, menuId: string) => {
      persist(
        seats.map((s) => {
          if (s.id !== seatId) return s;
          const items = s.items.filter((x) => x.menuId !== menuId);
          if (items.length === 0) {
            return { ...s, items, status: "empty" as const, startedAt: undefined };
          }
          return { ...s, items };
        })
      );
    },
    [persist, seats]
  );

  const closeSeat = useCallback(
    (seatId: string) => {
      persist(
        seats.map((s) =>
          s.id === seatId
            ? { ...s, items: [], status: "empty" as const, startedAt: undefined }
            : s
        )
      );
    },
    [persist, seats]
  );

  const stats = useMemo(() => {
    const occupied = seats.filter((s) => s.status === "occupied").length;
    const total = seats.length;
    const totalRevenue = seats.reduce(
      (acc, s) =>
        acc + s.items.reduce((a, it) => a + it.price * it.quantity, 0),
      0
    );
    return { total, occupied, empty: total - occupied, totalRevenue };
  }, [seats]);

  return {
    seats,
    ready,
    stats,
    addSeat,
    removeLastSeat,
    addItem,
    decreaseItem,
    removeItem,
    closeSeat,
  };
}

export function seatTotal(seat: Seat): number {
  return seat.items.reduce((a, it) => a + it.price * it.quantity, 0);
}

export function seatItemCount(seat: Seat): number {
  return seat.items.reduce((a, it) => a + it.quantity, 0);
}
