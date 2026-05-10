"use client";

import { formatPrice, formatTimeAgo } from "@/lib/utils/format";
import { seatItemCount, seatTotal } from "@/lib/hooks/useSeats";
import type { Seat } from "@/lib/types";

interface Props {
  seat: Seat;
  onClick: (seat: Seat) => void;
}

export default function SeatCard({ seat, onClick }: Props) {
  const occupied = seat.status === "occupied";
  const count = seatItemCount(seat);
  const total = seatTotal(seat);

  return (
    <button
      type="button"
      onClick={() => onClick(seat)}
      className={
        "group relative aspect-[4/3] rounded-card border-2 p-4 flex flex-col justify-between text-left transition-all " +
        (occupied
          ? "bg-primary-surface border-primary hover:bg-primary/10 hover:shadow-elevated"
          : "bg-white border-line-divider hover:border-primary-light hover:shadow-card")
      }
    >
      <header className="flex items-baseline justify-between">
        <span
          className={
            "font-extrabold tracking-tight text-2xl " +
            (occupied ? "text-primary-dark" : "text-ink-900")
          }
        >
          {seat.label}
        </span>
        <span
          className={
            "text-[11px] font-semibold px-2 py-0.5 rounded-chip " +
            (occupied
              ? "bg-primary text-white"
              : "bg-gray-100 text-ink-500")
          }
        >
          {occupied ? "사용중" : "비어있음"}
        </span>
      </header>

      {occupied ? (
        <div className="space-y-0.5">
          <p className="text-xs text-ink-700">
            {seat.startedAt ? formatTimeAgo(seat.startedAt) + " 시작" : ""}
          </p>
          <p className="text-sm text-ink-900">
            <span className="font-semibold">{count}건</span>
            <span className="mx-1.5 text-ink-500">·</span>
            <span className="font-bold">{formatPrice(total)}</span>
          </p>
        </div>
      ) : (
        <p className="text-xs text-ink-500">탭하여 주문 시작</p>
      )}
    </button>
  );
}
