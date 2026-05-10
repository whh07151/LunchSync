# LunchSync POS 개발 로그

**시작일:** 2026-05-07
**기준 문서:** `docs/POS_BUILD_GUIDE.md`(메인) + `docs/LUNCHSYNC_DTO.md` §1·§2·§10·§11·§12 + `docs/LUNCHSYNC_SPECIFICATION.md` §4·§6 + `docs/LUNCHSYNC_CODE_GUIDE.md` §3 (점주앱 컬러 팔레트)

---

## 0. 결정 사항

- **기술 스택:** Next.js 15 (App Router) + React 19 + TypeScript 5 + Tailwind 3 — `POS_BUILD_GUIDE.md §2` 그대로 채택
- **디렉터리 구조:** `src/` 사용. 루트의 Flutter 스캐폴드(`lib/main.dart`, `pubspec.yaml`, `web/index.html`)는 그대로 두어 충돌 회피 — `tsconfig.json` `exclude`에 Flutter 디렉터리 명시
- **JWT 저장:** `localStorage` (편의). 매장 PC 환경 전환 시 `httpOnly Cookie`로 마이그레이션 권장 — `POS_BUILD_GUIDE.md §10` 체크리스트
- **컬러:** 점주앱 팔레트(`#1DBFA3` primary) — `LUNCHSYNC_CODE_GUIDE.md §3`

---

## 1. 작업한 파일

### 설정 (8개, 신규)
| 파일 | 역할 |
|---|---|
| `package.json` | next 15, react 19, tailwindcss 3, typescript 5 |
| `tsconfig.json` | path alias `@/*` → `./src/*`, Flutter 디렉터리 exclude |
| `next.config.mjs` | 환경변수 노출 (BACKEND_BASE_URL, POLLING_INTERVAL_MS) |
| `tailwind.config.ts` | 점주앱 컬러 팔레트, 8px 그리드, `flash` 키프레임(호출 보드 깜박임) |
| `postcss.config.mjs` | tailwind + autoprefixer |
| `.eslintrc.json` | next/core-web-vitals |
| `next-env.d.ts` | Next 자동 생성 + 빌드 시 routes.d.ts 참조 자동 추가됨 |
| `.env.local.example` | `NEXT_PUBLIC_BACKEND_BASE_URL`, `NEXT_PUBLIC_POLLING_INTERVAL_MS=3000` |

### 소스 (`src/`, 22개, 신규)
```
src/
├── app/
│   ├── layout.tsx            루트 레이아웃 + 한국어 lang + Noto Sans
│   ├── globals.css           tailwind 베이스 + 호출 보드 풀스크린 클래스
│   ├── page.tsx              로그인 여부에 따라 /login 또는 /dashboard 리다이렉트
│   ├── login/page.tsx        카카오 토큰 / JWT 직접 입력 두 모드 + 식당 ID 수동 입력
│   ├── dashboard/page.tsx    PAID·PREPARING·READY 3컬럼 칸반 + 통계 카드 + 취소 모달
│   ├── kitchen/page.tsx      PAID·PREPARING만 큰 카드로 + 한 번 탭 상태 전이
│   ├── board/page.tsx        READY 주문번호 풀스크린, 신규 진입 시 깜박임+사운드
│   ├── orders/[id]/page.tsx  단일 주문 상세 + 상태 전이/취소
│   └── stats/page.tsx        결제 상태별 통계 + 평균 처리 시간 + 비율 바
├── lib/
│   ├── types/index.ts        Order, OrderStatus, OrderStats, AuthResult, ApiResponse
│   ├── utils/format.ts       formatPrice/formatTimeAgo/shortOrderNumber
│   ├── utils/status.ts       STATUS_LABEL/TONE/STEP, nextStatus, isCancellable
│   ├── utils/sound.ts        WebAudio 기반 비프음 (외부 파일 의존 없음)
│   ├── api/client.ts         JWT 자동 첨부 fetch wrapper, 304 처리, ApiError
│   ├── api/auth.ts           POST /auth/kakao
│   ├── api/pos.ts            getOrders, getOrderStats, updateOrderStatus, cancelOrder, getOrderById
│   ├── hooks/useAuth.ts      localStorage 동기화 + login/logout
│   ├── hooks/usePolling.ts   3초 폴링 + visibilitychange로 자동 중단/재시작 + AbortController
│   ├── hooks/useOrders.ts    usePolling + getOrders
│   └── hooks/useStats.ts     usePolling(5초) + getOrderStats
└── components/
    ├── AppShell.tsx          상단 헤더 + 라우트 가드 (미로그인 시 /login 강제)
    ├── OrderCard.tsx         compact/regular/large 사이즈, 다음 상태 버튼 + 취소
    ├── KanbanColumn.tsx      칼럼 + 카운트 배지
    ├── StatsCards.tsx        5상태 카운트 + 매출
    ├── CancelModal.tsx       사유 칩 4개 + 자유 입력 (사유 필수)
    └── EmptyState.tsx        공통 비어있음 표시
```

