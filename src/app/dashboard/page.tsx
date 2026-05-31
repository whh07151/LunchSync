"use client";

import Link from "next/link";
import { useMemo } from "react";
import AppShell from "@/components/AppShell";
import TodaysNoteCard from "@/components/TodaysNoteCard";
import { useAuth } from "@/lib/hooks/useAuth";
import { useOrders } from "@/lib/hooks/useOrders";
import { useOrderStats } from "@/lib/hooks/useStats";
import { useSeats } from "@/lib/hooks/useSeats";
import { useSales } from "@/lib/hooks/useSales";
import { useReservations } from "@/lib/hooks/useReservations";
import { formatPrice, formatTimeAgo, shortOrderNumber } from "@/lib/utils/format";
import { STATUS_LABEL, STATUS_TONE } from "@/lib/utils/status";
import type { OrderStatus, SeatItem } from "@/lib/types";

// pos_memo §8 — 대시보드: 오늘 운영 현황을 한눈에.
// 카드 12종 + 최근 주문 + 인기 메뉴.
export default function DashboardPage() {
  const auth = useAuth();
  const orders = useOrders(auth.restaurantId, undefined, auth.ready);
  const stats = useOrderStats(auth.restaurantId, auth.ready);
  const { stats: seatStats } = useSeats(auth.restaurantId);
  // 2026-05-31 회귀 fix: useSales 가 매출을 localStorage 누적 방식으로
  // 관리해서 손님 결제(PAID) 가 "오늘 매출/카드 결제" 카드에 0원으로
  // 표시됨. backend pos.service.getPaymentStats 가 totalRevenue +
  // 결제수단별 매출을 정상 제공하므로 그 값으로 dashboard 카드 재구성.
  // 좌석 결제 기반의 sales 배열은 인기 메뉴(아래) 용으로 그대로 유지.
  const { todayStats: seatTodayStats, sales } = useSales(auth.restaurantId);
  const todayStats = useMemo(() => {
    const s = stats.data;
    if (!s) return seatTodayStats;
    const paidCount = s.paid + s.preparing + s.ready + s.completed;
    return {
      total: s.totalRevenue,
      count: paidCount,
      // 토스 결제(앱 손님) + 카드 결제(좌석) 를 "카드 결제" 카드에 합쳐 노출.
      card: {
        total: (s.tossRevenue ?? 0) + (s.cardRevenue ?? 0),
        count: paidCount,
      },
      cash: {
        total: s.cashRevenue ?? 0,
        count: 0,
      },
    };
  }, [stats.data, seatTodayStats]);
  const { stats: reservationStats } = useReservations(auth.restaurantId);

  const orderList = orders.data ?? [];
  const todayOrders = orderList.length;

  const counts: Record<OrderStatus, number> = useMemo(() => {
    const acc: Record<OrderStatus, number> = {
      PENDING: 0,
      PAID: 0,
      PREPARING: 0,
      READY: 0,
      COMPLETED: 0,
      CANCELLED: 0,
      // POS-09: 환불 시뮬 상태도 카운트에 포함. dashboard 카드 그리드에서는
      // 아직 "환불" 카드를 별도로 두지 않지만, OrderStatus 가 확장되어
      // Record 키가 누락되면 타입 에러가 나므로 0 으로 초기화.
      REFUNDED: 0,
    };
    for (const o of orderList) acc[o.status] += 1;
    return acc;
  }, [orderList]);

  const inProgress = counts.PAID + counts.PREPARING + counts.READY;

  // 인기 메뉴 — 오늘 sales의 menuId별 quantity 합산
  const topMenus = useMemo(() => {
    const today = new Date();
    const isSameDay = (iso: string) => {
      const d = new Date(iso);
      return (
        d.getFullYear() === today.getFullYear() &&
        d.getMonth() === today.getMonth() &&
        d.getDate() === today.getDate()
      );
    };
    const tally = new Map<string, { name: string; qty: number; revenue: number }>();
    for (const sale of sales) {
      if (!isSameDay(sale.closedAt)) continue;
      for (const it of sale.items as SeatItem[]) {
        const cur = tally.get(it.menuId);
        if (cur) {
          cur.qty += it.quantity;
          cur.revenue += it.quantity * it.price;
        } else {
          tally.set(it.menuId, {
            name: it.name,
            qty: it.quantity,
            revenue: it.quantity * it.price,
          });
        }
      }
    }
    return Array.from(tally.values())
      .sort((a, b) => b.qty - a.qty)
      .slice(0, 5);
  }, [sales]);

  const recentOrders = useMemo(() => {
    return [...orderList]
      .sort((a, b) => (b.createdAt > a.createdAt ? 1 : -1))
      .slice(0, 5);
  }, [orderList]);

  return (
    <AppShell>
      <div className="max-w-[1400px] mx-auto px-screen-x py-6 space-y-6">
        <div>
          <h1 className="text-h1 text-ink-900">대시보드</h1>
          <p className="text-sm text-ink-500 mt-1">오늘 운영 현황을 한눈에</p>
        </div>

        {/*
          2026-05-31 WOW#1 "사장님 오늘의 한 줄" 카드.
          상단 영업 토글(AppShell) 바로 아래에 큰 영역으로 노출 — 시연 때
          사장님이 한눈에 발견하도록 핵심 카드 그리드보다 위에 배치한다.
        */}
        <TodaysNoteCard
          restaurantId={auth.restaurantId}
          ready={auth.ready}
        />

        {/* 핵심 카드 그리드 */}
        <section className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
          <BigCard
            label="오늘 매출"
            value={formatPrice(todayStats.total)}
            sub={`${todayStats.count}건`}
            tone="primary"
          />
          <BigCard
            label="오늘 주문 수"
            value={todayOrders}
            sub={`결제대기 ${counts.PENDING}건 포함`}
          />
          <BigCard
            label="진행 중 주문"
            value={inProgress}
            sub={`신규 ${counts.PAID} · 조리 ${counts.PREPARING} · 완료 ${counts.READY}`}
          />
          <BigCard
            label="신규 주문"
            value={counts.PAID}
            sub="아직 조리 시작 전"
            tone={counts.PAID > 0 ? "warning" : undefined}
          />
          <BigCard
            label="웨이팅"
            value={reservationStats.waiting}
          />
          <BigCard label="예약" value={reservationStats.reservations} />
          <BigCard
            label="사용 중 테이블"
            value={seatStats.occupied}
            sub={`전체 ${seatStats.total}석`}
          />
          <BigCard label="빈 테이블" value={seatStats.empty} />
          <BigCard
            label="결제 대기"
            value={counts.PENDING}
            sub="PENDING 주문"
          />
          <BigCard
            label="취소 주문"
            value={counts.CANCELLED}
            tone={counts.CANCELLED > 0 ? "danger" : undefined}
          />
          <BigCard
            label="카드 결제"
            value={formatPrice(todayStats.card.total)}
            sub={`${todayStats.card.count}건`}
            tone="card"
          />
          <BigCard
            label="현금 결제"
            value={formatPrice(todayStats.cash.total)}
            sub={`${todayStats.cash.count}건`}
            tone="cash"
          />
        </section>

        {orders.error && (
          <div className="bg-red-50 border border-red-200 text-red-700 rounded-card p-4 text-sm">
            <p className="font-semibold">주문 목록을 불러오지 못했습니다</p>
            <p className="text-red-600/90">{orders.error}</p>
          </div>
        )}

        {/* 최근 주문 + 인기 메뉴 */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <section className="lg:col-span-2 bg-white border border-line-divider rounded-card shadow-card overflow-hidden">
            <header className="px-5 py-3 flex items-center justify-between border-b border-line-divider">
              <h2 className="text-base font-bold text-ink-900">최근 주문</h2>
              <Link
                href="/orders"
                className="text-xs text-primary-dark hover:underline"
              >
                전체 보기 →
              </Link>
            </header>
            {recentOrders.length === 0 ? (
              <p className="p-8 text-center text-sm text-ink-500">
                오늘 들어온 주문이 없습니다
              </p>
            ) : (
              <ul className="divide-y divide-line-divider">
                {recentOrders.map((o) => {
                  const tone = STATUS_TONE[o.status];
                  return (
                    <li key={o.id}>
                      <Link
                        href={`/orders/${o.id}`}
                        className="px-5 py-3 hover:bg-gray-50 flex items-center justify-between gap-3"
                      >
                        <div className="min-w-0 flex items-center gap-3">
                          <span className="font-extrabold text-ink-900 tabular-nums">
                            #{shortOrderNumber(o.id)}
                          </span>
                          <span className="text-sm text-ink-700 truncate">
                            {o.customer?.name ?? "손님"}
                          </span>
                        </div>
                        <div className="flex items-center gap-3 text-xs">
                          <span className="text-ink-500">
                            {formatTimeAgo(o.createdAt)}
                          </span>
                          <span className="text-sm font-semibold text-ink-900 tabular-nums">
                            {formatPrice(o.totalPrice)}
                          </span>
                          <span
                            className={`px-2 py-0.5 rounded-chip border border-current/30 ${tone.text} bg-white text-[11px] font-semibold`}
                          >
                            {STATUS_LABEL[o.status]}
                          </span>
                        </div>
                      </Link>
                    </li>
                  );
                })}
              </ul>
            )}
          </section>

          <section className="bg-white border border-line-divider rounded-card shadow-card overflow-hidden">
            <header className="px-5 py-3 border-b border-line-divider">
              <h2 className="text-base font-bold text-ink-900">인기 메뉴</h2>
              <p className="text-[11px] text-ink-500 mt-0.5">
                오늘 좌석 결제 기준 (백엔드 미연동)
              </p>
            </header>
            {topMenus.length === 0 ? (
              <p className="p-8 text-center text-sm text-ink-500">
                오늘 결제된 메뉴가 없습니다
              </p>
            ) : (
              <ol className="divide-y divide-line-divider">
                {topMenus.map((m, idx) => (
                  <li
                    key={m.name + idx}
                    className="px-5 py-3 flex items-center justify-between gap-3"
                  >
                    <div className="flex items-center gap-3 min-w-0">
                      <span className="inline-flex h-6 w-6 rounded-full bg-primary-surface text-primary-dark items-center justify-center text-xs font-bold tabular-nums">
                        {idx + 1}
                      </span>
                      <span className="text-sm text-ink-900 truncate">
                        {m.name}
                      </span>
                    </div>
                    <div className="text-right">
                      <p className="text-sm font-bold tabular-nums">
                        {m.qty}건
                      </p>
                      <p className="text-[11px] text-ink-500 tabular-nums">
                        {formatPrice(m.revenue)}
                      </p>
                    </div>
                  </li>
                ))}
              </ol>
            )}
          </section>
        </div>
      </div>
    </AppShell>
  );
}

function BigCard({
  label,
  value,
  sub,
  tone,
}: {
  label: string;
  value: number | string;
  sub?: string;
  tone?: "primary" | "warning" | "danger" | "card" | "cash";
}) {
  const cls =
    tone === "primary"
      ? "bg-primary-dark text-white border-primary-dark"
      : tone === "warning"
        ? "bg-orange-50 border-orange-200 text-orange-800"
        : tone === "danger"
          ? "bg-red-50 border-red-200 text-state-error"
          : tone === "card"
            ? "bg-primary-surface border-primary-light text-primary-dark"
            : tone === "cash"
              ? "bg-emerald-50 border-emerald-200 text-emerald-800"
              : "bg-white border-line-divider text-ink-900";
  const subCls =
    tone === "primary"
      ? "opacity-80"
      : tone === "warning"
        ? "text-orange-700/80"
        : tone === "danger"
          ? "text-red-600/80"
          : tone === "card"
            ? "text-primary-dark/70"
            : tone === "cash"
              ? "text-emerald-700/80"
              : "text-ink-500";
  const labelCls =
    tone === "primary" ? "opacity-80" : "text-ink-700/90";

  return (
    <div className={`rounded-card border shadow-card p-4 ${cls}`}>
      <p className={"text-[11px] font-medium " + labelCls}>{label}</p>
      <p className="text-2xl font-extrabold mt-1 tabular-nums tracking-tight">
        {value}
      </p>
      {sub && <p className={"text-[11px] mt-0.5 " + subCls}>{sub}</p>}
    </div>
  );
}
