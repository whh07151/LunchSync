"use client";

import { useCallback, useEffect, useState } from "react";

// pos_memo §6-2 — 영업 상태(영업중/마감) 표시. localStorage 식당별 키.
const STORAGE_KEY = (rid: string) => `ls_pos_open_${rid}`;

export function useShopStatus(restaurantId: string | null) {
  const [open, setOpen] = useState<boolean>(true);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (!restaurantId || typeof window === "undefined") {
      setReady(true);
      return;
    }
    const raw = window.localStorage.getItem(STORAGE_KEY(restaurantId));
    if (raw === "0") setOpen(false);
    else setOpen(true);
    setReady(true);
  }, [restaurantId]);

  const setShopOpen = useCallback(
    (next: boolean) => {
      setOpen(next);
      if (!restaurantId || typeof window === "undefined") return;
      window.localStorage.setItem(STORAGE_KEY(restaurantId), next ? "1" : "0");
    },
    [restaurantId]
  );

  const toggle = useCallback(() => setShopOpen(!open), [open, setShopOpen]);

  return { open, ready, setShopOpen, toggle };
}