### 진행도 / 로그 (1개, 신규)
- `POS_DEV_LOG.md` (이 파일)

### 기존 파일 수정
- `.gitignore` — Next.js 산출물(`/.next/`, `/node_modules/`, `.env.local` 등) 추가

### 보존
- `docs/` 9개 — 룰 문서, 손대지 않음
- `lib/main.dart`, `pubspec.yaml`, `web/`, `.dart_tool/` — Flutter 스캐폴드 보존 (사용자가 정리 결정하도록 둠). `tsconfig.json` exclude로 Next.js 컴파일 대상에서 제외

---

## 2. 페이지 별 동작

| 라우트 | 화면 | 폴링 | 액션 |
|---|---|---|---|
| `/` | 자동 리다이렉트 | — | 로그인 여부 판별 |
| `/login` | 로그인 폼 | — | 카카오 토큰 → POST /auth/kakao 또는 JWT 직접 입력. 식당 ID 수동 입력 |
| `/dashboard` | 칸반 + 통계 | 주문 3초 / 통계 5초 | PAID→PREPARING→READY→COMPLETED 단계 전이, 취소 모달 |
| `/kitchen` | 주방 모드 (큰 글씨) | 3초 | PAID·PREPARING만 표시, 한 번 탭 전이, 신규 진입 시 사운드 |
| `/board` | 호출 보드 (전광판) | 3초 (status=READY) | READY 진입 시 깜박임 6초 + 사운드 |
| `/orders/[id]` | 주문 상세 | — (수동 새로고침) | 상태 전이 + 취소. 메뉴 항목 표시 |
| `/stats` | 통계 | 5초 | 상태별 비율 바, 평균 처리 시간(클라이언트 계산) |

---

## 3. 명세 정합성 체크

| 항목 | 명세 | 구현 |
|---|---|---|
| 폴링 3초 | `POS_BUILD_GUIDE §7` | `NEXT_PUBLIC_POLLING_INTERVAL_MS` 기본 3000 |
| 백그라운드 폴링 중단 | `LUNCHSYNC_SPECIFICATION §4` | `usePolling` `visibilitychange` 처리 |
| 304 폴링 최적화 | `LUNCHSYNC_SPECIFICATION §7` (백엔드 미구현) | 클라이언트는 304 수신 시 데이터 유지하도록 처리해 둠 |
| 데이터 레이어 인터페이스 분리 | `POS_BUILD_GUIDE §7` (WebSocket 교체 대비) | `lib/api/pos.ts` 함수 단위로 분리, 훅이 함수만 호출 |
| Supabase 직접 접근 금지 | `LUNCHSYNC_SPECIFICATION §4` | Supabase JS 의존성 없음 — NestJS API만 호출 |
| ENUM 값 | `LUNCHSYNC_SPECIFICATION §6` | `OrderStatus` 6개만 사용. ACCEPTED/DONE 잔재값 미사용 |
| 공통 응답 포맷 | `LUNCHSYNC_DTO §1` | `ApiResponse<T>` 처리, 에러 코드 그대로 throw |
| JWT 헤더 | `LUNCHSYNC_DTO §공통` | `Authorization: Bearer` 자동 첨부 |
| 컬러 팔레트 | `LUNCHSYNC_CODE_GUIDE §3` | primary `#1DBFA3` 외 5색 모두 반영 |
| 큰 글씨 + 사운드 알림 (주방용) | `POS_BUILD_GUIDE §8` | OrderCard size="large", playNewOrderChime |
| 호출 보드 깜박임/풀스크린 | `POS_BUILD_GUIDE §8` | `animate-flash` 6초 + 어두운 배경 |
| 잘못된 상태 전이 차단 | `POS_BUILD_GUIDE §10` | `nextStatus()`로 정해진 단계만 노출, READY는 PREPARING만 가능 등 |
| 취소 사유 필수 | `POS_BUILD_GUIDE §10` | CancelModal에서 trim 후 빈값이면 버튼 비활성 |

