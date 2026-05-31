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
  // POS-09: 환불 시뮬레이션 — 사장이 "환불 처리" 버튼을 눌러 백엔드가
  //   상태를 REFUNDED 로 바꾼 주문. 실제 결제 환불은 미수행(시뮬).
  REFUNDED: "환불 완료",
};

// statusStep — LUNCHSYNC_DTO.md §10
export const STATUS_STEP: Record<OrderStatus, number> = {
  PENDING: 1,
  PAID: 2,
  PREPARING: 3,
  READY: 4,
  COMPLETED: 5,
  CANCELLED: 0,
  // 환불도 종료 상태이므로 진행도 0(트랙 외) 으로 둔다 — 손님 진행 바에서
  // "조리 5단계 라인" 밖으로 빠지도록 의도.
  REFUNDED: 0,
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
  // 환불은 CANCELLED 와 톤을 구분 — 회계 의미가 다르므로 보라/자주색 계열로
  // 차별. tailwind 표준 fuchsia 팔레트를 사용해 별도 디자인 토큰 의존 X.
  REFUNDED: { bg: "bg-fuchsia-50", border: "border-fuchsia-200", text: "text-fuchsia-700" },
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

// POS-09 (2026-05-31) — 환불 시뮬레이션 가능 여부.
//   "환불 처리" 버튼은 손님이 이미 결제한 주문에만 노출되어야 한다.
//   - PAID      : 결제는 됐지만 조리 시작 전 (조리 시작 전 환불)
//   - COMPLETED : 서빙까지 끝났지만 사후 환불 (가장 흔한 회계 시나리오)
//   PREPARING/READY 도 이론상 환불 가능하지만, 캡스톤 시연 시나리오는
//   "결제 직후" 또는 "사후 처리" 두 케이스에 집중하기 위해 일단 두 상태로
//   한정. 백엔드 OW-10 라우트도 동일 가드를 가질 예정 — 프론트에서 막아도
//   서버에서 한 번 더 확인하므로 이중 안전.
export function isRefundable(status: OrderStatus): boolean {
  return status === "PAID" || status === "COMPLETED";
}
