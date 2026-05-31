"use client";

import { use, useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import AppShell from "@/components/AppShell";
import CancelModal from "@/components/CancelModal";
import {
  cancelOrder,
  chargeViaPosToss,
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

  // POS-13: Toss POS 시뮬 결제 모달 상태.
  //   payOpen        — 결제수단 선택 모달 열림 여부
  //   payMethod      — 'CARD' (POS 토스 카드) | 'CASH' (현금)
  //   receivedText   — 현금 결제 시 사장이 받은 금액(원). 거스름돈 계산용.
  //                    문자열로 들고 있다가 제출 직전 number 로 변환 — 입력 중
  //                    "5000" 의 0/공백 상태를 자연스럽게 유지하기 위함.
  //   payBusy        — 백엔드 호출 진행 중 여부 (버튼 disable + 라벨 변경)
  const [payOpen, setPayOpen] = useState(false);
  const [payMethod, setPayMethod] = useState<"CARD" | "CASH">("CARD");
  const [receivedText, setReceivedText] = useState("");
  const [payBusy, setPayBusy] = useState(false);

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

  // POS-13: 결제 모달 열기 — 매번 입력값 초기화.
  //   결제 모달이 다시 열렸을 때 이전 입력값이 남아 있으면 오작동(엉뚱한
  //   거스름돈) 가능성. 매번 깨끗한 상태로 시작한다.
  const openPayModal = () => {
    setPayMethod("CARD");
    setReceivedText("");
    setPayOpen(true);
  };

  // POS-13: 결제 확정 — 백엔드 chargeViaPosToss 호출.
  //   - CASH 인데 받은 금액 < 총액 → 클라이언트에서 가드 (UX 친화 에러)
  //   - 성공: 토스트 + load() 재조회로 상태가 PAID 칩으로 갱신
  //   - 실패: 토스트 에러, 모달은 그대로 두어 재시도 가능
  const onConfirmPay = async () => {
    if (!order) return;
    const received =
      payMethod === "CASH" ? Number(receivedText.replace(/[^0-9]/g, "")) : 0;
    if (
      payMethod === "CASH" &&
      (Number.isNaN(received) || received < order.totalPrice)
    ) {
      setToast({ tone: "error", text: "받은 금액이 부족합니다" });
      return;
    }
    setPayBusy(true);
    setError(null);
    try {
      await chargeViaPosToss(
        order.id,
        payMethod,
        payMethod === "CASH" ? received : undefined,
      );
      setPayOpen(false);
      setToast({ tone: "success", text: "결제 완료" });
      await load();
    } catch (e) {
      const msg = e instanceof Error ? e.message : "결제 실패";
      setToast({ tone: "error", text: msg });
      setError(msg);
    } finally {
      setPayBusy(false);
    }
  };

  // POS-13: 거스름돈 계산 — 현금 결제 시 받은 금액에서 총액 차감.
  //   "5,000" 같은 콤마 입력도 허용 (숫자 외 문자 strip 후 변환).
  //   음수면 "부족" 으로 표시되도록 컴포넌트에서 분기.
  const receivedNumber = receivedText
    ? Number(receivedText.replace(/[^0-9]/g, ""))
    : 0;
  const change = order ? receivedNumber - order.totalPrice : 0;

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
              {/*
                POS-13 Toss POS 시뮬 결제 버튼.
                  - PENDING(결제 대기) 상태에서만 노출 — 매장 워크인 손님이
                    아직 결제 전인 주문만 대상.
                  - 빨강 강조 — 결제 행위가 가장 두드러진 액션이 되도록.
                  - 클릭 시 결제수단 선택 모달 오픈.
              */}
              {order.status === "PENDING" && (
                <button
                  type="button"
                  onClick={openPayModal}
                  disabled={busy || payBusy}
                  className="flex-1 h-12 rounded-button bg-state-error text-white font-semibold hover:opacity-90 active:scale-[0.99] transition disabled:opacity-50"
                >
                  Toss POS로 결제
                </button>
              )}
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

      {/*
        POS-13 결제수단 선택 모달.
          - 카드/현금 라디오 — 단순 UI 로 시연 임팩트 우선.
          - CASH 선택 시 받은 금액 입력 + 거스름돈 자동 표시 (실시간 계산).
          - 확인 → onConfirmPay() → 백엔드 호출 → 상태 PAID 칩 갱신.
          - 별도 컴포넌트로 분리하지 않은 이유: 본 페이지 외 사용처가 없고
            결제 상태(payMethod/receivedText) 가 페이지 로컬에 묶여 있어
            props 드릴이 오히려 복잡해짐.
      */}
      {payOpen && order && (
        <div
          className="fixed inset-0 z-50 bg-black/40 flex items-end sm:items-center justify-center p-4"
          role="dialog"
          aria-modal="true"
          onClick={() => !payBusy && setPayOpen(false)}
        >
          <div
            className="bg-white rounded-card shadow-elevated max-w-md w-full p-6 space-y-4"
            onClick={(e) => e.stopPropagation()}
          >
            <header className="flex items-baseline justify-between">
              <h2 className="text-lg font-bold text-ink-900">결제 처리</h2>
              <span className="text-xs text-ink-500">
                #{shortOrderNumber(order.id)}
              </span>
            </header>

            <div className="bg-gray-50 rounded-input p-3 flex items-baseline justify-between">
              <span className="text-sm text-ink-500">총 결제 금액</span>
              <span className="text-h2 font-bold text-ink-900">
                {formatPrice(order.totalPrice)}
              </span>
            </div>

            <div className="space-y-2">
              <p className="text-sm font-semibold text-ink-700">결제수단</p>
              <div className="grid grid-cols-2 gap-2">
                {/*
                  각 라디오를 큼직한 카드 형태로 변환. 시연 시 사장님이
                  손가락으로 명확히 선택할 수 있도록 hit area 확보.
                */}
                <label
                  className={
                    "h-14 rounded-button border-2 flex items-center justify-center gap-2 cursor-pointer text-sm font-semibold " +
                    (payMethod === "CARD"
                      ? "border-primary bg-primary-surface text-primary-dark"
                      : "border-line-border bg-white text-ink-700")
                  }
                >
                  <input
                    type="radio"
                    name="payMethod"
                    value="CARD"
                    checked={payMethod === "CARD"}
                    onChange={() => setPayMethod("CARD")}
                    className="sr-only"
                  />
                  카드
                </label>
                <label
                  className={
                    "h-14 rounded-button border-2 flex items-center justify-center gap-2 cursor-pointer text-sm font-semibold " +
                    (payMethod === "CASH"
                      ? "border-primary bg-primary-surface text-primary-dark"
                      : "border-line-border bg-white text-ink-700")
                  }
                >
                  <input
                    type="radio"
                    name="payMethod"
                    value="CASH"
                    checked={payMethod === "CASH"}
                    onChange={() => setPayMethod("CASH")}
                    className="sr-only"
                  />
                  현금
                </label>
              </div>
            </div>

            {/*
              CASH 선택 시에만 받은 금액 입력 노출.
              거스름돈 = 받은 금액 - 총액. 음수면 빨강으로 "부족" 표시.
            */}
            {payMethod === "CASH" && (
              <div className="space-y-2">
                <label className="text-sm font-semibold text-ink-700">
                  받은 금액
                </label>
                <input
                  type="text"
                  inputMode="numeric"
                  value={receivedText}
                  onChange={(e) => setReceivedText(e.target.value)}
                  placeholder="0"
                  className="w-full h-12 px-3 rounded-input border border-line-border text-right text-base tabular-nums focus:outline-none focus:border-primary"
                />
                <div className="bg-yellow-50 rounded-input p-3 flex items-baseline justify-between">
                  <span className="text-sm text-ink-500">거스름돈</span>
                  <span
                    className={
                      "text-base font-bold tabular-nums " +
                      (change < 0 ? "text-state-error" : "text-ink-900")
                    }
                  >
                    {change < 0
                      ? `부족 ${formatPrice(Math.abs(change))}`
                      : formatPrice(change)}
                  </span>
                </div>
              </div>
            )}

            <div className="flex gap-2 pt-2">
              <button
                type="button"
                onClick={() => setPayOpen(false)}
                disabled={payBusy}
                className="flex-1 h-12 rounded-button border border-line-border bg-white text-ink-700 font-medium hover:bg-gray-50 disabled:opacity-50"
              >
                취소
              </button>
              <button
                type="button"
                onClick={onConfirmPay}
                disabled={
                  payBusy ||
                  (payMethod === "CASH" && change < 0)
                }
                className="flex-1 h-12 rounded-button bg-primary text-white font-semibold hover:bg-primary-dark active:scale-[0.99] disabled:opacity-50"
              >
                {payBusy ? "처리 중…" : "결제 확인"}
              </button>
            </div>
          </div>
        </div>
      )}
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
