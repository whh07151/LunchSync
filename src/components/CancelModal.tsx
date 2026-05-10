"use client";

import { useState } from "react";
import { shortOrderNumber } from "@/lib/utils/format";
import type { Order } from "@/lib/types";

interface Props {
  order: Order | null;
  onClose: () => void;
  onConfirm: (order: Order, reason: string) => Promise<void> | void;
  busy?: boolean;
}

const PRESETS = ["고객 요청", "재료 소진", "조리 불가", "결제 오류"];

export default function CancelModal({ order, onClose, onConfirm, busy = false }: Props) {
  const [reason, setReason] = useState("");

  if (!order) return null;

  const trimmed = reason.trim();
  const canSubmit = trimmed.length > 0 && !busy;

  return (
    <div
      className="fixed inset-0 z-50 bg-black/50 backdrop-blur-sm flex items-end sm:items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="bg-white rounded-sheet sm:rounded-card w-full max-w-md p-6 shadow-elevated"
        onClick={(e) => e.stopPropagation()}
      >
        <header>
          <h2 className="text-h2 text-ink-900">
            주문 #{shortOrderNumber(order.id)} 취소
          </h2>
          <p className="text-sm text-ink-700 mt-1">
            취소 사유는 필수입니다.{" "}
            <span className="text-ink-500">
              (POS-13: Toss 실 환불 미연결 — 상태만 CANCELLED 처리)
            </span>
          </p>
        </header>

        <div className="mt-4 flex flex-wrap gap-2">
          {PRESETS.map((p) => (
            <button
              key={p}
              type="button"
              onClick={() => setReason(p)}
              className={
                "px-3 py-1.5 rounded-chip text-sm border font-medium transition-colors " +
                (reason === p
                  ? "border-primary bg-primary-surface text-primary-dark"
                  : "border-line-border text-ink-700 hover:bg-gray-50")
              }
            >
              {p}
            </button>
          ))}
        </div>

        <textarea
          className="mt-3 w-full border border-line-border rounded-input p-3 text-sm focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/15 resize-none"
          rows={3}
          placeholder="기타 사유를 입력하거나 위 칩을 선택"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
        />

        <div className="mt-5 flex gap-2 justify-end">
          <button
            type="button"
            onClick={onClose}
            disabled={busy}
            className="h-11 px-4 rounded-button border border-line-border text-ink-700 text-sm font-medium hover:bg-gray-50 disabled:opacity-50"
          >
            닫기
          </button>
          <button
            type="button"
            onClick={() => canSubmit && onConfirm(order, trimmed)}
            disabled={!canSubmit}
            className="h-11 px-5 rounded-button bg-state-error text-white text-sm font-semibold hover:opacity-90 disabled:opacity-50"
          >
            {busy ? "처리 중…" : "취소 확정"}
          </button>
        </div>
      </div>
    </div>
  );
}
