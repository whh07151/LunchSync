"use client";

import AppShell from "@/components/AppShell";
import StatsCards from "@/components/StatsCards";
import { useAuth } from "@/lib/hooks/useAuth";
import { useOrderStats } from "@/lib/hooks/useStats";
import { useOrders } from "@/lib/hooks/useOrders";
import { formatPrice } from "@/lib/utils/format";
import { useMemo } from "react";

export default function StatsPage() {
  const auth = useAuth();
  const stats = useOrderStats(auth.restaurantId, auth.ready);
  const orders = useOrders(auth.restaurantId, undefined, auth.ready);

  // 평균 처리 시간 (PAID → COMPLETED) — 클라이언트에서 createdAt/updatedAt 비교로 추정
  const avgPickupMinutes = useMemo(() => {
    const list = orders.data ?? [];
    const completed = list.filter((o) => o.status === "COMPLETED");
    if (completed.length === 0) return null;
    const sumMs = completed.reduce((acc, o) => {
      const start = new Date(o.createdAt).getTime();
      const end = new Date(o.updatedAt).getTime();
      return acc + Math.max(0, end - start);
    }, 0);
    return Math.round(sumMs / completed.length / 60000);
  }, [orders.data]);

  const ratio = (n: number, total: number) =>
    total === 0 ? 0 : Math.round((n / total) * 100);

  return (
    <AppShell>
      <div className="max-w-[1200px] mx-auto px-screen-x py-6 space-y-6">
        <div>
          <h1 className="text-h1 text-ink-900">통계</h1>
          <p className="text-sm text-ink-500 mt-1">
            결제 상태별 주문 수 + 매출 합계 · 5초 폴링
          </p>
        </div>

        {stats.error && (
          <div className="bg-red-50 border border-red-200 text-red-700 rounded-card p-4 text-sm">
            통계 조회 실패: {stats.error}
          </div>
        )}

        <StatsCards stats={stats.data} loading={stats.loading} />

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <Card>
            <h2 className="text-sm font-semibold text-ink-700">총 주문</h2>
            <p className="text-3xl font-extrabold mt-2 tracking-tight">
              {stats.data?.total ?? "—"}
            </p>
          </Card>
          <Card highlight>
            <h2 className="text-sm font-semibold text-primary-dark/80">매출 합계</h2>
            <p className="text-3xl font-extrabold mt-2 tracking-tight text-primary-dark">
              {stats.data ? formatPrice(stats.data.totalRevenue) : "—"}
            </p>
            {stats.data && stats.data.completed > 0 && (
              <p className="text-xs text-ink-700 mt-1">
                건당 평균{" "}
                {formatPrice(
                  Math.round(
                    stats.data.totalRevenue / Math.max(1, stats.data.completed)
                  )
                )}
              </p>
            )}
          </Card>
          <Card>
            <h2 className="text-sm font-semibold text-ink-700">평균 처리 시간</h2>
            <p className="text-3xl font-extrabold mt-2 tracking-tight">
              {avgPickupMinutes !== null ? `${avgPickupMinutes}분` : "—"}
            </p>
            <p className="text-xs text-ink-500 mt-1">
              완료 주문 createdAt → updatedAt 평균
            </p>
          </Card>
        </div>

        {stats.data && (
          <Card>
            <h2 className="text-sm font-semibold text-ink-700 mb-3">상태별 비율</h2>
            <div className="space-y-2.5">
              {(
                [
                  ["paid", "신규(PAID)", "bg-primary"],
                  ["preparing", "조리중(PREPARING)", "bg-orange-400"],
                  ["ready", "픽업대기(READY)", "bg-yellow-400"],
                  ["completed", "완료(COMPLETED)", "bg-ink-500"],
                  ["cancelled", "취소(CANCELLED)", "bg-state-error"],
                ] as const
              ).map(([k, label, bar]) => {
                const v = stats.data ? (stats.data[k] as number) : 0;
                const pct = ratio(v, stats.data!.total);
                return (
                  <div key={k}>
                    <div className="flex justify-between text-xs text-ink-700 mb-1">
                      <span>{label}</span>
                      <span className="tabular-nums">
                        {v} <span className="text-ink-500">({pct}%)</span>
                      </span>
                    </div>
                    <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
                      <div
                        className={`h-full ${bar} transition-all duration-500`}
                        style={{ width: `${pct}%` }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </Card>
        )}

        <p className="text-xs text-ink-500">
          ※ 일/주/월 매출 그래프는 백엔드 통계 엔드포인트 확장 후 추가 예정.
        </p>
      </div>
    </AppShell>
  );
}

function Card({
  children,
  highlight,
}: {
  children: React.ReactNode;
  highlight?: boolean;
}) {
  return (
    <section
      className={
        "rounded-card border shadow-card p-5 " +
        (highlight
          ? "bg-primary-surface border-primary-light"
          : "bg-white border-line-divider")
      }
    >
      {children}
    </section>
  );
}
