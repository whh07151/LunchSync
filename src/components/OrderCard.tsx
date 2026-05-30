"use client";

import { useRef, useState } from "react";
import {
  STATUS_LABEL,
  STATUS_TONE,
  isCancellable,
  nextStatus,
  nextStatusLabel,
} from "@/lib/utils/status";
import { formatPrice, formatTimeAgo, shortOrderNumber } from "@/lib/utils/format";
import { uploadCompletionPhoto } from "@/lib/api/pos";
import type { Order } from "@/lib/types";

interface Props {
  order: Order;
  onAdvance?: (order: Order) => void;
  onCancel?: (order: Order) => void;
  /// 사진 업로드 성공 시 호출 — 부모가 refetch 트리거 가능 (선택).
  onPhotoUploaded?: (order: Order, photoUrl: string) => void;
  busy?: boolean;
  size?: "compact" | "regular" | "large";
}

export default function OrderCard({
  order,
  onAdvance,
  onCancel,
  onPhotoUploaded,
  busy = false,
  size = "regular",
}: Props) {
  const tone = STATUS_TONE[order.status];
  const next = nextStatus(order.status);
  const nextLabel = nextStatusLabel(order.status);

  // ── 2026-05-31 WOW#2: 사장 라이브 카메라 1장 ─────────────
  // 카메라 아이콘은 PAID/PREPARING 상태에서만 표시 (조리 중 사진 전송).
  // input[type=file] capture=environment 로 단말 후면 카메라 즉시 호출.
  const photoInputRef = useRef<HTMLInputElement | null>(null);
  const [photoBusy, setPhotoBusy] = useState(false);
  const [photoError, setPhotoError] = useState<string | null>(null);
  const showCameraButton =
    order.status === "PAID" || order.status === "PREPARING";

  const onPickPhoto = () => {
    setPhotoError(null);
    photoInputRef.current?.click();
  };

  const onPhotoSelected = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    // input 값 초기화 — 같은 파일 재선택 가능하게.
    e.target.value = "";
    if (!file) return;
    setPhotoBusy(true);
    setPhotoError(null);
    try {
      const result = await uploadCompletionPhoto(order.id, file);
      onPhotoUploaded?.(order, result.completionPhotoUrl);
    } catch (err) {
      setPhotoError(
        err instanceof Error ? err.message : "사진 업로드에 실패했어요",
      );
    } finally {
      setPhotoBusy(false);
    }
  };

  const titleSize =
    size === "large" ? "text-3xl" : size === "compact" ? "text-base" : "text-xl";
  const bodySize = size === "large" ? "text-lg" : "text-sm";
  const cardPadding = size === "large" ? "p-5" : "p-4";

  return (
    <article
      className={`rounded-card border shadow-card ${tone.border} ${tone.bg} ${cardPadding} flex flex-col gap-3`}
    >
      <header className="flex items-baseline justify-between gap-2">
        <div className="flex items-baseline gap-2 min-w-0">
          <span className={`font-extrabold ${titleSize} text-ink-900 tracking-tight`}>
            #{shortOrderNumber(order.id)}
          </span>
          <span className={`${bodySize} text-ink-700 truncate`}>
            {order.customer?.name ?? "손님"}
            {order.customer?.org ? (
              <span className="text-ink-500"> / {order.customer.org}</span>
            ) : null}
          </span>
        </div>
        <span
          className={`px-2 py-0.5 rounded-chip text-[11px] font-semibold ${tone.text} bg-white border border-current/30`}
        >
          {order.statusLabel ?? STATUS_LABEL[order.status]}
        </span>
      </header>

      {order.items && order.items.length > 0 ? (
        <ul className={`${bodySize} text-ink-900 space-y-0.5`}>
          {order.items.map((it, idx) => (
            <li key={idx}>
              {it.name} <span className="text-ink-500">×{it.quantity}</span>
            </li>
          ))}
        </ul>
      ) : (
        <p className={`${bodySize} text-ink-500 italic`}>
          메뉴 정보 미연동 — 상세 보기에서 확인
        </p>
      )}

      <footer className="flex items-center justify-between pt-1 border-t border-line-divider/60">
        <span className="text-base font-bold text-ink-900 pt-2">
          {formatPrice(order.totalPrice)}
        </span>
        <span className="text-xs text-ink-500 pt-2">
          {formatTimeAgo(order.createdAt)}
        </span>
      </footer>

      {(next || isCancellable(order.status) || showCameraButton) && (
        <div className="flex items-center gap-2">
          {next && onAdvance && (
            <button
              type="button"
              onClick={() => onAdvance(order)}
              disabled={busy || photoBusy}
              className="flex-1 h-11 rounded-button bg-primary text-white font-semibold text-sm hover:bg-primary-dark active:scale-[0.99] transition disabled:opacity-50 disabled:active:scale-100"
            >
              {busy ? "처리 중…" : nextLabel}
            </button>
          )}
          {/* 2026-05-31 WOW#2: 카메라 아이콘 — 조리 완료 사진 1장 전송.
              PAID/PREPARING 에서만 노출. 단말 카메라(capture) 즉시 호출. */}
          {showCameraButton && (
            <button
              type="button"
              onClick={onPickPhoto}
              disabled={busy || photoBusy}
              title={
                order.completionPhotoUrl
                  ? "사진 다시 보내기"
                  : "조리 사진 보내기"
              }
              aria-label="조리 사진 보내기"
              className={
                "h-11 w-11 rounded-button border text-sm font-medium inline-flex items-center justify-center disabled:opacity-50 " +
                (order.completionPhotoUrl
                  ? "border-state-success text-state-success bg-white hover:bg-green-50"
                  : "border-line-border text-ink-700 bg-white hover:bg-gray-50")
              }
            >
              {photoBusy ? (
                <span className="inline-block h-4 w-4 rounded-full border-2 border-current border-t-transparent animate-spin" />
              ) : (
                // 인라인 SVG — 의존성 추가 없이 카메라 아이콘 표시
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  className="h-5 w-5"
                  aria-hidden="true"
                >
                  <path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z" />
                  <circle cx="12" cy="13" r="4" />
                </svg>
              )}
            </button>
          )}
          {isCancellable(order.status) && onCancel && (
            <button
              type="button"
              onClick={() => onCancel(order)}
              disabled={busy || photoBusy}
              className="h-11 px-4 rounded-button border border-line-border bg-white text-ink-700 text-sm font-medium hover:bg-gray-50 disabled:opacity-50"
            >
              취소
            </button>
          )}
        </div>
      )}

      {/* 카메라 인풋 — capture=environment 로 단말 후면 카메라 호출.
          데스크톱/시연 환경에서는 파일 선택 다이얼로그로 폴백. */}
      {showCameraButton && (
        <input
          ref={photoInputRef}
          type="file"
          accept="image/*"
          capture="environment"
          className="hidden"
          onChange={onPhotoSelected}
        />
      )}

      {photoError && (
        <p className="text-xs text-state-danger" role="alert">
          {photoError}
        </p>
      )}
      {order.completionPhotoUrl && !photoBusy && !photoError && (
        <p className="text-xs text-state-success">
          사진 전송 완료 — 손님 화면에 표시 중
        </p>
      )}
    </article>
  );
}
