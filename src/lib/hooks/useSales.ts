"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { Sale } from "@/lib/types";

// pos_memo.md §2 — 결제 수단별 관리 + 하루 매출.
// 백엔드 매출 모델 미정 → 식당 ID별 localStorage에 누적.
// 백엔드 합의(POS_DEV_LOG 협의 #10) 후 동일 시그니처로 API 교체.

const STORAGE_KEY = (restaurantId: string) => `ls_pos_sales_${restaurantId}`;

function isSameDay(iso: string, date: Date): boolean {
  const d = new Date(iso);
  return (
    d.getFullYear() === date.getFullYear() &&
    d.getMonth() === date.getMonth() &&
    d.getDate() === date.getDate()
  );
}

function newId(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID();
  }
  return `sale-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

export function useSales(restaurantId: string | null) {
  const [sales, setSales] = useState<Sale[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (!restaurantId || typeof window === "undefined") {
      setReady(true);
      return;
    }
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY(restaurantId));
      if (raw) {
        const parsed = JSON.parse(raw) as Sale[];
        if (Array.isArray(parsed)) setSales(parsed);
      }
    } catch {
      // 무시
    }
    setReady(true);
  }, [restaurantId]);

  const persist = useCallback(
    (next: Sale[]) => {
      setSales(next);
      if (!restaurantId || typeof window === "undefined") return;
      try {
        window.localStorage.setItem(
          STORAGE_KEY(restaurantId),
          JSON.stringify(next)
        );
      } catch {
        // 저장 실패 무시
      }
    },
    [restaurantId]
  );

  const recordSale = useCallback(
    (input: Omit<Sale, "id" | "closedAt"> & { closedAt?: string }): Sale => {
      const finalized: Sale = {
        ...input,
        id: newId(),
        closedAt: input.closedAt ?? new Date().toISOString(),
      };
      persist([...sales, finalized]);
      return finalized;
    },
    [persist, sales]
  );

  const todayStats = useMemo(() => {
    const today = new Date();
    const todays = sales.filter((s) => isSameDay(s.closedAt, today));
    const card = todays.filter((s) => s.method === "CARD");
    const cash = todays.filter((s) => s.method === "CASH");
    const sum = (arr: Sale[]) => arr.reduce((a, b) => a + b.total, 0);
    return {
      total: sum(todays),
      count: todays.length,
      card: { total: sum(card), count: card.length },
      cash: { total: sum(cash), count: cash.length },
    };
  }, [sales]);

  return { sales, ready, recordSale, todayStats };
}
