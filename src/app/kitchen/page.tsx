"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import AppShell from "@/components/AppShell";
import OrderCard from "@/components/OrderCard";
import EmptyState from "@/components/EmptyState";
import { useAuth } from "@/lib/hooks/useAuth";
import { useOrders } from "@/lib/hooks/useOrders";
import { updateOrderStatus } from "@/lib/api/pos";
import { nextStatus } from "@/lib/utils/status";
import { playNewOrderChime } from "@/lib/utils/sound";
import type { Order } from "@/lib/types";

// 주방 모드: PAID + PREPARING만 큰 글씨로. 한 번 탭으로 다음 상태 전이.
// POS_BUILD_GUIDE.md §6, §8 (UI/UX — 큰 글씨, 사운드)
export default function KitchenPage() {
  const auth = useAuth();
  const orders = useOrders(auth.restaurantId, undefined, auth.ready);

  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const seenPaid = useRef<Set<string>>(new Set());
  const primed = useRef(false);
  useEffect(() => {
    const list = orders.data ?? [];
    const paid = list.filter((o) => o.status === "PAID").map((o) => o.id);
    if (!primed.current) {
      paid.forEach((id) => seenPaid.current.add(id));
      primed.current = true;
      return;
    }
    let isNew = false;
    for (const id of paid) {
      if (!seenPaid.current.has(id)) {
        seenPaid.current.add(id);
        isNew = true;
      }
    }
    if (isNew) playNewOrderChime();
  }, [orders.data]);

  const visible = useMemo(() => {
    const list = orders.data ?? [];
    return list.filter((o) => o.status === "PAID" || o.status === "PREPARING");
  }, [orders.data]);

  const advance = async (order: Order) => {
    const next = nextStatus(order.status);
    if (!next) return;
    setBusyId(order.id);
    setError(null);
    try {
      await updateOrderStatus(order.id, next);
      await orders.refetch();
    } catch (e) {
      setError(e instanceof Error ? e.message : "상태 변경 실패");
    } finally {
      setBusyId(null);
    }
  };

  const paidCount = visible.filter((o) => o.status === "PAID").length;
  const preparingCount = visible.filter((o) => o.status === "PREPARING").length;

  return (
    <AppShell>
      <div className="max-w-[1400px] mx-auto px-screen-x py-6">
        <div className="flex items-end justify-between mb-5 gap-4 flex-wrap">
          <div>
            <h1 className="text-h1 text-ink-900">주방 모드</h1>
            <p className="text-base text-ink-700 mt-1">
              한 번 탭으로 다음 단계로 넘어갑니다
            </p>
          </div>
          <div className="flex items-center gap-2 text-sm">
            <Pill tone="primary" label="신규" count={paidCount} />
            <Pill tone="warning" label="조리중" count={preparingCount} />
          </div>
        </div>

        {error && (
          <div className="bg-red-50 border border-red-200 text-red-700 rounded-card p-4 text-sm mb-4">
            {error}
          </div>
        )}

        {visible.length === 0 ? (
          <div className="bg-white border border-line-divider rounded-card shadow-card py-20">
            <EmptyState
              message="처리할 주문이 없습니다"
              hint="새 주문이 들어오면 자동으로 표시됩니다"
            />
          </div>
        ) : (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {visible.map((o) => (
              <OrderCard
                key={o.id}
                order={o}
                size="large"
                onAdvance={advance}
                busy={busyId === o.id}
              />
            ))}
          </div>
        )}
      </div>
    </AppShell>
  );
}

function Pill({
  tone,
  label,
  count,
}: {
  tone: "primary" | "warning";
  label: string;
  count: number;
}) {
  const cls =
    tone === "primary"
      ? "bg-primary-surface text-primary-dark border-primary-light"
      : "bg-orange-50 text-orange-700 border-orange-200";
  return (
    <span
      className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-chip border text-xs font-semibold ${cls}`}
    >
      {label}
      <span className="font-extrabold tabular-nums">{count}</span>
    </span>
  );
}
