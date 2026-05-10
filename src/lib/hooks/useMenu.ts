"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { DEMO_CATEGORIES, DEMO_MENU } from "@/lib/data/demoMenu";
import {
  createMenu as apiCreateMenu,
  deleteMenu as apiDeleteMenu,
  listMenus as apiListMenus,
  updateMenu as apiUpdateMenu,
  type RemoteMenu,
} from "@/lib/api/menus";

// ══════════════════════════════════════════════════════════
// 파일 역할: POS 메뉴 관리 훅
//
// 동작 (2026-05-13 백엔드 연동 후):
//   1. mount 시 GET /pos/menus/:restaurantId 호출
//   2. 성공 → items 백엔드 데이터로 채움 (usingBackend=true)
//   3. 실패(네트워크/401/404 등) → localStorage 폴백 (UI 미리보기)
//   4. add/update/delete/toggleSoldOut 도 동일 분기
//
// 사장앱(우리 owner_home / menu_management_screen)이 메뉴를 추가/수정하면
// 같은 API 를 쓰므로 LSPOS 와 자동 동기화 된다.
//
// 백엔드 응답 ↔ 로컬 타입 매핑:
//   isAvailable=true  ↔  soldOut=false
//   isAvailable=false ↔  soldOut=true
// ══════════════════════════════════════════════════════════

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

function fromRemote(r: RemoteMenu): MenuItem {
  return {
    id: r.id,
    name: r.name,
    price: r.price,
    category: r.category ?? "기타",
    soldOut: !r.isAvailable,
  };
}

function readLocal(restaurantId: string): MenuItem[] {
  if (typeof window === "undefined") return seedFromDemo();
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY(restaurantId));
    if (raw) {
      const parsed = JSON.parse(raw) as MenuItem[];
      if (Array.isArray(parsed) && parsed.length > 0) return parsed;
    }
  } catch {
    // ignore
  }
  return seedFromDemo();
}

function writeLocal(restaurantId: string, items: MenuItem[]): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(
      STORAGE_KEY(restaurantId),
      JSON.stringify(items)
    );
  } catch {
    // ignore
  }
}

export function useMenu(restaurantId: string | null) {
  const [items, setItems] = useState<MenuItem[]>([]);
  const [ready, setReady] = useState(false);
  // 백엔드 연결 상태 — true 면 변경 호출도 백엔드로, false 면 localStorage 만
  const [usingBackend, setUsingBackend] = useState(false);

  useEffect(() => {
    if (!restaurantId || typeof window === "undefined") {
      setReady(true);
      return;
    }
    let cancelled = false;

    (async () => {
      // 1) 백엔드 시도
      const remote = await apiListMenus(restaurantId);
      if (cancelled) return;
      if (remote !== null) {
        setItems(remote.map(fromRemote));
        setUsingBackend(true);
        setReady(true);
        return;
      }
      // 2) 폴백: localStorage 에서 읽거나 데모로 시드
      setItems(readLocal(restaurantId));
      setUsingBackend(false);
      setReady(true);
    })();

    return () => {
      cancelled = true;
    };
  }, [restaurantId]);

  const persistLocal = useCallback(
    (next: MenuItem[]) => {
      setItems(next);
      if (restaurantId) writeLocal(restaurantId, next);
    },
    [restaurantId]
  );

  const addItem = useCallback(
    async (input: Omit<MenuItem, "id">) => {
      if (usingBackend && restaurantId) {
        const created = await apiCreateMenu(restaurantId, {
          name: input.name,
          price: input.price,
          category: input.category,
        });
        if (created) {
          setItems((prev) => [...prev, fromRemote(created)]);
          return;
        }
        // 백엔드 실패 → 로컬에만 반영 (사용자가 작업을 잃지 않도록)
      }
      persistLocal([...items, { ...input, id: newMenuId() }]);
    },
    [usingBackend, restaurantId, items, persistLocal]
  );

  const updateItem = useCallback(
    async (id: string, patch: Partial<Omit<MenuItem, "id">>) => {
      if (usingBackend) {
        const apiPatch: Record<string, unknown> = {};
        if (patch.name !== undefined) apiPatch.name = patch.name;
        if (patch.price !== undefined) apiPatch.price = patch.price;
        if (patch.category !== undefined) apiPatch.category = patch.category;
        if (patch.soldOut !== undefined) apiPatch.isAvailable = !patch.soldOut;
        const updated = await apiUpdateMenu(id, apiPatch);
        if (updated) {
          setItems((prev) =>
            prev.map((m) => (m.id === id ? fromRemote(updated) : m))
          );
          return;
        }
      }
      persistLocal(items.map((m) => (m.id === id ? { ...m, ...patch } : m)));
    },
    [usingBackend, items, persistLocal]
  );

  const deleteItem = useCallback(
    async (id: string) => {
      if (usingBackend) {
        const ok = await apiDeleteMenu(id);
        if (ok) {
          setItems((prev) => prev.filter((m) => m.id !== id));
          return;
        }
        // FK 위반 등으로 실패 — 사용자가 다시 시도하거나 품절 토글로 우회
      }
      persistLocal(items.filter((m) => m.id !== id));
    },
    [usingBackend, items, persistLocal]
  );

  const toggleSoldOut = useCallback(
    async (id: string) => {
      const current = items.find((m) => m.id === id);
      if (!current) return;
      const nextSoldOut = !current.soldOut;
      if (usingBackend) {
        const updated = await apiUpdateMenu(id, { isAvailable: !nextSoldOut });
        if (updated) {
          setItems((prev) =>
            prev.map((m) => (m.id === id ? fromRemote(updated) : m))
          );
          return;
        }
      }
      persistLocal(
        items.map((m) => (m.id === id ? { ...m, soldOut: nextSoldOut } : m))
      );
    },
    [usingBackend, items, persistLocal]
  );

  const resetToDemo = useCallback(() => {
    // 백엔드 모드일 땐 진짜 데이터를 흔들지 않도록 로컬에만 리셋 (개발 도구 성격)
    persistLocal(seedFromDemo());
  }, [persistLocal]);

  // 사용자 수정 카테고리 + 기본 카테고리 합쳐서 정렬 (전체는 항상 첫번째)
  const categories = useMemo(() => {
    const fromItems = Array.from(new Set(items.map((m) => m.category)));
    const merged = ["전체", ...new Set([...DEMO_CATEGORIES.slice(1), ...fromItems])];
    return merged;
  }, [items]);

  return {
    items,
    ready,
    usingBackend,
    categories,
    addItem,
    updateItem,
    deleteItem,
    toggleSoldOut,
    resetToDemo,
  };
}
