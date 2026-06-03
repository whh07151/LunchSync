"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import AppShell from "@/components/AppShell";
import KanbanColumn from "@/components/KanbanColumn";
import CancelModal from "@/components/CancelModal";
import { useAuth } from "@/lib/hooks/useAuth";
import { useOrders } from "@/lib/hooks/useOrders";
import { cancelOrder, updateOrderStatus } from "@/lib/api/pos";
import { nextStatus, STATUS_LABEL } from "@/lib/utils/status";
import { playNewOrderChime } from "@/lib/utils/sound";
import type { Order, OrderStatus } from "@/lib/types";

// pos_memo §9 — 주문 관리.
// 손님앱(픽업) 흐름의 PAID/PREPARING/READY 칸반 + 필터 + 빠른 모드 진입.
type FilterKey = "ALL" | "PAID" | "PREPARING" | "READY" | "COMPLETED" | "CANCELLED";

export default function OrdersPage() {
  const auth = useAuth();
  const orders = useOrders(auth.restaurantId, undefined, auth.ready);

  const [busyId, setBusyId] = useState<string | null>(null);
  const [cancelTarget, setCancelTarget] = useState<Order | null>(null);
  const [cancelBusy, setCancelBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [filter, setFilter] = useState<FilterKey>("ALL");

  // 신규(PAID) 진입 감지 — 사운드
  const seenPaidIds = useRef<Set<string>>(new Set());
  const primedRef = useRef(false);
  useEffect(() => {
    const list = orders.data ?? [];
    const currentPaid = list.filter((o) => o.status === "PAID").map((o) => o.id);
    if (!primedRef.current) {
      currentPaid.forEach((id) => seenPaidIds.current.add(id));
      primedRef.current = true;
      return;
    }
    let hasNew = false;
    for (const id of currentPaid) {
      if (!seenPaidIds.current.has(id)) {
        seenPaidIds.current.add(id);
        hasNew = true;
      }
    }
    if (hasNew) playNewOrderChime();
  }, [orders.data]);

  const grouped = useMemo(() => {
    const list = orders.data ?? [];
    const buckets: Record<OrderStatus, Order[]> = {
      PENDING: [],
      PAID: [],
      PREPARING: [],
      READY: [],
      COMPLETED: [],
      CANCELLED: [],
      // POS-09: 환불 시뮬 상태도 별도 버킷에 분리. 현재 페이지의 칸반은
      // PAID/PREPARING/READY 만 표시하지만, OrderStatus 가 확장되었으므로
      // Record 키를 모두 채워 타입 검사를 만족시킨다. COMPLETED/CANCELLED
      // 처럼 별도 필터 화면이 필요해지면 후속 티켓에서 리스트 뷰를 추가.
      REFUNDED: [],
    };
    for (const o of list) buckets[o.status]?.push(o);
    return buckets;
  }, [orders.data]);

  const filterCount = (k: FilterKey) => {
    if (k === "ALL") return orders.data?.length ?? 0;
    // 2026-06-03: 신규 주문 칩(PAID)에는 결제대기(PENDING)도 함께 집계 —
    //   칸반 첫 컬럼이 PENDING+PAID 를 함께 보여주는 것과 카운트를 일치시킨다.
    if (k === "PAID") return grouped.PENDING.length + grouped.PAID.length;
    return grouped[k as OrderStatus].length;
  };

  const advance = async (order: Order) => {
    const next = nextStatus(order.status);
    if (!next) return;
    setBusyId(order.id);
    setActionError(null);
    try {
      await updateOrderStatus(order.id, next);
      await orders.refetch();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "상태 변경 실패");
    } finally {
      setBusyId(null);
    }
  };

  const onCancelConfirm = async (order: Order, reason: string) => {
    setCancelBusy(true);
    setActionError(null);
    try {
      await cancelOrder(order.id, reason);
      setCancelTarget(null);
      await orders.refetch();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "취소 실패");
    } finally {
      setCancelBusy(false);
    }
  };

  return (
    <AppShell>
      <div className="max-w-[1400px] mx-auto px-screen-x py-6 space-y-5">
        <div className="flex items-end justify-between gap-4 flex-wrap">
          <div>
            <h1 className="text-h1 text-ink-900">주문 관리</h1>
            <p className="text-sm text-ink-500 mt-1">
              손님앱에서 들어온 주문을 처리합니다 · 3초 폴링
              {orders.lastUpdatedAt && (
                <span className="ml-2 inline-flex items-center gap-1.5 text-ink-700">
                  <span className="inline-block h-1.5 w-1.5 rounded-full bg-state-success animate-pulse" />
                  {orders.lastUpdatedAt.toLocaleTimeString("ko-KR")}
                </span>
              )}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Link
              href="/kitchen"
              className="h-10 px-4 rounded-button border border-line-border bg-white text-sm font-medium text-ink-700 hover:bg-gray-50 inline-flex items-center"
            >
              주방 모드
            </Link>
            <Link
              href="/board"
              className="h-10 px-4 rounded-button border border-line-border bg-white text-sm font-medium text-ink-700 hover:bg-gray-50 inline-flex items-center"
            >
              호출 보드
            </Link>
          </div>
        </div>

        {/* 필터 */}
        <div className="flex flex-wrap gap-2">
          {(
            [
              ["ALL", "전체"],
              ["PAID", STATUS_LABEL.PAID],
              ["PREPARING", STATUS_LABEL.PREPARING],
              ["READY", STATUS_LABEL.READY],
              ["COMPLETED", STATUS_LABEL.COMPLETED],
              ["CANCELLED", STATUS_LABEL.CANCELLED],
            ] as const
          ).map(([k, label]) => {
            const active = filter === k;
            return (
              <button
                key={k}
                type="button"
                onClick={() => setFilter(k)}
                className={
                  "h-9 px-3 rounded-chip text-sm font-semibold border inline-flex items-center gap-1.5 " +
                  (active
                    ? "bg-primary text-white border-primary"
                    : "bg-white text-ink-700 border-line-border hover:bg-gray-50")
                }
              >
                {label}
                <span
                  className={
                    "tabular-nums text-[11px] " +
                    (active ? "opacity-90" : "text-ink-500")
                  }
                >
                  {filterCount(k)}
                </span>
              </button>
            );
          })}
        </div>

        {orders.error && (
          <div className="bg-red-50 border border-red-200 text-red-700 rounded-card p-4 text-sm">
            <p className="font-semibold">주문 목록을 불러오지 못했습니다</p>
            <p className="mt-0.5 text-red-600/90">{orders.error}</p>
          </div>
        )}
        {actionError && (
          <div className="bg-red-50 border border-red-200 text-red-700 rounded-card p-4 text-sm">
            {actionError}
          </div>
        )}

        {/* 칸반 — 활성 단계만 항상 노출 */}
        {(filter === "ALL" || ["PAID", "PREPARING", "READY"].includes(filter)) && (
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {(filter === "ALL" || filter === "PAID") && (
              <KanbanColumn
                title="신규 주문"
                caption="결제대기(PENDING)·결제완료(PAID) — 수락 대기"
                highlight
                // 2026-06-03: 결제 미완으로 PENDING 에 갇힌 주문도 사장이 수락/거절할 수
                //   있도록 첫 컬럼에 PENDING+PAID 를 함께 노출한다. (이전엔 PAID 만 표시되어
                //   PENDING 주문이 POS 에 아예 안 보였고, Supabase 에서 직접 status 를
                //   바꿔야만 처리되던 문제를 해소.)
                orders={[...grouped.PENDING, ...grouped.PAID]}
                onAdvance={advance}
                onCancel={(o) => setCancelTarget(o)}
                busyOrderId={busyId}
              />
            )}
            {(filter === "ALL" || filter === "PREPARING") && (
              <KanbanColumn
                title={STATUS_LABEL.PREPARING}
                caption="PREPARING"
                orders={grouped.PREPARING}
                onAdvance={advance}
                onCancel={(o) => setCancelTarget(o)}
                busyOrderId={busyId}
              />
            )}
            {(filter === "ALL" || filter === "READY") && (
              <KanbanColumn
                title={STATUS_LABEL.READY}
                caption="READY"
                orders={grouped.READY}
                onAdvance={advance}
                busyOrderId={busyId}
              />
            )}
          </div>
        )}

        {/* COMPLETED / CANCELLED 는 리스트 형식 */}
        {(filter === "COMPLETED" || filter === "CANCELLED") && (
          <div className="bg-white border border-line-divider rounded-card shadow-card divide-y divide-line-divider">
            {grouped[filter as OrderStatus].length === 0 ? (
              <p className="p-8 text-center text-sm text-ink-500">
                {STATUS_LABEL[filter as OrderStatus]} 상태 주문이 없습니다
              </p>
            ) : (
              grouped[filter as OrderStatus].map((o) => (
                <Link
                  key={o.id}
                  href={`/orders/${o.id}`}
                  className="block p-4 hover:bg-gray-50 flex items-center justify-between gap-3"
                >
                  <div className="min-w-0">
                    <p className="text-sm font-bold text-ink-900">
                      #{o.id.replace(/-/g, "").slice(-4).toUpperCase()}
                    </p>
                    <p className="text-xs text-ink-500 mt-0.5">
                      {o.customer?.name ?? "손님"} · ₩
                      {o.totalPrice.toLocaleString("ko-KR")}
                    </p>
                  </div>
                  <span className="text-xs text-ink-700">→</span>
                </Link>
              ))
            )}
          </div>
        )}
      </div>

      <CancelModal
        order={cancelTarget}
        onClose={() => !cancelBusy && setCancelTarget(null)}
        onConfirm={onCancelConfirm}
        busy={cancelBusy}
      />
    </AppShell>
  );
}
