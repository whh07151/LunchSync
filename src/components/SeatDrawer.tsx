"use client";

import { useEffect, useMemo, useState } from "react";
import { formatPrice, formatTimeAgo } from "@/lib/utils/format";
import { seatItemCount, seatTotal } from "@/lib/hooks/useSeats";
import type { MenuItem } from "@/lib/hooks/useMenu";
import type { PaymentMethod, Seat, SeatItem } from "@/lib/types";

interface PaidPayload {
  seatId: string;
  seatLabel: string;
  items: SeatItem[];
  total: number;
  method: PaymentMethod;
  receivedAmount?: number;
  change?: number;
}

interface Props {
  seat: Seat | null;
  menuItems: MenuItem[];
  categories: string[];
  onClose: () => void;
  onAddItem: (
    seatId: string,
    item: { menuId: string; name: string; price: number }
  ) => void;
  onDecreaseItem: (seatId: string, menuId: string) => void;
  onRemoveItem: (seatId: string, menuId: string) => void;
  onPaid: (payload: PaidPayload) => void;
  onCancelSeat: (seatId: string) => void;
}

type Mode = "browse" | "paying" | "card" | "cash" | "cancel";

const QUICK_AMOUNTS = [
  { label: "딱 맞게", round: 0 },
  { label: "+ 천원", round: 1000 },
  { label: "+ 5천원", round: 5000 },
  { label: "+ 만원", round: 10000 },
];

function roundUpTo(value: number, step: number): number {
  if (step <= 0) return value;
  return Math.ceil(value / step) * step;
}

