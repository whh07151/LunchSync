"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { Seat, SeatItem } from "@/lib/types";
import {
  createSeat as apiCreateSeat,
  deleteSeat as apiDeleteSeat,
  listSeats as apiListSeats,
  updateSeat as apiUpdateSeat,
} from "@/lib/api/seats";

// ══════════════════════════════════════════════════════════
// 파일 역할: 좌석 상태 관리 훅
//
// 동작 방식 (2026-05-14 백엔드 연동):
//   1. mount 시 GET /pos/seats/:restaurantId 조회 → 성공 시 백엔드 모드.
//   2. 실패하면 localStorage 폴백 (네트워크 단절/미로그인 환경에서도 데모 가능).
//   3. 모든 mutation 은 백엔드 PATCH/POST/DELETE 호출 → 성공 시 응답으로 상태 동기화.
//      실패 시 로컬 상태에만 반영하고 localStorage 에 백업.
//
// 외부 시그니처는 기존 좌석 페이지가 그대로 사용하도록 유지.
// ══════════════════════════════════════════════════════════

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
  // 백엔드 사용 가능 여부 — false 면 모든 mutation 이 localStorage 만 갱신
  const usingBackendRef = useRef(false);

  // ── 초기 로드 ─────────────────────────────────────────
  useEffect(() => {
    if (!restaurantId) {
      setReady(true);
      return;
    }

    let cancelled = false;
    (async () => {
      // 1) 백엔드 시도
      const remote = await apiListSeats(restaurantId);
      if (cancelled) return;

      if (remote !== null) {
        usingBackendRef.current = true;
        // 첫 진입이고 좌석이 비어 있으면 기본 8개를 백엔드에 자동 생성
        if (remote.length === 0) {
          const created: Seat[] = [];
          for (let i = 0; i < DEFAULT_COUNT; i += 1) {
            const s = await apiCreateSeat(restaurantId, `${i + 1}번`);
            if (s) created.push(s);
          }
          if (created.length > 0) {
            setSeats(created);
            setReady(true);
            return;
          }
          // 그래도 빈 배열 — 로컬 폴백
        } else {
          setSeats(remote);
          setReady(true);
          return;
        }
      }

      // 2) 백엔드 실패 → localStorage 폴백
      usingBackendRef.current = false;
      if (typeof window !== "undefined") {
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
      }
      setSeats(makeInitial(DEFAULT_COUNT));
      setReady(true);
    })();

    return () => {
      cancelled = true;
    };
  }, [restaurantId]);

  // ── 로컬 영속화 + state 갱신 (백엔드 모드에서도 안전 백업) ──
  const persist = useCallback(
    (next: Seat[]) => {
      setSeats(next);
      if (!restaurantId || typeof window === "undefined") return;
      try {
        window.localStorage.setItem(
          STORAGE_KEY(restaurantId),
          JSON.stringify(next),
        );
      } catch {
        // 저장 실패는 무시 (할당 초과 등)
      }
    },
    [restaurantId],
  );

  // 백엔드 모드에서 단건 patch — 성공 시 응답으로 해당 좌석 갱신
  const patchSeatRemote = useCallback(
    async (seatId: string, next: Seat) => {
      if (!usingBackendRef.current) return;
      const updated = await apiUpdateSeat(seatId, {
        label: next.label,
        status: next.status,
        startedAt: next.startedAt ?? null,
        items: next.items,
      });
      if (updated) {
        // 응답으로 한번 더 동기화 (서버가 보낸 값이 진실)
        setSeats((prev) =>
          prev.map((s) => (s.id === seatId ? updated : s)),
        );
      }
    },
    [],
  );

  const addSeat = useCallback(async () => {
    if (seats.length >= MAX_COUNT) return;
    if (usingBackendRef.current && restaurantId) {
      const created = await apiCreateSeat(
        restaurantId,
        `${seats.length + 1}번`,
      );
      if (created) {
        persist([...seats, created]);
        return;
      }
    }
    persist([...seats, buildSeat(seats.length)]);
  }, [persist, restaurantId, seats]);

  const removeLastSeat = useCallback(async () => {
    if (seats.length <= MIN_COUNT) return;
    const last = seats[seats.length - 1];
    if (last.status === "occupied") return; // 점유 좌석 보호
    if (usingBackendRef.current) {
      const ok = await apiDeleteSeat(last.id);
      if (!ok) return; // 백엔드 실패 시 변경 없음
    }
    persist(seats.slice(0, -1));
  }, [persist, seats]);

  const addItem = useCallback(
    (seatId: string, item: AddItemArgs) => {
      const now = new Date().toISOString();
      const next = seats.map((s) => {
        if (s.id !== seatId) return s;
        const existing = s.items.find((x) => x.menuId === item.menuId);
        let items: SeatItem[];
        if (existing) {
          items = s.items.map((x) =>
            x.menuId === item.menuId ? { ...x, quantity: x.quantity + 1 } : x,
          );
        } else {
          items = [...s.items, { ...item, quantity: 1, addedAt: now }];
        }
        return {
          ...s,
          status: "occupied" as const,
          startedAt: s.startedAt ?? now,
          items,
        };
      });
      persist(next);
      const target = next.find((s) => s.id === seatId);
      if (target) void patchSeatRemote(seatId, target);
    },
    [patchSeatRemote, persist, seats],
  );

  const decreaseItem = useCallback(
    (seatId: string, menuId: string) => {
      const next = seats.map((s) => {
        if (s.id !== seatId) return s;
        const items = s.items
          .map((x) =>
            x.menuId === menuId ? { ...x, quantity: x.quantity - 1 } : x,
          )
          .filter((x) => x.quantity > 0);
        if (items.length === 0) {
          return {
            ...s,
            items,
            status: "empty" as const,
            startedAt: undefined,
          };
        }
        return { ...s, items };
      });
      persist(next);
      const target = next.find((s) => s.id === seatId);
      if (target) void patchSeatRemote(seatId, target);
    },
    [patchSeatRemote, persist, seats],
  );

  const removeItem = useCallback(
    (seatId: string, menuId: string) => {
      const next = seats.map((s) => {
        if (s.id !== seatId) return s;
        const items = s.items.filter((x) => x.menuId !== menuId);
        if (items.length === 0) {
          return {
            ...s,
            items,
            status: "empty" as const,
            startedAt: undefined,
          };
        }
        return { ...s, items };
      });
      persist(next);
      const target = next.find((s) => s.id === seatId);
      if (target) void patchSeatRemote(seatId, target);
    },
    [patchSeatRemote, persist, seats],
  );

  const closeSeat = useCallback(
    (seatId: string) => {
      const next = seats.map((s) =>
        s.id === seatId
          ? {
              ...s,
              items: [],
              status: "empty" as const,
              startedAt: undefined,
            }
          : s,
      );
      persist(next);
      const target = next.find((s) => s.id === seatId);
      if (target) void patchSeatRemote(seatId, target);
    },
    [patchSeatRemote, persist, seats],
  );

  const stats = useMemo(() => {
    const occupied = seats.filter((s) => s.status === "occupied").length;
    const total = seats.length;
    const totalRevenue = seats.reduce(
      (acc, s) =>
        acc + s.items.reduce((a, it) => a + it.price * it.quantity, 0),
      0,
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
