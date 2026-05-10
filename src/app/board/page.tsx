"use client";

import { useEffect, useMemo, useRef } from "react";
import AppShell from "@/components/AppShell";
import { useAuth } from "@/lib/hooks/useAuth";
import { useOrders } from "@/lib/hooks/useOrders";
import { playReadyChime } from "@/lib/utils/sound";
import { shortOrderNumber } from "@/lib/utils/format";
import type { Order } from "@/lib/types";

// 호출 보드 — 풀스크린 전광판 가정. POS_BUILD_GUIDE.md §6, §8
export default function BoardPage() {
  const auth = useAuth();
  const orders = useOrders(auth.restaurantId, "READY", auth.ready);

  const seenReady = useRef<Set<string>>(new Set());
  const primed = useRef(false);
  const flashIds = useRef<Set<string>>(new Set());

  useEffect(() => {
    const list = (orders.data ?? []) as Order[];
    const ids = list.map((o) => o.id);
    if (!primed.current) {
      ids.forEach((id) => seenReady.current.add(id));
      primed.current = true;
      return;
    }
    let chimed = false;
    for (const id of ids) {
      if (!seenReady.current.has(id)) {
        seenReady.current.add(id);
        flashIds.current.add(id);
        if (!chimed) {
          playReadyChime();
          chimed = true;
        }
        const target = id;
        setTimeout(() => {
          flashIds.current.delete(target);
        }, 6000);
      }
    }
  }, [orders.data]);

  const list = useMemo(() => {
    return ((orders.data ?? []) as Order[]).slice(0, 20);
  }, [orders.data]);

  return (
    <AppShell bare>
      <div className="board-fullscreen min-h-screen p-8 flex flex-col">
        <header className="flex items-baseline justify-between border-b border-white/10 pb-4">
          <div>
            <h1 className="text-4xl font-extrabold tracking-tight">픽업 안내</h1>
            <p className="text-white/60 mt-1 text-sm">
              번호가 보이면 카운터에서 수령해 주세요
            </p>
          </div>
          <div className="flex items-center gap-3 text-xs text-white/50">
            <span className="inline-flex items-center gap-1.5">
              <span className="inline-block h-1.5 w-1.5 rounded-full bg-emerald-400 animate-pulse" />
              실시간
            </span>
            <a href="/dashboard" className="hover:text-white underline-offset-4 hover:underline">
              대시보드로
            </a>
          </div>
        </header>

        <div className="flex-1 flex items-center justify-center mt-8">
          {list.length === 0 ? (
            <p className="text-white/40 text-2xl">대기 중인 주문이 없습니다</p>
          ) : (
            <div
              className="grid gap-6 w-full"
              style={{
                gridTemplateColumns: `repeat(auto-fit, minmax(min(220px, 100%), 1fr))`,
              }}
            >
              {list.map((o) => {
                const flashing = flashIds.current.has(o.id);
                return (
                  <div
                    key={o.id}
                    className={
                      "rounded-card border-2 border-primary-light bg-primary/15 text-center py-10 " +
                      (flashing ? "animate-flash" : "")
                    }
                  >
                    <p className="text-primary-light text-sm font-medium">호출번호</p>
                    <p className="text-white font-extrabold tracking-widest text-7xl mt-2">
                      {shortOrderNumber(o.id)}
                    </p>
                    {o.customer?.name && (
                      <p className="text-white/70 mt-3 text-base">
                        {o.customer.name} 님
                      </p>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>

        <footer className="text-white/40 text-xs text-right pt-4">
          {orders.lastUpdatedAt
            ? `갱신 ${orders.lastUpdatedAt.toLocaleTimeString("ko-KR")}`
            : "갱신 대기"}
        </footer>
      </div>
    </AppShell>
  );
}
