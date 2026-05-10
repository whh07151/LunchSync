"use client";

import type { OrderStats } from "@/lib/types";
import { formatPrice } from "@/lib/utils/format";

interface Props {
  stats: OrderStats | null;
  loading?: boolean;
}

const ITEMS: Array<{
  key: keyof OrderStats;
  label: string;
  tone: string;
  ring: string;
}> = [
  { key: "paid", label: "신규", tone: "text-primary-dark", ring: "bg-primary" },
  { key: "preparing", label: "조리중", tone: "text-orange-700", ring: "bg-orange-400" },
  { key: "ready", label: "픽업대기", tone: "text-yellow-800", ring: "bg-yellow-400" },
  { key: "completed", label: "완료", tone: "text-ink-500", ring: "bg-ink-500" },
  { key: "cancelled", label: "취소", tone: "text-state-error", ring: "bg-state-error" },
];

export default function StatsCards({ stats, loading = false }: Props) {
  return (
    <div className="grid grid-cols-2 md:grid-cols-6 gap-3">
      {ITEMS.map((it) => (
        <div
          key={it.key}
          className="bg-white rounded-card border border-line-divider shadow-card p-4 flex flex-col gap-2"
        >
          <div className="flex items-center gap-1.5">
            <span className={`inline-block h-1.5 w-1.5 rounded-full ${it.ring}`} />
            <span className="text-[11px] font-medium text-ink-700">{it.label}</span>
          </div>
          <p className={`text-2xl font-extrabold ${it.tone}`}>
            {loading || !stats ? "—" : (stats[it.key] as number)}
          </p>
        </div>
      ))}
      <div className="bg-primary-dark text-white rounded-card shadow-card p-4 col-span-2 md:col-span-1 flex flex-col gap-2">
        <span className="text-[11px] opacity-80">매출 합계</span>
        <p className="text-xl font-extrabold tracking-tight">
          {loading || !stats ? "—" : formatPrice(stats.totalRevenue)}
        </p>
      </div>
    </div>
  );
}