---

## 4. 백엔드 협의 필요 사항 (POS_BUILD_GUIDE §11)

| # | 항목 | 현재 임시 처리 | 정식 처리 시 영향 받는 파일 |
|---|---|---|---|
| 1 | POS 로그인 방식 | `/login`에서 카카오 토큰 / JWT 직접 입력 두 모드 제공 | `src/app/login/page.tsx`, `src/lib/api/auth.ts` |
| 2 | `users.restaurant_id` FK | 식당 ID를 사용자가 수동 입력해 localStorage 저장 | `src/lib/hooks/useAuth.ts` (자동 추출로 교체) |
| 3 | `GET /pos/orders/:restaurantId` 응답 보강 (`customer`, `items[]`, `statusLabel`) | OrderCard·OrderDetailPage가 모두 optional로 처리 — 비면 "메뉴 정보 미연동" 표시 | `src/lib/types/index.ts` (선택→필수 전환), `OrderCard.tsx` 의 fallback 제거 |
| 4 | Toss 실 환불 (POS-13) | 백엔드가 status만 CANCELLED 처리 → POS는 그대로 호출 | 변경 없음 (백엔드 내부 작업) |
| 5 | FCM 푸시 알림 | 폴링으로만 신규 주문 감지 → WebAudio chime | 알림 권한 요청 + Service Worker 도입 시 신규 파일 |
| 6 | 304 Not Modified | 클라이언트는 수신 가능, 백엔드 미구현 | 변경 없음 (백엔드 추가만) |

또한 **백엔드 컨트롤러 경로 충돌**:
- `LUNCHSYNC_PROGRESS.md` 86~89번째 줄: `GET /pos/restaurants/:id/orders`, `GET /pos/restaurants/:id/stats`
- `POS_BUILD_GUIDE.md §3` / `LUNCHSYNC_DTO.md §12`: `GET /pos/orders/:restaurantId`

→ 본 클라이언트는 **공식 명세(GUIDE/DTO)** 경로를 채택. 실 백엔드와 어긋나면 `src/lib/api/pos.ts` 한 곳만 교체.

---

## 5. 검증

```bash
cd C:/Users/user/StudioProjects/LS_POS
npm install            # 355 packages
npx tsc --noEmit       # exit 0 (타입 오류 0건)
npx next build         # ✓ 9 routes 생성, 컴파일 성공
```

빌드 결과 (정적/동적):
```
○ /              1.72 kB    /board     4.31 kB    /dashboard 3.00 kB
○ /kitchen       1.26 kB    /login     3.10 kB    /stats     4.61 kB
ƒ /orders/[id]   5.00 kB
First Load JS: 102 kB (shared)
```

---

## 6. 실행 방법

```powershell
# 환경변수 (.env.local 생성)
# NEXT_PUBLIC_BACKEND_BASE_URL=http://localhost:3000/api
# NEXT_PUBLIC_POLLING_INTERVAL_MS=3000

# 개발 서버
npm run dev          # http://localhost:3000  ※ NestJS 백엔드와 포트 충돌 시 PORT=3001 등으로 변경

# 프로덕션
npm run build && npm start

# 타입 체크 / 린트
npm run typecheck
npm run lint
```

> ⚠️ **포트 충돌:** Next.js·NestJS 모두 기본 3000. 백엔드를 먼저 띄운 환경에선 `npm run dev -- -p 3001` 사용.

---

## 7. 미구현 / 후속 작업

