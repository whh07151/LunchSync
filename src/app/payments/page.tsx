"use client";

import { useMemo, useState } from "react";
import AppShell from "@/components/AppShell";
import { useAuth } from "@/lib/hooks/useAuth";
import { useSales } from "@/lib/hooks/useSales";
import { formatPrice } from "@/lib/utils/format";
import type { PaymentMethod, Sale } from "@/lib/types";

// pos_memo §6-3 — 결제 관리. useSales가 누적한 결제 내역을 시간순 + 수단별 필터.
type Filter = "ALL" | PaymentMethod;
type DateScope = "TODAY" | "ALL";

export default function PaymentsPage() {
  const auth = useAuth();
  const { sales, ready, todayStats } = useSales(auth.restaurantId);

  const [filter, setFilter] = useState<Filter>("ALL");
  const [scope, setScope] = useState<DateScope>("TODAY");

  const today = new Date();
  const isSameDay = (iso: string) => {
    const d = new Date(iso);
    return (
      d.getFullYear() === today.getFullYear() &&
      d.getMonth() === today.getMonth() &&
      d.getDate() === today.getDate()
    );
  };

  const filtered = useMemo(() => {
    let arr = sales.slice();
    if (scope === "TODAY") arr = arr.filter((s) => isSameDay(s.closedAt));
    if (filter !== "ALL") arr = arr.filter((s) => s.method === filter);
    arr.sort((a, b) => (b.closedAt > a.closedAt ? 1 : -1));
    return arr;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sales, filter, scope]);

  const totals = useMemo(() => {
    const sum = filtered.reduce((a, s) => a + s.total, 0);
    return { sum, count: filtered.length };
  }, [filtered]);

  return (
    <AppShell>
      <div className="max-w-[1200px] mx-auto px-screen-x py-6 space-y-5">
        <div>
          <h1 className="text-h1 text-ink-900">결제 관리</h1>
          <p className="text-sm text-ink-500 mt-1">
            POS 좌석 결제 내역 (카드/현금) ·{" "}
            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-chip border border-line-border bg-white text-[10px] font-medium text-ink-700">
              데모 · 로컬 저장
            </span>
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

        {!ready ? (
          <p className="py-10 text-center text-sm text-ink-500">불러오는 중…</p>
        ) : filtered.length === 0 ? (
          <div className="bg-white border border-line-divider rounded-card p-10 text-center text-sm text-ink-500">
            결제 내역이 없습니다
          </div>
        ) : (
          <div className="bg-white border border-line-divider rounded-card shadow-card overflow-hidden">
            <ul className="divide-y divide-line-divider">
              {filtered.map((s) => (
                <SaleRow key={s.id} sale={s} />
              ))}
            </ul>
          </div>
        )}

        <p className="text-xs text-ink-500">
          ※ 백엔드{" "}
          <code className="font-mono">orders.payment_method</code> 컬럼 + 결제 집계 API 연결 후
          서버 데이터로 교체.
        </p>
      </div>
    </AppShell>
  );
}

function SaleRow({ sale }: { sale: Sale }) {
  const at = new Date(sale.closedAt);
  const time = at.toLocaleTimeString("ko-KR", {
    hour: "2-digit",
    minute: "2-digit",
  });
  const date = at.toLocaleDateString("ko-KR", {
    month: "2-digit",
    day: "2-digit",
  });
  const itemSummary =
    sale.items.length === 0
      ? "—"
      : sale.items
          .slice(0, 2)
          .map((it) => `${it.name} ×${it.quantity}`)
          .join(", ") + (sale.items.length > 2 ? ` 외 ${sale.items.length - 2}` : "");

  return (
    <li className="px-5 py-3 flex items-center justify-between gap-3">
      <div className="flex items-center gap-3 min-w-0">
        <span
          className={
            "shrink-0 inline-flex h-8 w-8 rounded-lg items-center justify-center text-base " +
            (sale.method === "CARD"
              ? "bg-primary-surface text-primary-dark"
              : "bg-emerald-50 text-emerald-700")
          }
        >
          {sale.method === "CARD" ? "💳" : "💵"}
        </span>
        <div className="min-w-0">
          <p className="text-sm font-bold text-ink-900">
            {sale.seatLabel} 테이블{" "}
            <span className="text-ink-500 font-normal">· {itemSummary}</span>
          </p>
          <p className="text-[11px] text-ink-500 mt-0.5 tabular-nums">
            {date} {time}
            {sale.method === "CASH" && typeof sale.change === "number" && (
              <span className="ml-2 text-emerald-700">
                받음 {formatPrice(sale.receivedAmount ?? 0)} / 거스름{" "}
                {formatPrice(sale.change)}
              </span>
            )}
          </p>
        </div>
      </div>
      <span className="text-base font-extrabold text-ink-900 tabular-nums shrink-0">
        {formatPrice(sale.total)}
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
