"use client";

import OrderCard from "@/components/OrderCard";
import EmptyState from "@/components/EmptyState";
import type { Order } from "@/lib/types";

interface Props {
  title: string;
  caption?: string;
  orders: Order[];
  highlight?: boolean;
  onAdvance: (order: Order) => void;
  onCancel?: (order: Order) => void;
  busyOrderId?: string | null;
}

export default function KanbanColumn({
  title,
  caption,
  orders,
  highlight = false,
  onAdvance,
  onCancel,
  busyOrderId = null,
}: Props) {
  return (
    <section
      className={
        "flex flex-col rounded-card border bg-white shadow-card " +
        (highlight ? "border-primary-light" : "border-line-divider")
      }
    >
      <header
        className={
          "px-4 py-3 border-b flex items-baseline justify-between rounded-t-card " +
          (highlight
            ? "border-primary-light/60 bg-primary-surface"
            : "border-line-divider bg-white")
        }
      >
        <div>
          <h2
            className={
              "text-base font-bold " +
              (highlight ? "text-primary-dark" : "text-ink-900")
            }
          >
            {title}
          </h2>
          {caption && (
            <p className="text-[11px] text-ink-500 mt-0.5">{caption}</p>
          )}
        </div>
        <span
          className={
            "text-xs font-semibold px-2 py-0.5 rounded-full border " +
            (highlight
              ? "border-primary text-primary-dark bg-white"
              : "border-line-border text-ink-700 bg-white")
          }
        >
          {orders.length}
        </span>
      </header>
      <div className="p-3 space-y-3 overflow-y-auto flex-1 min-h-[240px]">
        {orders.length === 0 ? (
          <EmptyState message="아직 없습니다" />
        ) : (
          orders.map((o) => (
            <OrderCard
              key={o.id}
              order={o}
              onAdvance={onAdvance}
              onCancel={onCancel}
              busy={busyOrderId === o.id}
            />
          ))
        )}
      </div>
    </section>
  );
}