- [ ] `npm run lint` 실행 결과 검증 (이번 빌드는 typecheck만 실행됨)
- [ ] 일/주/월 매출 그래프 — 백엔드 통계 엔드포인트 확장 후
- [ ] FCM Web Push (신규 주문 시) — 백엔드 합의 후
- [ ] httpOnly Cookie 기반 세션 — 매장 PC 운영 전환 시
- [ ] 자동 로그아웃 (JWT 만료 7일) — 토큰 만료 감지 + /login 리다이렉트
- [ ] CORS 화이트리스트 — `backend/src/main.ts` `origin: '*'` 제한 협의
- [ ] 호출 보드 풀스크린 토글 버튼 (`document.requestFullscreen`)
- [ ] Toss 실 환불 연결 (POS-13) — 백엔드 TODO 해소 후 메시지만 변경
- [ ] 점주앱과 디자인 토큰 통일 (Flutter 점주앱 빌드 시작되면 토큰 공유 검토)

---

## 8. 변경 이력

| 날짜 | 내용 |
|---|---|
| 2026-05-07 | 초기 구현 — 7개 페이지 + 공용 레이어. typecheck/build 통과 |
| 2026-05-07 | 로그인 흐름을 고유번호 단일 입력으로 단순화 (`docs/pos_memo.md` 반영) |
| 2026-05-07 | UI 톤 정렬 — Noto Sans KR(next/font/google), POS 컬러를 로열 블루/네이비(#2563EB/#1E40AF)로 교체, 카드/버튼/타이포 LunchSync 점주앱 가이드 §3·§4 정렬 |
| 2026-05-07 | LS_POS/.env 삭제 — 백엔드 전용 비밀키(`SUPABASE_*`, `JWT_SECRET`, `TOSS_SECRET_KEY`)는 `LunchSync/backend/.env` 한 곳에서만 관리 (docs §4 단일 문지기 원칙). LS_POS는 `.env.local`에 `NEXT_PUBLIC_BACKEND_BASE_URL` 한 줄만 |
| 2026-05-07 | 데모 단말 진입 버튼 추가 — 사장앱 미구현 단계에서 UI 미리보기용. seed UUID(rest_001) 사용 |
| 2026-05-07 | 좌석 관리 기능 1차 구현 — `/seats` (8개 기본, ±로 가감), 좌석별 메뉴 추가/수량/마감 드로어. localStorage 식당별 저장. pos_memo §2 반영 |
| 2026-05-07 | 결제 흐름 추가 — 결제하기 → 카드/현금 선택 → (현금: 받은 금액·거스름돈) → 마감. 매출은 `useSales` 훅이 식당별 localStorage에 누적. /seats 상단에 오늘 매출/카드/현금/진행중 카드 4개 |
| 2026-05-07 | pos_memo §5~§9 반영 — 상단바+사이드바 레이아웃, 사이드바 9메뉴(대시보드/주문/테이블/메뉴/웨이팅예약/결제/매출/설정/로그아웃), 신규 페이지 4개(/menu, /reservations, /payments, /settings), /orders 분리, 대시보드 카드 12종 + 최근주문 + 인기메뉴, 영업상태 토글, 단말 시계, 신규주문 알림 배지 |

---

## 10. 좌석 관리 기능 (2026-05-07)

**근거:** `pos_memo.md §2` "주문 들어왔을 시에 좌석 예약/선택" + POS_DEV_LOG 백엔드 협의 #8

### 신규 파일
| 파일 | 역할 |
|---|---|
| `src/lib/types/index.ts` | `Seat`, `SeatItem`, `SeatStatus` 타입 추가 |
| `src/lib/data/demoMenu.ts` | 데모 메뉴 10건 (백엔드 `GET /restaurants/:id/menus` 교체 TODO) |
| `src/lib/hooks/useSeats.ts` | localStorage 기반 좌석 CRUD + stats. 식당 ID별 키 분리 |
| `src/components/SeatCard.tsx` | 좌석 그리드 타일 — 비어있음/사용중 + 사용 시간 + 합계 |
| `src/components/SeatDrawer.tsx` | 우측 드로어 — 담은 메뉴(±/×) + 카테고리 메뉴 그리드 + 결제 마감(2단계 확인) |
| `src/app/seats/page.tsx` | `/seats` 페이지 — 좌석 그리드 + 통계 카드 + ±좌석 가감 |

### 수정
- `src/components/AppShell.tsx` 상단 nav에 "좌석" 추가 (대시보드 ↔ 주방 모드 사이)

### 동작 요약
- 좌석은 **식당 ID별 localStorage**에 저장 (`ls_pos_seats_<restaurantId>`) — 새로고침 후 유지, 다른 단말과는 동기화 안 됨
- 좌석 클릭 → 드로어 열림 → 메뉴 카테고리 탭에서 클릭 시 즉시 +1 (이미 있으면 수량 증가)
- 수량 ±, 단건 삭제, 좌석 비우기(2단계 확인) 지원
- 좌석 가감 — 현재 사용중인 마지막 좌석은 −로 줄여지지 않도록 보호. 최대 32개

### 백엔드 협의 필요 (좌석 모델)

| # | 항목 | 비고 |
|---|---|---|
| 8a | DB 테이블 — `tables`(id, restaurant_id, label, position) | 매장별 좌석 배치 저장 |
| 8b | DB 테이블 — `table_orders`(id, table_id, status, started_at, closed_at, customer_note) | 좌석에 묶인 한 회 주문 단위 |
| 8c | API — `GET /pos/tables/:restaurantId`, `POST /pos/tables/:restaurantId/seat`, `PATCH /pos/tables/:tableId/items`, `POST /pos/tables/:tableId/close` | useSeats가 localStorage 대신 호출하면 멀티 단말 동기화 가능 |
| 8d | 주문 흐름 통합 — 좌석 마감 시 `POST /orders` (paymentMethod=CASH 등) 트리거 → /dashboard 칸반에 반영 | 현재는 좌석↔주문이 분리. 통합되면 전체 매출/통계도 자연스레 합쳐짐 |

### 결제 흐름 (2026-05-07 추가)

`SeatDrawer`는 `mode: "browse" | "paying" | "card" | "cash" | "cancel"` 상태머신:

```
browse  → [결제하기]                 → paying
                                       │
                                       ├─ [카드] → card  (1.2초 시뮬 → ✓ 카드 결제 완료)
                                       │
                                       └─ [현금] → cash  (받은 금액 입력 → 거스름돈 표시)

browse  → [비우기 (결제 없이)]       → cancel  (확인 후 좌석만 비우기)
```

**카드 결제:** 실제 VAN/PG 연동 없음. 1.2초 처리 표시 후 즉시 승인 완료. 매출에는 정상 기록.

**현금 결제:** 받은 금액 입력. "딱 맞게 / +천원 / +5천원 / +만원" 빠른 버튼 4종으로 자주 쓰는 금액 한 번에. 거스름돈 자동 계산. 합계보다 받은 금액이 적으면 결제 버튼 비활성화 + 부족액 표시.

**매출 기록:** `useSales.recordSale()`이 `Sale` 객체를 식당별 localStorage(`ls_pos_sales_<restaurantId>`)에 누적. `Sale.method`로 카드/현금 분리 집계.

### 백엔드 협의 필요 (결제 수단별 매출)

| # | 항목 | 비고 |
|---|---|---|
| 9a | `orders.payment_method` ENUM 컬럼 — CARD/CASH/TOSS | 현재 ENUM 미존재. 추가 시 DTO §10 paymentMethod 그대로 사용 |
| 9b | `GET /pos/sales/:restaurantId/today` API | 결제 수단별 일 매출 집계. 현재 클라이언트에서 useSales가 함 |
| 9c | 카드 결제 VAN/PG 연동 | 현재는 시뮬레이션. 매장용 카드 단말기는 손님앱의 Toss와 별개 (점주의 매장용 카드 결제) |

---

## 11. pos_memo §5~§9 반영 (2026-05-07)

**원칙:** `docs/`(POS_BUILD_GUIDE / DTO / SPECIFICATION / CODE_GUIDE)가 변수명·ENUM·디자인 시스템의 ground truth. `pos_memo.md`는 **흐름/기능/화면 구성**만 참고. 둘이 충돌하면 docs 우선.

### 레이아웃 (pos_memo §6)
- 상단바(sticky) + 좌측 사이드바(데스크톱 고정 / 모바일 토글) + 메인 콘텐츠
- 상단바: LS 배지 + 식당 식별 + 영업상태 토글 + 시계 + 오늘주문 배지(신규 알림 펄스) + 주방모드/호출보드 빠른 진입 + 계정/로그아웃
- 사이드바: 9개 메뉴 (대시보드/주문관리/테이블관리/메뉴관리/웨이팅·예약/결제관리/매출관리/설정/로그아웃)

### 신규 / 변경 라우트

| 라우트 | 변경 |
|---|---|
| `/dashboard` | **재작성** — 카드 12종(매출/주문수/진행중/신규/웨이팅/예약/사용중·빈테이블/결제대기/취소/카드매출/현금매출) + 최근 주문 5건 + 인기 메뉴 5건 |
| `/orders` (신규) | 기존 /dashboard에 있던 칸반(PAID/PREPARING/READY) + 상태 필터 6종 + 주방모드/호출보드 빠른 진입 |
| `/seats` | 기존 — 사이드바 라벨만 "테이블 관리"로. 메뉴 데이터를 `useMenu`에서 가져와 메뉴 관리 변경이 즉시 반영 |
| `/menu` (신규) | 메뉴 추가/가격 수정/품절 토글/삭제. 카테고리 필터 + 폼 모달. 기본값은 `DEMO_MENU`로 시드, 변경은 식당 ID별 localStorage |
| `/reservations` (신규) | 웨이팅·예약 두 탭. 등록·착석처리·취소·삭제. localStorage |
| `/payments` (신규) | useSales 누적 결제 내역. 오늘/전체 + 카드/현금 필터 + 시간순 |
| `/stats` | 기존 — 사이드바 라벨만 "매출 관리"로 |
| `/settings` (신규) | 식당 고유번호·단말 이름 변경, 영업상태 토글, 좌석/메뉴/매출/예약 데이터 비우기, 전체 초기화 + 로그아웃 |
| `/kitchen`, `/board` | 사이드바에서 제외. 상단바·주문관리·설정에서 빠른 링크 |

### 주문 상태 라벨 정리 (pos_memo §9-5)

ENUM은 `LUNCHSYNC_SPECIFICATION §6` 그대로 유지. 라벨만 한글 정렬:

| ENUM | 이전 라벨 | 현재 라벨 (pos_memo §9-5 기준) |
|---|---|---|
| PENDING | 결제 대기 | 결제 대기 |
| PAID | 신규 주문 | 신규 주문 |
| PREPARING | 조리 중 | 조리 중 |
| READY | 픽업 대기 | **조리 완료** |
| COMPLETED | 완료 | **서빙 완료** |
| CANCELLED | 취소 | **취소됨** |

> pos_memo는 7단계(신규주문→주문접수완료→조리중→조리완료→서빙완료→결제대기→결제완료)인데, 손님앱 픽업 흐름의 DB ENUM은 6값(PENDING/PAID/PREPARING/READY/COMPLETED/CANCELLED). 매장 좌석 흐름은 별도(`/seats` SeatDrawer 결제 마감)이므로 두 흐름을 분리해서 운영. ENUM 확장은 백엔드 협의 #9a로 등록.

### 신규 hook (3개)

| 훅 | 역할 |
|---|---|
| `useShopStatus` | 영업중/마감 토글. localStorage `ls_pos_open_<restaurantId>` |
| `useMenu` | 메뉴 CRUD + 품절 토글. localStorage `ls_pos_menu_<restaurantId>`. SeatDrawer가 사용 |
| `useReservations` | 웨이팅·예약 CRUD. localStorage `ls_pos_reservations_<restaurantId>` |

### 백엔드 협의 항목 추가

| # | 항목 | 비고 |
|---|---|---|
| 12a | 영업 상태 — `restaurants.is_open` 또는 별도 `business_status` | 멀티 단말 동기화 |
| 12b | 메뉴 CRUD API — `POST/PATCH/DELETE /pos/menus/:restaurantId` | useMenu가 호출하도록 교체 |
| 12c | 웨이팅·예약 모델 + API | DB 테이블 신규(`waiting_list`, `reservations`) + CRUD |
| 12d | 영업 상태 변경 알림 (FCM 또는 SSE) | 마감 시 손님앱이 신규 세션 차단 |

---

## 9. `docs/pos_memo.md` 반영 (2026-05-07)

**핵심 결정사항 (`POS_BUILD_GUIDE §11-#1·#2`에 대한 확정 답):**
- POS는 **회원가입 없음**. 사장앱에서 식당 등록 시 발급된 **고유번호(restaurant_id)** 로 단말에 로그인
- 식당 정보 등록은 **사장앱 전용**, 메뉴/가격 수정은 **사장앱·POS 둘 다 가능**
- 크롤링 데이터는 초안(사장앱 자동 입력용), 사장 수정값이 최종

### 코드 변경

| 파일 | 변경 |
|---|---|
| `src/app/login/page.tsx` | 카카오 토큰 / JWT 직접 입력 모드 토글 제거. 식당 고유번호 + 단말 이름(선택) 단일 입력. "회원가입 없음" 안내 카드 + "고유번호를 모르겠어요" details 도움말 추가 |
| `src/lib/hooks/useAuth.ts` | `login()` 시그니처에서 `accessToken`·`user`를 optional로 변경. 정식 토큰은 백엔드 합의 후 채워질 값 |
| `src/components/AppShell.tsx` | 인증 가드 기준을 `accessToken` → `restaurantId`로 전환 |
| `src/app/page.tsx` | 자동 리다이렉트 판단도 `restaurantId` 기준으로 통일 |
| `src/lib/api/auth.ts` | `loginWithKakao` 함수는 미사용 상태로 보존 (백엔드가 카카오 SSO를 채택할 가능성 대비) |

### 백엔드 협의 항목 갱신

`§4` 표의 #1·#2 항목 변경 사항:

| # | 이전 | 현재 |
|---|---|---|
| 1 | "POS 로그인 방식 미정 — 카카오 토큰/JWT 직접 입력 두 모드 제공" | **확정 (pos_memo)**: 고유번호 단일 입력. 정식 인증 엔드포인트(예: `POST /pos/login/:restaurantId`) 백엔드 신설 필요 |
| 2 | "users.restaurant_id FK 미존재 → 사용자가 수동 입력" | **확정 (pos_memo)**: 단말이 곧 식당. POS 사용자 모델 자체가 불필요할 수 있음 — 별도 PINs/디바이스 토큰 등 보안 정책은 추가 협의 |

### 추가 백엔드 협의 항목 (pos_memo §2 — POS 기능)

| # | 항목 | 비고 |
|---|---|---|
| 7 | **메뉴/가격 수정** API (`PATCH /pos/menus/:id`?) | pos_memo §2·§4 — POS도 사장앱과 동등한 권한. 백엔드 엔드포인트 미존재 |
| 8 | **좌석 예약/선택** 모델 + API | pos_memo §2 — DB 스키마(`tables`, `reservations`?) 신규 설계 필요 |
| 9 | **결제 수단별(현금/카드) 관리** | 현재 orders.paymentKey만 있고 method 컬럼 없음. ENUM 추가 + 통계 API 보강 필요 |
| 10 | **하루 매출** 별도 엔드포인트 | 현재 `GET /pos/orders/:id/stats`는 누적 통계 — 일/주/월 분리 + 결제수단별 매출 필요 |
| 11 | **크롤링 vs 사장 수정 충돌 처리** | pos_memo §5 결론: 사장 수정값이 최종. AI 재크롤링 시 자동 반영 X, 변경 후보로만 비교. 백엔드 정책으로 강제 |

### POS 추가 화면 (후속 작업, 미구현)

- `/menu` — 메뉴/가격 수정 (사장앱과 권한 동등)
- `/seats` — 좌석 예약·선택 보드
- `/sales` — 일일 매출 + 결제 수단별 분리 (`/stats`와 별도)
- `/setup` — 단말 초기 설정 (고유번호 변경, 화면 모드 선택 등)

