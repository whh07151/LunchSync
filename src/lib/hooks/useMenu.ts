"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { DEMO_CATEGORIES, DEMO_MENU } from "@/lib/data/demoMenu";

// pos_memo §4 (POS 권한 — 메뉴/가격 수정), §9 (메뉴 관리 페이지)
// 백엔드 메뉴 수정 API 미구현 → localStorage 식당별 저장.
// DEMO_MENU를 시드로 두고, 사용자 수정/추가/삭제는 override layer로 누적.
// 백엔드 합의(POS_DEV_LOG 협의 #7) 후 GET/PATCH/POST 호출로 교체.

const STORAGE_KEY = (rid: string) => `ls_pos_menu_${rid}`;

export interface MenuItem {
  id: string;
  name: string;
  price: number;
  category: string;
  soldOut?: boolean;
}

function newMenuId(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID();
  }
  return `m-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
}

function seedFromDemo(): MenuItem[] {
  return DEMO_MENU.map((m) => ({
    id: m.id,
    name: m.name,
    price: m.price,
    category: m.category,
    soldOut: false,
  }));
}

export function useMenu(restaurantId: string | null) {
  const [items, setItems] = useState<MenuItem[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (!restaurantId || typeof window === "undefined") {
      setReady(true);
      return;
    }
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY(restaurantId));
      if (raw) {
        const parsed = JSON.parse(raw) as MenuItem[];
        if (Array.isArray(parsed) && parsed.length > 0) {
          setItems(parsed);
          setReady(true);
          return;
        }
      }
    } catch {
      // ignore
    }
    setItems(seedFromDemo());
    setReady(true);
  }, [restaurantId]);

  const persist = useCallback(
    (next: MenuItem[]) => {
      setItems(next);
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

  const addItem = useCallback(
    (input: Omit<MenuItem, "id">) => {
      persist([...items, { ...input, id: newMenuId() }]);
    },
    [persist, items]
  );

  const updateItem = useCallback(
    (id: string, patch: Partial<Omit<MenuItem, "id">>) => {
      persist(items.map((m) => (m.id === id ? { ...m, ...patch } : m)));
    },
    [persist, items]
  );

  const deleteItem = useCallback(
    (id: string) => {
      persist(items.filter((m) => m.id !== id));
    },
    [persist, items]
  );

  const toggleSoldOut = useCallback(
    (id: string) => {
      persist(
        items.map((m) =>
          m.id === id ? { ...m, soldOut: !m.soldOut } : m
        )
      );
    },
    [persist, items]
  );

  const resetToDemo = useCallback(() => {
    persist(seedFromDemo());
  }, [persist]);

  // 사용자 수정 카테고리 + 기본 카테고리 합쳐서 정렬 (전체는 항상 첫번째)
  const categories = useMemo(() => {
    const fromItems = Array.from(new Set(items.map((m) => m.category)));
    const merged = ["전체", ...new Set([...DEMO_CATEGORIES.slice(1), ...fromItems])];
    return merged;
  }, [items]);

  return {
    items,
    ready,
    categories,
    addItem,
    updateItem,
    deleteItem,
    toggleSoldOut,
    resetToDemo,
  };
}
