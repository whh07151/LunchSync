"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { useAuth } from "@/lib/hooks/useAuth";
import { useOrders } from "@/lib/hooks/useOrders";
import { useShopStatus } from "@/lib/hooks/useShopStatus";

// pos_memo §6 — 상단바 + 좌측 사이드바 + 메인 콘텐츠.
// 사이드바 메뉴는 §6-3에 명시된 9개. /kitchen, /board는 사이드바 외 별도 진입(상단바 빠른링크).

interface NavItem {
  href: string;
  label: string;
  icon: string;
}

const NAV: NavItem[] = [
  { href: "/dashboard", label: "대시보드", icon: "▤" },
  { href: "/orders", label: "주문 관리", icon: "🧾" },
  { href: "/seats", label: "테이블 관리", icon: "▦" },
  { href: "/menu", label: "메뉴 관리", icon: "♨" },
  { href: "/reservations", label: "웨이팅·예약", icon: "🕒" },
  { href: "/payments", label: "결제 관리", icon: "💳" },
  { href: "/stats", label: "매출 관리", icon: "📈" },
  { href: "/settings", label: "설정", icon: "⚙" },
];

interface Props {
  children: React.ReactNode;
  bare?: boolean; // 호출 보드 등 풀스크린 페이지
}

export default function AppShell({ children, bare = false }: Props) {
  const pathname = usePathname();
  const router = useRouter();
  const auth = useAuth();
  const { open: shopOpen, ready: shopReady, toggle: toggleShop } =
    useShopStatus(auth.restaurantId);
  const orders = useOrders(auth.restaurantId, undefined, auth.ready);

  const [now, setNow] = useState<Date>(new Date());
  const [sidebarOpen, setSidebarOpen] = useState(false);

  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    if (!auth.ready) return;
    if (!auth.restaurantId && pathname !== "/login") {
      router.replace("/login");
    }
  }, [auth.ready, auth.restaurantId, pathname, router]);

  // 라우트 이동 시 모바일 사이드바 닫기
  useEffect(() => {
    setSidebarOpen(false);
  }, [pathname]);

  if (bare) {
    return <main className="min-h-screen">{children}</main>;
  }

  const orderList = orders.data ?? [];
  const todayCount = orderList.length;
  const newCount = orderList.filter((o) => o.status === "PAID").length;

  const dateLabel = now.toLocaleDateString("ko-KR", {
    month: "2-digit",
    day: "2-digit",
    weekday: "short",
  });
  const timeLabel = now.toLocaleTimeString("ko-KR", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });

  return (
    <div className="min-h-screen flex flex-col bg-bg-page">
      {/* === 상단바 === */}
      <header className="bg-white shadow-header sticky top-0 z-30">
        <div className="h-14 px-4 sm:px-6 flex items-center justify-between gap-3">
          <div className="flex items-center gap-3 min-w-0">
            <button
              type="button"
              onClick={() => setSidebarOpen((v) => !v)}
              className="lg:hidden h-9 w-9 inline-flex items-center justify-center rounded-lg hover:bg-gray-100 text-ink-700"
              aria-label="메뉴"
            >
              ☰
            </button>
            <Link href="/dashboard" className="flex items-center gap-2 shrink-0">
              <span className="inline-flex h-7 w-7 rounded-lg bg-primary text-white items-center justify-center font-bold text-sm">
                LS
              </span>
              <span className="font-bold text-base text-ink-900 hidden sm:inline">
                {auth.restaurantId
                  ? `식당 ${auth.restaurantId.slice(0, 6)}…`
                  : "POS"}
              </span>
            </Link>
            <button
              type="button"
              onClick={() => shopReady && toggleShop()}
              className={
                "ml-1 inline-flex items-center gap-1.5 px-2.5 py-1 rounded-chip text-xs font-semibold border transition-colors " +
                (shopOpen
                  ? "bg-emerald-50 border-emerald-200 text-emerald-700 hover:bg-emerald-100"
                  : "bg-gray-100 border-gray-300 text-ink-700 hover:bg-gray-200")
              }
            >
              <span
                className={
                  "h-1.5 w-1.5 rounded-full " +
                  (shopOpen ? "bg-emerald-500 animate-pulse" : "bg-ink-500")
                }
              />
              {shopOpen ? "영업중" : "마감"}
            </button>
          </div>

          <div className="hidden md:flex items-center gap-3 text-sm text-ink-700 tabular-nums">
            <span>{dateLabel}</span>
            <span className="font-bold text-ink-900 text-base">{timeLabel}</span>
          </div>

          <div className="flex items-center gap-2">
            <Link
              href="/orders"
              className="hidden sm:inline-flex items-center gap-1.5 px-3 py-1.5 rounded-chip text-xs font-semibold bg-primary-surface border border-primary-light text-primary-dark hover:bg-primary-light/20"
              title="오늘 주문 수"
            >
              오늘 주문 <span className="font-extrabold">{todayCount}</span>
              {newCount > 0 && (
                <span
                  className="ml-1 inline-flex items-center justify-center h-5 min-w-5 px-1.5 rounded-full bg-state-error text-white text-[10px] font-bold animate-pulse"
                  aria-label={`신규 주문 ${newCount}건`}
                >
                  {newCount}
                </span>
              )}
            </Link>
            <Link
              href="/kitchen"
              className="hidden lg:inline-flex h-9 px-3 rounded-chip text-xs font-semibold border border-line-border bg-white text-ink-700 hover:bg-gray-50 items-center"
            >
              주방 모드
            </Link>
            <Link
              href="/board"
              className="hidden lg:inline-flex h-9 px-3 rounded-chip text-xs font-semibold border border-line-border bg-white text-ink-700 hover:bg-gray-50 items-center"
            >
              호출 보드
            </Link>
            <span className="hidden sm:inline text-xs text-ink-700 mx-1">
              <span className="font-medium text-ink-900">
                {auth.user?.name ?? "POS"}
              </span>
            </span>
            <button
              type="button"
              onClick={() => {
                auth.logout();
                router.replace("/login");
              }}
              className="h-9 px-3 rounded-chip border border-line-border bg-white hover:bg-gray-50 text-xs font-medium text-ink-700"
            >
              로그아웃
            </button>
          </div>
        </div>
      </header>

      <div className="flex-1 flex">
        {/* === 좌측 사이드바 === */}
        <aside
          className={
            "fixed lg:static inset-y-0 left-0 top-14 lg:top-0 w-60 bg-white border-r border-line-divider flex-col z-20 transition-transform " +
            (sidebarOpen
              ? "translate-x-0 flex"
              : "-translate-x-full lg:translate-x-0 lg:flex hidden")
          }
        >
          <nav className="flex-1 p-3 space-y-1 overflow-y-auto">
            {NAV.map((n) => {
              const active =
                pathname === n.href || pathname.startsWith(n.href + "/");
              return (
                <Link
                  key={n.href}
                  href={n.href}
                  className={
                    "flex items-center gap-2.5 h-11 px-3 rounded-input text-sm font-medium transition-colors " +
                    (active
                      ? "bg-primary-surface text-primary-dark border border-primary-light/60"
                      : "text-ink-700 hover:bg-gray-100 border border-transparent")
                  }
                >
                  <span className="text-base shrink-0" aria-hidden>
                    {n.icon}
                  </span>
                  <span>{n.label}</span>
                </Link>
              );
            })}
          </nav>
          <div className="p-3 border-t border-line-divider">
            <button
              type="button"
              onClick={() => {
                auth.logout();
                router.replace("/login");
              }}
              className="w-full h-11 rounded-input text-sm font-medium text-ink-700 hover:bg-gray-100 flex items-center gap-2.5 px-3 border border-transparent"
            >
              <span aria-hidden>↩</span>
              <span>로그아웃</span>
            </button>
          </div>
        </aside>

        {/* 모바일 사이드바 dim */}
        {sidebarOpen && (
          <div
            className="fixed inset-0 top-14 z-10 bg-black/30 lg:hidden"
            onClick={() => setSidebarOpen(false)}
            aria-hidden
          />
        )}

        {/* === 메인 === */}
        <main className="flex-1 min-w-0">{children}</main>
      </div>
    </div>
  );
}
