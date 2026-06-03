"use client";

import { useMemo, useState } from "react";
import AppShell from "@/components/AppShell";
import { useAuth } from "@/lib/hooks/useAuth";
import { useOrders } from "@/lib/hooks/useOrders";
import { formatPrice } from "@/lib/utils/format";
import type { Order, OrderStatus } from "@/lib/types";

// ══════════════════════════════════════════════════════════
// 파일 역할: 점주/POS "결제 관리" — orders 테이블 기반 실DB 결제 내역
//
// 2026-06-03 연동 변경 (localStorage → Supabase):
//   · 기존엔 useSales(localStorage `ls_pos_sales_*`)의 좌석 결제 시뮬을 보여줬으나,
//     이제 백엔드 GET /pos/orders/:restaurantId(useOrders, 3초 폴링)의 실제 주문 중
//     '결제 완료' 상태(PAID/PREPARING/READY/COMPLETED)를 결제 내역으로 집계한다.
//   · 결제수단은 orders.payment_method(문자열, 출처별로 POS_TOSS/POS_CASH/TOSS/CARD/null
//     혼재)를 현금/카드 2분류로 정규화(paymentBucket).
//   → Supabase 가 단일 진실원본. 손님앱·사장앱·POS 어디서 결제·처리해도 동일하게 반영되며,
//     사장이 Supabase 를 직접 만지지 않아도 POS 화면에 실시간 표시된다.
//   · dashboard/seats 페이지는 여전히 useSales(좌석 워크인 시뮬)를 사용 — 본 변경과 무관.
// ══════════════════════════════════════════════════════════

type PayKind = "CARD" | "CASH";
type Filter = "ALL" | PayKind;
type DateScope = "TODAY" | "ALL";

// 결제 완료로 간주하는 주문 상태.
//   PENDING = 결제 전, CANCELLED/REFUNDED = 결제 무효/환불 → 결제 내역에서 제외.
const PAID_STATUSES = new Set<OrderStatus>([
  "PAID",
  "PREPARING",
  "READY",
  "COMPLETED",
]);

// orders.payment_method 문자열 → 현금/카드 2분류.
//   값이 출처별로 섞여 있어(예: 'POS_CASH', 'CASH', 'POS_TOSS', 'TOSS', 'CARD', null)
//   'CASH' 포함 여부로만 현금을 판별하고, 나머지는 카드로 본다.
function paymentBucket(pm?: string | null): PayKind {
  if (pm && pm.toUpperCase().includes("CASH")) return "CASH";
  return "CARD";
}

function isSameDay(iso: string, date: Date): boolean {
  const d = new Date(iso);
  return (
    d.getFullYear() === date.getFullYear() &&
    d.getMonth() === date.getMonth() &&
    d.getDate() === date.getDate()
  );
}

