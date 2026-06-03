// LunchSync POS 타입 정의 — LUNCHSYNC_DTO.md §12, LUNCHSYNC_SPECIFICATION.md §6 기준

export type OrderStatus =
  | "PENDING"
  | "PAID"
  | "PREPARING"
  | "READY"
  | "COMPLETED"
  | "CANCELLED"
  // POS-09 (2026-05-31) — 환불 시뮬레이션.
  //   PAID/COMPLETED 주문에 대해 사장이 "환불 처리" 버튼을 누르면 백엔드
  //   (OW-10 추가 중인 POST /pos/orders/:id/refund-sim) 가 status 를
  //   REFUNDED 로 전환한다. 실제 Toss 환불 API 는 미연결 — 캡스톤 시연 단계
  //   에서는 상태값만 기록해 사장이 "이 주문은 환불됐다"는 사실을 식별.
  | "REFUNDED";
// ACCEPTED, DONE 은 DB ENUM에 잔재로 남아있는 미사용 값. POS는 사용하지 않음.

export type UserRole = "CUSTOMER" | "OWNER" | "POS";

export interface Order {
  id: string;
  sessionId: string;
  userId: string;
  status: OrderStatus;
  totalPrice: number;
  paymentKey?: string | null;
  // 결제 수단 — 백엔드 getOrdersByRestaurant 의 select 에 orders.payment_method 가
  // 포함되어 응답에 함께 내려온다. 값 분포(예: 'POS_TOSS' | 'POS_CASH' | 'CARD' |
  // 'TOSS' | null)가 출처별로 섞여 있어 string 으로 받고, 화면 단에서 헬퍼로
  // 현금/카드 2분류로 정규화한다(결제관리 페이지 paymentBucket 참고).
  paymentMethod?: string | null;
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
  // 2026-05-31 WOW#2: 사장이 업로드한 조리 완료 사진 public URL.
  //   null/undefined = 아직 사진 미첨부. 백엔드 GET /orders/:id 또는
  //   POS 목록 응답에 포함 (가능한 경우). POS 가 동일 카드에서 "전송 완료"
  //   배지를 띄울 때 활용.
  completionPhotoUrl?: string | null;
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
  // 2026-05-31 회귀 fix: backend pos.service.getPaymentStats 가 결제수단별
  // 매출(2026-05-13 backend 협의 #9b)을 분리해 내려주는데 LSPOS 타입이 받지
  // 않아 dashboard "오늘 매출/카드 결제" 가 0원으로 표시되는 회귀.
  tossRevenue?: number;
  cardRevenue?: number;
  cashRevenue?: number;
  simulateRevenue?: number;
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
