"use client";

import {
  STATUS_LABEL,
  STATUS_TONE,
  isCancellable,
  nextStatus,
  nextStatusLabel,
} from "@/lib/utils/status";
import { formatPrice, formatTimeAgo, shortOrderNumber } from "@/lib/utils/format";
import type { Order } from "@/lib/types";

interface Props {
  order: Order;
  onAdvance?: (order: Order) => void;
  onCancel?: (order: Order) => void;
  busy?: boolean;
  size?: "compact" | "regular" | "large";
}

export default function OrderCard({
  order,
  onAdvance,
  onCancel,
  busy = false,
  size = "regular",
}: Props) {
  const tone = STATUS_TONE[order.status];
  const next = nextStatus(order.status);
  const nextLabel = nextStatusLabel(order.status);

  const titleSize =
    size === "large" ? "text-3xl" : size === "compact" ? "text-base" : "text-xl";
  const bodySize = size === "large" ? "text-lg" : "text-sm";
  const cardPadding = size === "large" ? "p-5" : "p-4";

  return (
    <article
      className={`rounded-card border shadow-card ${tone.border} ${tone.bg} ${cardPadding} flex flex-col gap-3`}
    >
      <header className="flex items-baseline justify-between gap-2">
        <div className="flex items-baseline gap-2 min-w-0">
          <span className={`font-extrabold ${titleSize} text-ink-900 tracking-tight`}>
            #{shortOrderNumber(order.id)}
          </span>
          <span className={`${bodySize} text-ink-700 truncate`}>
            {order.customer?.name ?? "손님"}
            {order.customer?.org ? (
              <span className="text-ink-500"> / {order.customer.org}</span>
            ) : null}
          </span>
        </div>
        <span
          className={`px-2 py-0.5 rounded-chip text-[11px] font-semibold ${tone.text} bg-white border border-current/30`}
        >
          {order.statusLabel ?? STATUS_LABEL[order.status]}
        </span>
      </header>

      {order.items && order.items.length > 0 ? (
        <ul className={`${bodySize} text-ink-900 space-y-0.5`}>
          {order.items.map((it, idx) => (
            <li key={idx}>
              {it.name} <span className="text-ink-500">×{it.quantity}</span>
            </li>
          ))}
        </ul>
      ) : (
        <p className={`${bodySize} text-ink-500 italic`}>
          메뉴 정보 미연동 — 상세 보기에서 확인
        </p>
      )}

      <footer className="flex items-center justify-between pt-1 border-t border-line-divider/60">
        <span className="text-base font-bold text-ink-900 pt-2">
          {formatPrice(order.totalPrice)}
        </span>
        <span className="text-xs text-ink-500 pt-2">
          {formatTimeAgo(order.createdAt)}
        </span>
      </footer>

      {(next || isCancellable(order.status)) && (
        <div className="flex items-center gap-2">
          {next && onAdvance && (
            <button
              type="button"
              onClick={() => onAdvance(order)}
              disabled={busy}
              className="flex-1 h-11 rounded-button bg-primary text-white font-semibold text-sm hover:bg-primary-dark active:scale-[0.99] transition disabled:opacity-50 disabled:active:scale-100"
            >
              {busy ? "처리 중…" : nextLabel}
            </button>
          )}
          {isCancellable(order.status) && onCancel && (
            <button
              type="button"
              onClick={() => onCancel(order)}
              disabled={busy}
              className="h-11 px-4 rounded-button border border-line-border bg-white text-ink-700 text-sm font-medium hover:bg-gray-50 disabled:opacity-50"
            >
              취소
            </button>
          )}
        </div>
      )}
    </article>
  );
}