export default function PaymentsPage() {
  const auth = useAuth();
  // 주문 전체를 3초 폴링으로 받아 결제 완료분만 추린다 (status 필터 없이 전체 조회).
  const orders = useOrders(auth.restaurantId, undefined, auth.ready);

  const [filter, setFilter] = useState<Filter>("ALL");
  const [scope, setScope] = useState<DateScope>("TODAY");

  const today = new Date();

  // 결제 완료 주문만 (결제 확정 시각 = updatedAt 사용)
  const paidOrders = useMemo(
    () => (orders.data ?? []).filter((o) => PAID_STATUSES.has(o.status)),
    [orders.data],
  );

  const filtered = useMemo(() => {
    let arr = paidOrders.slice();
    if (scope === "TODAY") arr = arr.filter((o) => isSameDay(o.updatedAt, today));
    if (filter !== "ALL")
      arr = arr.filter((o) => paymentBucket(o.paymentMethod) === filter);
    arr.sort((a, b) => (b.updatedAt > a.updatedAt ? 1 : -1));
    return arr;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [paidOrders, filter, scope]);

  // 오늘 결제 집계 (카드/현금 분리)
  const todayStats = useMemo(() => {
    const todays = paidOrders.filter((o) => isSameDay(o.updatedAt, today));
    const card = todays.filter((o) => paymentBucket(o.paymentMethod) === "CARD");
    const cash = todays.filter((o) => paymentBucket(o.paymentMethod) === "CASH");
    const sum = (arr: Order[]) => arr.reduce((a, b) => a + b.totalPrice, 0);
    return {
      total: sum(todays),
      count: todays.length,
      card: { total: sum(card), count: card.length },
      cash: { total: sum(cash), count: cash.length },
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [paidOrders]);

  const totals = useMemo(() => {
    const sum = filtered.reduce((a, o) => a + o.totalPrice, 0);
    return { sum, count: filtered.length };
  }, [filtered]);

  // 첫 로드 전(data 없음 + 식당 매핑 있음)만 로딩으로 본다.
  const loading = orders.data === undefined && Boolean(auth.restaurantId);

  return (
    <AppShell>
      <div className="max-w-[1200px] mx-auto px-screen-x py-6 space-y-5">
        <div>
          <h1 className="text-h1 text-ink-900">결제 관리</h1>
          <p className="text-sm text-ink-500 mt-1">
            주문 결제 내역 (카드/현금) · 3초 폴링
            {orders.lastUpdatedAt && (
              <span className="ml-2 inline-flex items-center gap-1.5 text-ink-700">
                <span className="inline-block h-1.5 w-1.5 rounded-full bg-state-success animate-pulse" />
                {orders.lastUpdatedAt.toLocaleTimeString("ko-KR")}
              </span>
            )}
          </p>
        </div>

        <section className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <SummaryCard
            label="오늘 결제"
            value={formatPrice(todayStats.total)}
            sub={`${todayStats.count}건`}
            primary
          />
          <SummaryCard
            label="카드"
            value={formatPrice(todayStats.card.total)}
            sub={`${todayStats.card.count}건`}
            tone="card"
          />
          <SummaryCard
            label="현금"
            value={formatPrice(todayStats.cash.total)}
            sub={`${todayStats.cash.count}건`}
            tone="cash"
          />
          <SummaryCard
            label="필터 결과"
            value={formatPrice(totals.sum)}
            sub={`${totals.count}건`}
          />
        </section>

        {/* 필터 */}
        <div className="flex flex-wrap gap-2">
          <FilterChip
            active={scope === "TODAY"}
            onClick={() => setScope("TODAY")}
            label="오늘"
          />
          <FilterChip
            active={scope === "ALL"}
            onClick={() => setScope("ALL")}
            label="전체 기간"
          />
          <span className="mx-1 text-ink-500">·</span>
          <FilterChip
            active={filter === "ALL"}
            onClick={() => setFilter("ALL")}
            label="전체"
          />
          <FilterChip
            active={filter === "CARD"}
            onClick={() => setFilter("CARD")}
            label="카드"
          />
          <FilterChip
            active={filter === "CASH"}
            onClick={() => setFilter("CASH")}
            label="현금"
          />
        </div>

        {orders.error && (
          <div className="bg-red-50 border border-red-200 text-red-700 rounded-card p-4 text-sm">
            결제 내역을 불러오지 못했습니다 · {orders.error}
          </div>
        )}

        {loading ? (
          <p className="py-10 text-center text-sm text-ink-500">불러오는 중…</p>
        ) : filtered.length === 0 ? (
          <div className="bg-white border border-line-divider rounded-card p-10 text-center text-sm text-ink-500">
            결제 내역이 없습니다
          </div>
        ) : (
          <div className="bg-white border border-line-divider rounded-card shadow-card overflow-hidden">
            <ul className="divide-y divide-line-divider">
              {filtered.map((o) => (
                <OrderRow key={o.id} order={o} />
              ))}
            </ul>
          </div>
        )}
      </div>
    </AppShell>
  );
}

function OrderRow({ order }: { order: Order }) {
  const kind = paymentBucket(order.paymentMethod);
  const at = new Date(order.updatedAt);
  const time = at.toLocaleTimeString("ko-KR", {
    hour: "2-digit",
    minute: "2-digit",
  });
  const date = at.toLocaleDateString("ko-KR", {
    month: "2-digit",
    day: "2-digit",
  });
  const orderNo = "#" + order.id.replace(/-/g, "").slice(-4).toUpperCase();
  const who = order.customer?.name ?? "손님";
  const itemSummary =
    !order.items || order.items.length === 0
      ? "—"
      : order.items
          .slice(0, 2)
          .map((it) => `${it.name} ×${it.quantity}`)
          .join(", ") +
        (order.items.length > 2 ? ` 외 ${order.items.length - 2}` : "");

  return (
    <li className="px-5 py-3 flex items-center justify-between gap-3">
      <div className="flex items-center gap-3 min-w-0">
        <span
          className={
            "shrink-0 inline-flex h-8 w-8 rounded-lg items-center justify-center text-base " +
            (kind === "CARD"
              ? "bg-primary-surface text-primary-dark"
              : "bg-emerald-50 text-emerald-700")
          }
        >
          {kind === "CARD" ? "💳" : "💵"}
        </span>
        <div className="min-w-0">
          <p className="text-sm font-bold text-ink-900 truncate">
            {orderNo}{" "}
            <span className="text-ink-500 font-normal">
              · {who} · {itemSummary}
            </span>
          </p>
          <p className="text-[11px] text-ink-500 mt-0.5 tabular-nums">
            {date} {time} · {kind === "CARD" ? "카드" : "현금"}
            {order.status === "COMPLETED" && (
              <span className="ml-1 text-ink-700">· 서빙완료</span>
            )}
          </p>
        </div>
      </div>
      <span className="text-base font-extrabold text-ink-900 tabular-nums shrink-0">
        {formatPrice(order.totalPrice)}
      </span>
    </li>
  );
}

function SummaryCard({
  label,
  value,
  sub,
  primary,
  tone,
}: {
  label: string;
  value: string;
  sub?: string;
  primary?: boolean;
  tone?: "card" | "cash";
}) {
  const cls = primary
    ? "bg-primary-dark text-white border-primary-dark"
    : tone === "card"
      ? "bg-primary-surface border-primary-light text-primary-dark"
      : tone === "cash"
        ? "bg-emerald-50 border-emerald-200 text-emerald-800"
        : "bg-white border-line-divider text-ink-900";
  return (
    <div className={`rounded-card border shadow-card p-4 ${cls}`}>
      <p className={"text-[11px] font-medium " + (primary ? "opacity-80" : "")}>
        {label}
      </p>
      <p className="text-2xl font-extrabold mt-1 tabular-nums">{value}</p>
      {sub && <p className="text-[11px] mt-0.5 opacity-80">{sub}</p>}
    </div>
  );
}

function FilterChip({
  active,
  onClick,
  label,
}: {
  active: boolean;
  onClick: () => void;
  label: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={
        "h-9 px-3 rounded-chip text-sm font-semibold border " +
        (active
          ? "bg-primary text-white border-primary"
          : "bg-white text-ink-700 border-line-border hover:bg-gray-50")
      }
    >
      {label}
    </button>
  );
}