export default function SeatDrawer({
  seat,
  menuItems,
  categories,
  onClose,
  onAddItem,
  onDecreaseItem,
  onRemoveItem,
  onPaid,
  onCancelSeat,
}: Props) {
  const [category, setCategory] = useState<string>("전체");
  const [mode, setMode] = useState<Mode>("browse");
  const [received, setReceived] = useState<number | "">("");
  const [cardApproving, setCardApproving] = useState(false);

  // 좌석 바뀌면 상태 리셋
  useEffect(() => {
    setCategory("전체");
    setMode("browse");
    setReceived("");
    setCardApproving(false);
  }, [seat?.id]);

  // 카드 모드 진입 시 1.2초 시뮬레이션 후 승인 완료 표시
  useEffect(() => {
    if (mode !== "card") return;
    setCardApproving(true);
    const t = setTimeout(() => setCardApproving(false), 1200);
    return () => clearTimeout(t);
  }, [mode]);

  const filteredMenu = useMemo(() => {
    if (category === "전체") return menuItems;
    return menuItems.filter((m) => m.category === category);
  }, [menuItems, category]);

  if (!seat) return null;

  const total = seatTotal(seat);
  const itemCount = seatItemCount(seat);
  const hasItems = seat.items.length > 0;

  const receivedNum = typeof received === "number" ? received : 0;
  const change = Math.max(0, receivedNum - total);
  const cashOk = receivedNum >= total && total > 0;

  const finalize = (
    method: PaymentMethod,
    extra?: { receivedAmount?: number; change?: number }
  ) => {
    onPaid({
      seatId: seat.id,
      seatLabel: seat.label,
      items: seat.items,
      total,
      method,
      ...extra,
    });
    onClose();
  };

  const headerCaption =
    mode === "paying"
      ? "결제 수단을 선택하세요"
      : mode === "card"
        ? "카드 결제"
        : mode === "cash"
          ? "현금 결제"
          : mode === "cancel"
            ? "좌석 비우기"
            : seat.status === "occupied" && seat.startedAt
              ? `사용 시작 ${formatTimeAgo(seat.startedAt)}`
              : "비어있음";

  return (
    <div
      className="fixed inset-0 z-50 bg-black/40 flex justify-end"
      onClick={onClose}
    >
      <aside
        className="w-full sm:max-w-md bg-bg-page h-full overflow-y-auto shadow-elevated flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        {/* 헤더 */}
        <header className="bg-white border-b border-line-divider px-5 py-4 flex items-center justify-between sticky top-0 z-10">
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              {mode !== "browse" && (
                <button
                  type="button"
                  onClick={() =>
                    mode === "card" || mode === "cash"
                      ? setMode("paying")
                      : setMode("browse")
                  }
                  className="text-ink-700 hover:text-ink-900 text-sm"
                  aria-label="뒤로"
                >
                  ←
                </button>
              )}
              <h2 className="text-h2 text-ink-900 truncate">
                {seat.label} 테이블
              </h2>
            </div>
            <p className="text-xs text-ink-500 mt-0.5">{headerCaption}</p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="h-9 w-9 inline-flex items-center justify-center rounded-full hover:bg-gray-100 text-ink-700"
            aria-label="닫기"
          >
            ✕
          </button>
        </header>

        {/* === BROWSE: 담은 메뉴 + 메뉴 추가 === */}
        {mode === "browse" && (
          <>
            <ItemsSection
              seat={seat}
              total={total}
              itemCount={itemCount}
              onAddItem={onAddItem}
              onDecreaseItem={onDecreaseItem}
              onRemoveItem={onRemoveItem}
              editable
            />

            <section className="px-5 py-4 flex-1">
              <h3 className="text-sm font-semibold text-ink-700 mb-3">메뉴 추가</h3>

              <div className="flex gap-1.5 overflow-x-auto -mx-1 px-1 pb-2 mb-3">
                {categories.map((c) => (
                  <button
                    key={c}
                    type="button"
                    onClick={() => setCategory(c)}
                    className={
                      "shrink-0 px-3 py-1.5 rounded-chip text-xs font-semibold border " +
                      (category === c
                        ? "bg-primary text-white border-primary"
                        : "bg-white text-ink-700 border-line-border hover:bg-gray-50")
                    }
                  >
                    {c}
                  </button>
                ))}
              </div>

              <div className="grid grid-cols-2 gap-2">
                {filteredMenu.map((m) => (
                  <button
                    key={m.id}
                    type="button"
                    disabled={m.soldOut}
                    onClick={() =>
                      !m.soldOut &&
                      onAddItem(seat.id, {
                        menuId: m.id,
                        name: m.name,
                        price: m.price,
                      })
                    }
                    className={
                      "text-left rounded-card p-3 transition-colors active:scale-[0.99] " +
                      (m.soldOut
                        ? "bg-gray-50 border border-line-divider opacity-60 cursor-not-allowed"
                        : "bg-white border border-line-divider hover:border-primary hover:bg-primary-surface")
                    }
                  >
                    <div className="flex items-center gap-1.5">
                      <p className="text-sm font-semibold text-ink-900 truncate">
                        {m.name}
                      </p>
                      {m.soldOut && (
                        <span className="text-[9px] font-bold px-1 py-0.5 rounded-chip bg-state-error text-white shrink-0">
                          품절
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-ink-500 mt-0.5">{m.category}</p>
                    <p className="text-sm font-bold text-primary-dark mt-1.5">
                      {formatPrice(m.price)}
                    </p>
                  </button>
                ))}
              </div>

              <p className="text-[11px] text-ink-500 mt-3">
                ※ 메뉴는 메뉴 관리 화면에서 추가/수정/품절 처리할 수 있습니다.
              </p>
            </section>

            {/* footer: 결제하기 + 비우기 */}
            <footer className="bg-white border-t border-line-divider p-4 sticky bottom-0">
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={() => setMode("cancel")}
                  disabled={!hasItems}
                  className="h-12 px-4 rounded-button border border-line-border bg-white text-ink-700 font-medium hover:bg-gray-50 disabled:opacity-40"
                >
                  비우기
                </button>
                <button
                  type="button"
                  onClick={() => setMode("paying")}
                  disabled={!hasItems}
                  className="flex-1 h-12 rounded-button bg-primary text-white font-semibold hover:bg-primary-dark active:scale-[0.99] transition disabled:opacity-50"
                >
                  결제하기 · {formatPrice(total)}
                </button>
              </div>
            </footer>
          </>
        )}

        {/* === PAYING: 영수증 + 카드/현금 선택 === */}
        {mode === "paying" && (
          <>
            <ItemsSection
              seat={seat}
              total={total}
              itemCount={itemCount}
              receiptOnly
              title="영수증 확인"
            />
            <section className="px-5 py-5 flex-1">
              <p className="text-sm font-semibold text-ink-700 mb-3">결제 수단</p>
              <div className="grid grid-cols-2 gap-3">
                <PaymentMethodButton
                  emoji="💳"
                  label="카드"
                  onClick={() => setMode("card")}
                />
                <PaymentMethodButton
                  emoji="💵"
                  label="현금"
                  onClick={() => {
                    setReceived(total);
                    setMode("cash");
                  }}
                />
              </div>
            </section>
          </>
        )}

        {/* === CARD: 시뮬레이션 후 승인 === */}
        {mode === "card" && (
          <>
            <ItemsSection
              seat={seat}
              total={total}
              itemCount={itemCount}
              receiptOnly
              title="영수증"
            />
            <section className="px-5 py-8 flex-1 flex flex-col items-center justify-center text-center">
              {cardApproving ? (
                <>
                  <Spinner />
                  <p className="text-sm text-ink-700 mt-3">카드 승인 처리 중…</p>
                  <p className="text-[11px] text-ink-500 mt-1">
                    실제 VAN/PG 연동은 미구현 (데모 시뮬레이션)
                  </p>
                </>
              ) : (
                <>
                  <div className="h-14 w-14 rounded-full bg-state-success/15 text-state-success inline-flex items-center justify-center text-3xl">
                    ✓
                  </div>
                  <p className="text-h2 text-ink-900 mt-3">
                    카드 결제 완료
                  </p>
                  <p className="text-base font-bold text-primary-dark mt-1">
                    {formatPrice(total)}
                  </p>
                </>
              )}
            </section>
            <footer className="bg-white border-t border-line-divider p-4 sticky bottom-0">
              <button
                type="button"
                onClick={() => finalize("CARD")}
                disabled={cardApproving}
                className="w-full h-12 rounded-button bg-primary text-white font-semibold hover:bg-primary-dark transition disabled:opacity-50"
              >
                완료
              </button>
            </footer>
          </>
        )}

        {/* === CASH: 받은 금액 + 거스름돈 === */}
        {mode === "cash" && (
          <>
            <ItemsSection
              seat={seat}
              total={total}
              itemCount={itemCount}
              receiptOnly
              title="영수증"
            />
            <section className="px-5 py-5 flex-1 space-y-4">
              <div>
                <label className="block text-xs font-medium text-ink-700 mb-1.5">
                  받은 금액
                </label>
                <input
                  type="number"
                  inputMode="numeric"
                  value={received === "" ? "" : received}
                  onChange={(e) => {
                    const v = e.target.value;
                    setReceived(v === "" ? "" : Math.max(0, Number(v)));
                  }}
                  className="w-full h-14 border border-line-border rounded-input px-3 text-2xl font-bold text-right tabular-nums focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/15"
                  placeholder="0"
                />
                <div className="grid grid-cols-4 gap-1.5 mt-2">
                  {QUICK_AMOUNTS.map((q) => (
                    <button
                      key={q.label}
                      type="button"
                      onClick={() =>
                        setReceived(
                          q.round === 0 ? total : roundUpTo(total, q.round)
                        )
                      }
                      className="h-10 rounded-chip border border-line-border bg-white text-xs font-semibold text-ink-700 hover:bg-gray-50"
                    >
                      {q.label}
                    </button>
                  ))}
                </div>
              </div>

              <div className="bg-white rounded-card border border-line-divider p-4 space-y-2">
                <Row label="결제 합계" value={formatPrice(total)} />
                <Row
                  label="받은 금액"
                  value={
                    receivedNum > 0 ? formatPrice(receivedNum) : "—"
                  }
                />
                <div className="border-t border-line-divider pt-2">
                  <Row
                    label="거스름돈"
                    value={
                      cashOk ? formatPrice(change) : (
                        <span className="text-state-error text-sm">
                          {receivedNum < total
                            ? `${formatPrice(total - receivedNum)} 모자람`
                            : "—"}
                        </span>
                      )
                    }
                    accent
                  />
                </div>
              </div>
            </section>
            <footer className="bg-white border-t border-line-divider p-4 sticky bottom-0">
              <button
                type="button"
                onClick={() =>
                  finalize("CASH", {
                    receivedAmount: receivedNum,
                    change,
                  })
                }
                disabled={!cashOk}
                className="w-full h-12 rounded-button bg-primary text-white font-semibold hover:bg-primary-dark transition disabled:opacity-50"
              >
                결제 완료 {cashOk && `· 거스름돈 ${formatPrice(change)}`}
              </button>
            </footer>
          </>
        )}

        {/* === CANCEL: 결제 없이 비우기 === */}
        {mode === "cancel" && (
          <>
            <ItemsSection
              seat={seat}
              total={total}
              itemCount={itemCount}
              receiptOnly
              title="비울 항목"
            />
            <section className="px-5 py-6 flex-1">
              <div className="bg-red-50 border border-red-200 rounded-card p-4 text-sm text-state-error">
                <p className="font-semibold mb-1">결제 없이 비웁니다</p>
                <p>
                  담긴 메뉴 {itemCount}건이 결제 기록 없이 삭제됩니다. 매출에
                  반영되지 않으니 결제가 끝났다면 뒤로가서 결제하기를
                  사용하세요.
                </p>
              </div>
            </section>
            <footer className="bg-white border-t border-line-divider p-4 sticky bottom-0">
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={() => setMode("browse")}
                  className="flex-1 h-12 rounded-button border border-line-border bg-white text-ink-700 font-medium hover:bg-gray-50"
                >
                  뒤로
                </button>
                <button
                  type="button"
                  onClick={() => {
                    onCancelSeat(seat.id);
                    onClose();
                  }}
                  className="flex-1 h-12 rounded-button bg-state-error text-white font-semibold hover:opacity-90"
                >
                  네, 비우기
                </button>
              </div>
            </footer>
          </>
        )}
      </aside>
    </div>
  );
}

/* ───── 영수증/메뉴 영역 (browse: editable, 그 외: receiptOnly) ───── */
function ItemsSection({
  seat,
  total,
  itemCount,
  editable = false,
  receiptOnly = false,
  title = "담은 메뉴",
  onAddItem,
  onDecreaseItem,
  onRemoveItem,
}: {
  seat: Seat;
  total: number;
  itemCount: number;
  editable?: boolean;
  receiptOnly?: boolean;
  title?: string;
  onAddItem?: (
    seatId: string,
    item: { menuId: string; name: string; price: number }
  ) => void;
  onDecreaseItem?: (seatId: string, menuId: string) => void;
  onRemoveItem?: (seatId: string, menuId: string) => void;
}) {
  return (
    <section className="px-5 py-4 bg-white border-b border-line-divider">
      <h3 className="text-sm font-semibold text-ink-700 mb-2">{title}</h3>
      {seat.items.length === 0 ? (
        <p className="text-sm text-ink-500 italic py-2">
          아직 담긴 메뉴가 없습니다. 아래에서 골라 담으세요.
        </p>
      ) : (
        <ul className="divide-y divide-line-divider">
          {seat.items.map((it) => (
            <li
              key={it.menuId}
              className="py-2.5 flex items-center justify-between gap-3"
            >
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium text-ink-900 truncate">
                  {it.name}
                </p>
                <p className="text-xs text-ink-500">
                  {formatPrice(it.price)}
                  {receiptOnly && it.quantity > 1 ? ` × ${it.quantity}` : ""}
                </p>
              </div>
              {editable ? (
                <div className="flex items-center gap-1">
                  <button
                    type="button"
                    onClick={() => onDecreaseItem?.(seat.id, it.menuId)}
                    className="h-8 w-8 rounded-full border border-line-border bg-white text-ink-700 hover:bg-gray-50 inline-flex items-center justify-center"
                    aria-label="수량 감소"
                  >
                    −
                  </button>
                  <span className="w-7 text-center text-sm font-bold tabular-nums">
                    {it.quantity}
                  </span>
                  <button
                    type="button"
                    onClick={() =>
                      onAddItem?.(seat.id, {
                        menuId: it.menuId,
                        name: it.name,
                        price: it.price,
                      })
                    }
                    className="h-8 w-8 rounded-full bg-primary text-white hover:bg-primary-dark inline-flex items-center justify-center"
                    aria-label="수량 증가"
                  >
                    +
                  </button>
                  <button
                    type="button"
                    onClick={() => onRemoveItem?.(seat.id, it.menuId)}
                    className="ml-1 h-8 w-8 rounded-full text-ink-500 hover:bg-red-50 hover:text-state-error inline-flex items-center justify-center"
                    aria-label="삭제"
                  >
                    ×
                  </button>
                </div>
              ) : (
                <span className="text-sm font-semibold text-ink-900 tabular-nums">
                  {formatPrice(it.price * it.quantity)}
                </span>
              )}
            </li>
          ))}
        </ul>
      )}

      {seat.items.length > 0 && (
        <div className="mt-3 pt-3 border-t border-line-divider flex items-baseline justify-between">
          <span className="text-sm text-ink-700">
            총 <span className="font-semibold">{itemCount}건</span>
          </span>
          <span className="text-xl font-extrabold text-ink-900">
            {formatPrice(total)}
          </span>
        </div>
      )}
    </section>
  );
}

function PaymentMethodButton({
  emoji,
  label,
  onClick,
}: {
  emoji: string;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="aspect-[5/4] rounded-card border-2 border-line-divider bg-white hover:border-primary hover:bg-primary-surface flex flex-col items-center justify-center gap-1.5 transition-colors active:scale-[0.99]"
    >
      <span className="text-3xl" aria-hidden>
        {emoji}
      </span>
      <span className="text-base font-bold text-ink-900">{label}</span>
    </button>
  );
}

function Row({
  label,
  value,
  accent = false,
}: {
  label: string;
  value: React.ReactNode;
  accent?: boolean;
}) {
  return (
    <div className="flex items-baseline justify-between">
      <span className="text-sm text-ink-700">{label}</span>
      <span
        className={
          accent
            ? "text-xl font-extrabold text-primary-dark tabular-nums"
            : "text-sm font-semibold text-ink-900 tabular-nums"
        }
      >
        {value}
      </span>
    </div>
  );
}

function Spinner() {
  return (
    <div
      className="h-10 w-10 rounded-full border-4 border-primary/20 border-t-primary animate-spin"
      aria-label="처리 중"
    />
  );
}
