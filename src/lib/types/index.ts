// LunchSync POS 타입 정의 — LUNCHSYNC_DTO.md §12, LUNCHSYNC_SPECIFICATION.md §6 기준

export type OrderStatus =
  | "PENDING"
  | "PAID"
  | "PREPARING"
  | "READY"
  | "COMPLETED"
  | "CANCELLED";
// ACCEPTED, DONE 은 DB ENUM에 잔재로 남아있는 미사용 값. POS는 사용하지 않음.

export type UserRole = "CUSTOMER" | "OWNER" | "POS";

export interface Order {
  id: string;
  sessionId: string;
  userId: string;
  status: OrderStatus;
  totalPrice: number;
  paymentKey?: string | null;
  createdAt: string;
  updatedAt: string;
  // 백엔드 응답 보강 후 채워질 선택 필드 (POS_BUILD_GUIDE.md §3·§11)
  statusLabel?: string;
  customer?: {
    name?: string;
    org?: string;
  };
  items?: Array<{
    name: string;
    quantity: number;
    price?: number;
  }>;
  restaurantId?: string;
}

export interface OrderStats {
  total: number;
  pending: number;
  paid: number;
  preparing: number;
  ready: number;
  completed: number;
  cancelled: number;
  totalRevenue: number;
}

export interface AuthUser {
  id: string;
  name: string;
  profileImage?: string | null;
  role: UserRole;
}

export interface AuthResult {
  accessToken: string;
  isNewUser: boolean;
  user: AuthUser;
}

// pos_memo.md §2 — 좌석 예약/선택. 백엔드 모델 미정 (POS_DEV_LOG 백엔드 협의 #8).
// 현재는 클라이언트 localStorage 전용. 백엔드 합의 후 동일 형태로 API 교체 예정.
export type SeatStatus = "empty" | "occupied";

export interface SeatItem {
  menuId: string;
  name: string;
  price: number;
  quantity: number;
  addedAt: string;
}

export interface Seat {
  id: string; // T1, T2, …
  label: string; // "1번"
  status: SeatStatus;
  items: SeatItem[];
  startedAt?: string; // 첫 메뉴 추가 시점
}

// pos_memo.md §2 — 결제 수단별 관리(현금/카드)
export type PaymentMethod = "CARD" | "CASH";

export interface Sale {
  id: string;
  seatLabel: string; // 마감 시점의 좌석 라벨
  items: SeatItem[]; // 결제 시점 스냅샷
  total: number;
  method: PaymentMethod;
  receivedAmount?: number; // CASH만
  change?: number; // CASH만
  closedAt: string; // ISO
}

// 백엔드 공통 응답 포맷
export interface ApiSuccess<T> {
  success: true;
  data: T;
}

export interface ApiError {
  success: false;
  error: { code: string; message: string };
}

export type ApiResponse<T> = ApiSuccess<T> | ApiError;
