"use client";

import { use, useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import AppShell from "@/components/AppShell";
import CancelModal from "@/components/CancelModal";
import { cancelOrder, getOrderById, updateOrderStatus } from "@/lib/api/pos";
import {
  STATUS_LABEL,
  STATUS_TONE,
  isCancellable,
  nextStatus,
  nextStatusLabel,
} from "@/lib/utils/status";
import { formatPrice, formatTime, shortOrderNumber } from "@/lib/utils/format";
import { useAuth } from "@/lib/hooks/useAuth";
import type { Order } from "@/lib/types";

interface Props {
  params: Promise<{ id: string }>;
}

export default function OrderDetailPage({ params }: Props) {
  const { id } = use(params);
  const auth = useAuth();
  const router = useRouter();

  const [order, setOrder] = useState<Order | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [cancelOpen, setCancelOpen] = useState(false);
  const [cancelBusy, setCancelBusy] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    try {
      const data = await getOrderById(id);
      setOrder(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : "조회 실패");
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (!auth.ready || !auth.restaurantId) return;
    load();
  }, [auth.ready, auth.restaurantId, load]);

  const advance = async () => {
    if (!order) return;
    const next = nextStatus(order.status);
    if (!next) return;
    setBusy(true);
    setError(null);
    try {
      await updateOrderStatus(order.id, next);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "상태 변경 실패");
    } finally {
      setBusy(false);
    }
  };

  const onConfirmCancel = async (o: Order, reason: string) => {
    setCancelBusy(true);
    setError(null);
    try {
      await cancelOrder(o.id, reason);
      setCancelOpen(false);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "취소 실패");
    } finally {
      setCancelBusy(false);
    }
  };

  const tone = order ? STATUS_TONE[order.status] : null;
  const next = order ? nextStatus(order.status) : null;
  const nextLabel = order ? nextStatusLabel(order.status) : null;

  return (
    <AppShell>
      <div className="max-w-3xl mx-auto px-screen-x py-6 space-y-5">
        <button
          type="button"
          onClick={() => router.back()}
          className="inline-flex items-center gap-1 text-sm text-ink-700 hover:text-ink-900"
        >
          <span aria-hidden>←</span> 뒤로
        </button>

        {loading && (
          <div className="bg-white border border-line-divider rounded-card p-6 text-sm text-ink-500">
            불러오는 중…
          </div>
        )}

        {error && (
          <div className="bg-red-50 border border-red-200 text-red-700 rounded-card p-4 text-sm">
            {error}
          </div>
        )}

        {order && tone && (
          <article className={`rounded-card border-2 ${tone.border} ${tone.bg} p-6 shadow-card`}>
            <header className="flex items-baseline justify-between gap-4">
              <div className="min-w-0">
                <p className="text-xs font-medium text-ink-500">주문 번호</p>
                <h1 className="text-h1 text-ink-900 mt-1">
                  #{shortOrderNumber(order.id)}
                </h1>
                <p className="text-xs text-ink-500 mt-1 break-all font-mono">
                  {order.id}
                </p>
              </div>
              <span
                className={`shrink-0 px-3 py-1 rounded-chip text-xs font-semibold ${tone.text} bg-white border border-current/30`}
              >
                {order.statusLabel ?? STATUS_LABEL[order.status]}
              </span>
            </header>

            <dl className="mt-5 grid grid-cols-2 gap-3 text-sm">
              <Row label="손님">
                {order.customer?.name ?? "—"}
                {order.customer?.org ? ` / ${order.customer.org}` : ""}
              </Row>
              <Row label="총액">
                <span className="font-bold text-ink-900">
                  {formatPrice(order.totalPrice)}
                </span>
              </Row>
              <Row label="생성">{formatTime(order.createdAt)}</Row>
              <Row label="갱신">{formatTime(order.updatedAt)}</Row>
              {order.paymentKey && (
                <Row label="결제키" full>
                  <span className="break-all text-xs font-mono text-ink-700">
                    {order.paymentKey}
                  </span>
                </Row>
              )}
            </dl>

            <section className="mt-6">
              <h2 className="text-sm font-semibold text-ink-700 mb-2">메뉴</h2>
              {order.items && order.items.length > 0 ? (
                <ul className="bg-white rounded-input border border-line-divider divide-y divide-line-divider">
                  {order.items.map((it, idx) => (
                    <li
                      key={idx}
                      className="p-3 flex items-center justify-between text-sm"
                    >
                      <span>
                        {it.name}{" "}
                        <span className="text-ink-500">×{it.quantity}</span>
                      </span>
                      {typeof it.price === "number" && (
                        <span className="text-ink-700 tabular-nums">
                          {formatPrice(it.price * it.quantity)}
                        </span>
                      )}
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="text-sm text-ink-500 italic bg-white rounded-input border border-line-divider p-3">
                  메뉴 항목 정보 없음 — 백엔드 응답에 items[] 추가 필요
                </p>
              )}
            </section>

            <div className="mt-6 flex gap-2">
              {next && (
                <button
                  type="button"
                  onClick={advance}
                  disabled={busy}
                  className="flex-1 h-12 rounded-button bg-primary text-white font-semibold hover:bg-primary-dark active:scale-[0.99] transition disabled:opacity-50"
                >
                  {busy ? "처리 중…" : nextLabel}
                </button>
              )}
              {isCancellable(order.status) && (
                <button
                  type="button"
                  onClick={() => setCancelOpen(true)}
                  disabled={busy}
                  className="h-12 px-5 rounded-button border border-line-border bg-white text-ink-700 font-medium hover:bg-gray-50 disabled:opacity-50"
                >
                  취소
                </button>
              )}
            </div>
          </article>
        )}
      </div>

      <CancelModal
        order={cancelOpen ? order : null}
        onClose={() => !cancelBusy && setCancelOpen(false)}
        onConfirm={onConfirmCancel}
        busy={cancelBusy}
      />
    </AppShell>
  );
}

function Row({
  label,
  children,
  full = false,
}: {
  label: string;
  children: React.ReactNode;
  full?: boolean;
}) {
  return (
    <div className={full ? "col-span-2" : ""}>
      <dt className="text-xs text-ink-500 mb-0.5">{label}</dt>
      <dd className="text-sm text-ink-900">{children}</dd>
    </div>
  );
}
