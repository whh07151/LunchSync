"use client";

import { useState } from "react";
import AppShell from "@/components/AppShell";
import SeatCard from "@/components/SeatCard";
import SeatDrawer from "@/components/SeatDrawer";
import { useAuth } from "@/lib/hooks/useAuth";
import { useSeats } from "@/lib/hooks/useSeats";
import { useSales } from "@/lib/hooks/useSales";
import { useMenu } from "@/lib/hooks/useMenu";
import { formatPrice } from "@/lib/utils/format";
import type { Seat } from "@/lib/types";

// pos_memo.md §2 — 좌석 예약/선택 + 좌석별 메뉴 관리 + 결제 수단별(현금/카드).
// 백엔드 좌석/매출 API 미구현 → 전부 식당 ID별 localStorage. 새로고침 시 유지, 멀티 단말 동기화 X.
export default function SeatsPage() {
  const auth = useAuth();
  const {
    seats,
    ready,
    stats,
    addSeat,
    removeLastSeat,
    addItem,
    decreaseItem,
    removeItem,
    closeSeat,
  } = useSeats(auth.restaurantId);
  const { recordSale, todayStats } = useSales(auth.restaurantId);
  const { items: menuItems, categories } = useMenu(auth.restaurantId);

  const [activeSeat, setActiveSeat] = useState<Seat | null>(null);

  // 활성 좌석은 매번 seats에서 재조회 (참조 최신화)
  const visibleSeat = activeSeat
    ? seats.find((s) => s.id === activeSeat.id) ?? null
    : null;

  return (
    <AppShell>
      <div className="max-w-[1400px] mx-auto px-screen-x py-6 space-y-6">
        <div className="flex items-end justify-between gap-4 flex-wrap">
          <div>
            <h1 className="text-h1 text-ink-900">좌석</h1>
            <p className="text-sm text-ink-500 mt-1">
              주문 들어오면 좌석을 탭해서 메뉴를 담고 결제하세요
              <span className="ml-2 inline-flex items-center gap-1 px-2 py-0.5 rounded-chip border border-line-border bg-white text-[10px] font-medium text-ink-700">
                데모 · 로컬 저장
              </span>
            </p>
          </div>
        </div>

        {/* 오늘 매출 카드 */}
        <section className="grid grid-cols-1 md:grid-cols-4 gap-3">
          <SummaryCard
            label="오늘 매출"
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
            label="현재 진행중"
            value={formatPrice(stats.totalRevenue)}
            sub={`사용중 ${stats.occupied} · 비어있음 ${stats.empty}`}
          />
        </section>

        {/* 좌석 그리드 */}
        <div className="bg-white border border-line-divider rounded-card shadow-card p-4">
          <div className="flex items-center justify-between mb-4">
            <p className="text-sm font-semibold text-ink-700">
              좌석 배치 · 총 {stats.total}석
            </p>
            <div className="flex items-center gap-1.5">
              <button
                type="button"
                onClick={removeLastSeat}
                className="h-9 w-9 rounded-full border border-line-border bg-white text-ink-700 hover:bg-gray-50 inline-flex items-center justify-center"
                aria-label="좌석 줄이기"
              >
                −
              </button>
              <span className="w-10 text-center text-sm font-semibold tabular-nums">
                {stats.total}
              </span>
              <button
                type="button"
                onClick={addSeat}
                className="h-9 w-9 rounded-full bg-primary text-white hover:bg-primary-dark inline-flex items-center justify-center"
                aria-label="좌석 추가"
              >
                +
              </button>
            </div>
          </div>

          {!ready ? (
            <p className="text-sm text-ink-500 py-10 text-center">불러오는 중…</p>
          ) : (
            <div className="grid gap-3 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6">
              {seats.map((s) => (
                <SeatCard key={s.id} seat={s} onClick={setActiveSeat} />
              ))}
            </div>
          )}
        </div>

        <p className="text-xs text-ink-500">
          ※ 좌석/메뉴/매출 모두 이 단말 localStorage에 저장됩니다. 다른 단말과
          공유되지 않으며, 백엔드 좌석·매출 모델 합의 후 동기화로 교체 예정입니다.
        </p>
      </div>

      <SeatDrawer
        seat={visibleSeat}
        menuItems={menuItems}
        categories={categories}
        onClose={() => setActiveSeat(null)}
        onAddItem={addItem}
        onDecreaseItem={decreaseItem}
        onRemoveItem={removeItem}
        onPaid={(p) => {
          recordSale({
            seatLabel: p.seatLabel,
            items: p.items,
            total: p.total,
            method: p.method,
            receivedAmount: p.receivedAmount,
            change: p.change,
          });
          closeSeat(p.seatId);
        }}
        onCancelSeat={closeSeat}
      />
    </AppShell>
  );
}

function SummaryCard({
  label,
  value,
  sub,
  primary = false,
  tone,
}: {
  label: string;
  value: string;
  sub?: string;
  primary?: boolean;
  tone?: "card" | "cash";
}) {
  const cardCls = primary
    ? "bg-primary-dark text-white border-primary-dark"
    : tone === "card"
      ? "bg-primary-surface text-primary-dark border-primary-light"
      : tone === "cash"
        ? "bg-emerald-50 text-emerald-800 border-emerald-200"
        : "bg-white text-ink-900 border-line-divider";

  return (
    <div className={`rounded-card border shadow-card p-4 ${cardCls}`}>
      <p
        className={
          "text-xs font-medium " +
          (primary ? "opacity-80" : "text-ink-700") +
          (tone === "cash" ? " !text-emerald-700" : "") +
          (tone === "card" ? " !text-primary-dark/80" : "")
        }
      >
        {label}
      </p>
      <p
        className={
          "text-2xl font-extrabold mt-1 tabular-nums tracking-tight " +
          (primary ? "" : "")
        }
      >
        {value}
      </p>
      {sub && (
        <p
          className={
            "text-[11px] mt-0.5 " +
            (primary ? "opacity-70" : "text-ink-500") +
            (tone === "card" ? " !text-primary-dark/70" : "") +
            (tone === "cash" ? " !text-emerald-700/80" : "")
          }
        >
          {sub}
        </p>
      )}
    </div>
  );
}
