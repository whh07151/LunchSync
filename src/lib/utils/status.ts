import type { OrderStatus } from "@/lib/types";

// LUNCHSYNC_SPECIFICATION.md §6 + POS_BUILD_GUIDE.md §4 기준 ENUM 유지.
// 라벨은 pos_memo.md §9-5 "주문 상태"에 맞춰 한글 정렬.
export const STATUS_LABEL: Record<OrderStatus, string> = {
  PENDING: "결제 대기",
  PAID: "신규 주문",
  PREPARING: "조리 중",
  READY: "조리 완료",
  COMPLETED: "서빙 완료",
  CANCELLED: "취소됨",
};

// statusStep — LUNCHSYNC_DTO.md §10
export const STATUS_STEP: Record<OrderStatus, number> = {
  PENDING: 1,
  PAID: 2,
  PREPARING: 3,
  READY: 4,
  COMPLETED: 5,
  CANCELLED: 0,
};

export const STATUS_TONE: Record<
  OrderStatus,
  { bg: string; border: string; text: string }
> = {
  PENDING: { bg: "bg-gray-50", border: "border-gray-200", text: "text-gray-600" },
  PAID: { bg: "bg-primary-surface", border: "border-primary", text: "text-primary-dark" },
  PREPARING: { bg: "bg-orange-50", border: "border-status-preparing", text: "text-orange-700" },
  READY: { bg: "bg-yellow-50", border: "border-status-ready", text: "text-yellow-800" },
  COMPLETED: { bg: "bg-gray-50", border: "border-gray-200", text: "text-gray-500" },
  CANCELLED: { bg: "bg-red-50", border: "border-status-cancelled", text: "text-red-700" },
};

// 다음 상태 전이 (POS 흐름: PAID → PREPARING → READY → COMPLETED)
export function nextStatus(current: OrderStatus): OrderStatus | null {
  switch (current) {
    case "PAID":
      return "PREPARING";
    case "PREPARING":
      return "READY";
    case "READY":
      return "COMPLETED";
    default:
      return null;
  }
}

export function nextStatusLabel(current: OrderStatus): string | null {
  const next = nextStatus(current);
  if (!next) return null;
  switch (next) {
    case "PREPARING":
      return "조리 시작";
    case "READY":
      return "조리 완료";
    case "COMPLETED":
      return "서빙 완료";
    default:
      return STATUS_LABEL[next];
  }
}

// POS 화면에 노출되는 활성 상태 (PENDING/COMPLETED/CANCELLED 은 일반적으로 보드/칸반에 안 띄움)
export const ACTIVE_STATUSES: OrderStatus[] = ["PAID", "PREPARING", "READY"];

export function isCancellable(status: OrderStatus): boolean {
  return status === "PAID" || status === "PREPARING";
}
