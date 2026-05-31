"use client";

import { use, useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import AppShell from "@/components/AppShell";
import CancelModal from "@/components/CancelModal";
import {
  cancelOrder,
  getOrderById,
  refundOrderSim,
  updateOrderStatus,
} from "@/lib/api/pos";
import {
  STATUS_LABEL,
  STATUS_TONE,
  isCancellable,
  isRefundable,
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
  // POS-09: 환불 시뮬 상태.
  //   refundBusy = 백엔드 호출 진행 중 여부 (버튼 disable + 라벨 변경)
  //   refundConfirmOpen = window.confirm 대용으로 인라인 확인 패널 표시 여부
  //     (모달 컴포넌트는 따로 만들지 않고 카드 안쪽에 confirm 영역만 노출 —
  //      디자인 일관성 + 빠른 시연 우선)
  //   toast = 성공/실패 시 잠시 떠올랐다가 사라지는 알림 메시지
  const [refundBusy, setRefundBusy] = useState(false);
  const [refundConfirmOpen, setRefundConfirmOpen] = useState(false);
  const [toast, setToast] = useState<
    { tone: "success" | "error"; text: string } | null
  >(null);

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

  // POS-09: 환불 시뮬 실행.
  //   "환불 처리" 클릭 → 인라인 확인 패널 노출 → "환불 확정" 클릭 시 백엔드
  //   POST /pos/orders/:id/refund-sim 호출. 성공하면 즉시 load() 로 상세를
  //   재조회 → status 칩이 REFUNDED 로 갱신되고, 토스트가 3초간 뜬다.
  //
  //   reason 은 캡스톤 단계라 별도 입력 UI 없이 "POS 환불 시뮬" 고정 문자열.
  //   실 운영에서는 CancelModal 같은 프리셋 칩 + 자유 입력으로 확장 예정.
  const onConfirmRefund = async () => {
    if (!order) return;
    setRefundBusy(true);
    setError(null);
    try {
      await refundOrderSim(order.id, "POS 환불 시뮬");
      setRefundConfirmOpen(false);
      setToast({ tone: "success", text: "환불이 처리되었습니다 (시뮬)" });
      await load();
    } catch (e) {
      const msg = e instanceof Error ? e.message : "환불 처리 실패";
      setToast({ tone: "error", text: msg });
      setError(msg);
    } finally {
      setRefundBusy(false);
    }
  };

  // 토스트 3초 후 자동 닫힘. tone/text 모두 같은 객체에 묶여 있으니
  // 의존성에 toast 만 넣으면 충분 (객체 참조가 바뀌면 setTimeout 재설정).
  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 3000);
    return () => clearTimeout(t);
  }, [toast]);

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

            <div className="mt-6 flex gap-2 flex-wrap">
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
              {/*
                POS-09 환불 버튼.
                  - PAID/COMPLETED 상태에서만 노출 (isRefundable)
                  - 빨강(state-error) 강조 — "되돌릴 수 없는 액션" 표시
                  - 1차 클릭은 확인 패널만 토글 (실수 방지) → 2차 클릭에서
                    실제 백엔드 호출
              */}
              {isRefundable(order.status) && (
                <button
                  type="button"
                  onClick={() => setRefundConfirmOpen((v) => !v)}
                  disabled={busy || refundBusy}
                  className="h-12 px-5 rounded-button bg-state-error text-white font-semibold hover:opacity-90 active:scale-[0.99] transition disabled:opacity-50"
                >
                  환불 처리
                </button>
              )}
            </div>

            {/*
              POS-09 환불 확인 인라인 패널.
              "환불 처리" 버튼을 누르면 카드 하단에 등장한다. 별도 모달이
              아니라 카드 안쪽에 두어, 사장이 주문 정보(메뉴/금액)를
              눈으로 다시 확인하면서 환불을 확정할 수 있도록 한다.
            */}
            {refundConfirmOpen && isRefundable(order.status) && (
              <div className="mt-4 rounded-card border border-state-error bg-red-50 p-4">
                <p className="text-sm text-red-700 font-semibold">
                  정말 환불 처리하시겠어요?
                </p>
                <p className="text-xs text-red-600/90 mt-1">
                  실제 결제 환불은 수행되지 않으며 상태만 REFUNDED 로
                  변경됩니다. (캡스톤 시뮬레이션)
                </p>
                <div className="mt-3 flex gap-2 justify-end">
                  <button
                    type="button"
                    onClick={() => setRefundConfirmOpen(false)}
                    disabled={refundBusy}
                    className="h-10 px-4 rounded-button border border-line-border bg-white text-sm text-ink-700 font-medium hover:bg-gray-50 disabled:opacity-50"
                  >
                    아니요
                  </button>
                  <button
                    type="button"
                    onClick={onConfirmRefund}
                    disabled={refundBusy}
                    className="h-10 px-5 rounded-button bg-state-error text-white text-sm font-semibold hover:opacity-90 disabled:opacity-50"
                  >
                    {refundBusy ? "처리 중…" : "환불 확정"}
                  </button>
                </div>
              </div>
            )}
          </article>
        )}
      </div>

      {/*
        POS-09 토스트. 성공 시 녹색, 실패 시 빨강. 우상단 고정으로 3초간
        노출. 별도 의존성 없이 컴포넌트 인라인으로 처리한다.
      */}
      {toast && (
        <div
          role="status"
          className={
            "fixed top-4 right-4 z-50 px-4 py-3 rounded-card shadow-elevated text-sm font-semibold " +
            (toast.tone === "success"
              ? "bg-state-success text-white"
              : "bg-state-error text-white")
          }
        >
          {toast.text}
        </div>
      )}

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
