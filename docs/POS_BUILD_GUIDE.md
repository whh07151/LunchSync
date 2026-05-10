# LunchSync POS 제작 가이드

**작성일:** 2026-05-07
**기준 문서:** `LUNCHSYNC_SPECIFICATION.md`, `LUNCHSYNC_DTO.md`, `LUNCHSYNC_CODE_GUIDE.md`, `LUNCHSYNC_PROGRESS.md`
**목적:** LunchSync 시스템에서 POS 웹을 처음부터 제작할 때 필요한 모든 사항 정리

---

## 1. POS의 역할과 위치

### 전체 시스템 구조

```
손님앱 (Flutter, Android/iOS)         ─┐
점주앱 (Flutter, Android/iOS)         ─┼─→ NestJS 서버 ─→ Supabase PostgreSQL
POS 웹 (Next.js)  ← 본 가이드 대상     ─┘     (단일 문지기)         (DB 전용)
```

### POS의 책임

- **주방/카운터용 웹 화면**으로 손님이 결제 완료한 주문을 받아 처리
- 점주앱과 분리된 별도 클라이언트(현재 구조 가정상 매장 카운터 PC/태블릿용)
- 주문 상태 전이의 후반 단계(`PAID → PREPARING → READY → COMPLETED`)를 담당
- 호출(픽업 안내) 보드 표시

### 명세에 정의된 POS 화면 (미구현)

| ID | 기능 | 상태 |
|---|---|---|
| POS-07 | POS 주방 모드 | ❌ 미구현 |
| POS-08 | 점주 주문 목록 (백엔드만 완료) | ❌ UI 미구현 |
| POS-09 | 결제 상태별 통계 (백엔드만 완료) | ❌ UI 미구현 |
| POS-10 | 호출 결과 보드 | ❌ 미구현 |
| POS-13 | 취소/환불 (Toss 실제 환불 API 미연결) | ⚠️ 백엔드 TODO |

---

## 2. 기술 스택 (확정)

| 영역 | 기술 |
|---|---|
| 프레임워크 | **Next.js** (App Router 권장) |
| 언어 | TypeScript |
| 통신 | HTTP API (NestJS 백엔드 호출) |
| 인증 | JWT (`Authorization: Bearer ...`) |
| 실시간 | **폴링 3초 간격** (WebSocket 교체 가능성 있음 — 데이터 레이어 인터페이스 분리 권장) |
| DB 접근 | ❌ Supabase 직접 접근 절대 금지. NestJS API만 호출 |

> **아키텍처 원칙:** Flutter/POS 어떤 클라이언트든 Supabase에 직접 접근 금지. NestJS가 단일 문지기(권한 검증/트랜잭션) 역할.

---

## 3. POS 전용 백엔드 API (이미 구현 완료)

base URL 가정: `https://{backend-host}/api`
모든 요청 헤더: `Authorization: Bearer {jwt}`, `Content-Type: application/json`

| Method | 경로 | 역할 |
|---|---|---|
| GET | `/pos/orders/:restaurantId` | 점주/POS용 주문 목록 (status 쿼리 필터 지원) |
| GET | `/pos/orders/:restaurantId/stats` | 결제 상태별 통계 |
| PATCH | `/pos/orders/:orderId/status` | 주문 상태 변경 (PREPARING/READY/COMPLETED) |
| POST | `/pos/orders/:orderId/cancel` | 취소/환불 (실제 Toss 환불은 TODO) |

### 응답 예시

`GET /pos/orders/:restaurantId?status=PAID`
```json
{
  "success": true,
  "data": [
    {
      "id": "order_uuid",
      "sessionId": "session_uuid",
      "userId": "user_uuid",
      "status": "PAID",
      "totalPrice": 13000,
      "paymentKey": "toss_key",
      "createdAt": "2026-04-08T12:00:00",
      "updatedAt": "2026-04-08T12:00:00"
    }
  ]
}
```

`GET /pos/orders/:restaurantId/stats`
```json
{
  "success": true,
  "data": {
    "total": 10,
    "pending": 2,
    "paid": 3,
    "preparing": 3,
    "ready": 1,
    "completed": 1,
    "cancelled": 0,
    "totalRevenue": 78000
  }
}
```

`PATCH /pos/orders/:orderId/status`
```json
// 요청
{ "status": "PREPARING" }   // 또는 READY / COMPLETED

// 응답
{
  "success": true,
  "data": {
    "id": "order_uuid",
    "status": "PREPARING",
    "updatedAt": "2026-04-08T12:05:00"
  }
}
```

`POST /pos/orders/:orderId/cancel`
```json
// 요청
{ "reason": "고객 요청" }

// 응답
{ "success": true, "data": { "success": true, "orderId": "order_uuid" } }
```

> ⚠️ **응답 필드 보강 필요 가능성:** 위 GET 목록 응답에는 메뉴명/수량/손님 이름이 빠져 있음. POS 화면에서 표시하려면 백엔드에 추가 필드 요청(`customer.name`, `items[].name`, `items[].quantity`) 또는 `GET /orders/:id` 별도 호출이 필요함. 우선 백엔드 담당(우현호)와 응답 스키마 확정 합의 권장.

### 주문 응답 보강이 필요한 이유 (참고)

DTO 명세 `GET /orders/today`(점주앱용)에는 다음 필드가 있음:
```json
{
  "customer": { "name": "김지효", "org": "개발팀" },
  "items": [{ "name": "제육볶음 도시락", "quantity": 2 }],
  "statusLabel": "수락 대기"
}
```
POS도 동일한 구조로 정렬되면 화면 작업이 단순해짐.

---

## 4. 주문 상태 전이 (POS가 다루는 부분)

```
PENDING ── (손님 결제) ──> PAID ── (POS 수락) ──> PREPARING ── (조리완료) ──> READY ── (수령확인) ──> COMPLETED
                                                                                        │
                                                                                        └── 취소 ──> CANCELLED
```

| 상태 | 한글 라벨 | 누가 변경 | POS 화면 위치 |
|---|---|---|---|
| `PENDING` | 결제 대기 | 시스템(주문 생성) | 표시 안 함 |
| `PAID` | 신규 주문 | 시스템(결제 승인) | **신규 주문 영역** |
| `PREPARING` | 조리 중 | POS | **조리 중 영역** |
| `READY` | 픽업 대기 | POS | **호출 보드** |
| `COMPLETED` | 완료 | POS | (자동 숨김 또는 통계용) |
| `CANCELLED` | 취소 | POS | (필요 시 별도 영역) |

> ⚠️ DB ENUM에 `ACCEPTED`, `DONE`이 잔재로 남아있음(PostgreSQL ENUM은 삭제 불가). **POS는 사용하지 말 것.**

---

## 5. 인증 흐름

POS는 손님과 다른 권한이 필요함.

- `users.role` ENUM: `CUSTOMER` / `OWNER` / **`POS`**
- POS 사용자는 별도 로그인 화면 필요. 카카오 로그인 흐름은 손님앱과 동일하나 백엔드에서 role 부여 방식 협의 필요(현재 회원가입 시 기본 `CUSTOMER`로 INSERT됨).
- JWT는 `auth.controller.ts`의 `POST /auth/kakao` 응답에서 받음 (`accessToken` 필드).
- 모든 POS API 호출에 `Authorization: Bearer {accessToken}` 필수.
- **POS만 처리 가능** 작업: `PATCH /pos/orders/:id/status`, `POST /pos/orders/:id/cancel`.

> **백엔드 협의 필요 항목**
> 1. POS용 로그인 흐름 — 카카오 SSO를 그대로 쓸지, 점포별 ID/PW를 별도 발급할지 미정
> 2. POS 사용자에게 묶일 `restaurantId` 조회 방법 — 현재 users 테이블에 `restaurant_id` FK 없음. 신설하거나 별도 매핑 테이블 필요

---

## 6. 페이지 구성 제안

| 라우트 | 화면명 | 기능 |
|---|---|---|
| `/login` | POS 로그인 | 점포 계정 로그인 → JWT 저장 |
| `/dashboard` | 통합 대시보드(POS-08/09) | 신규/조리중/픽업대기 칸반 + 결제 통계 카드 |
| `/kitchen` | 주방 모드(POS-07) | 큰 글씨로 조리 대기/진행 주문만 표시. 터치로 상태 전이 |
| `/board` | 호출 보드(POS-10) | READY 상태 주문번호 큰 화면 표시(전광판용) |
| `/orders/:id` | 주문 상세 | 메뉴/수량/금액/취소 버튼 |
| `/stats` (선택) | 매출 통계 | 일/주/월 매출, 메뉴별 판매량 |

> **MVP 권장 순서:** `/login` → `/dashboard` → `/kitchen` → `/board`

### 칸반 화면 예시(대시보드)

```
┌──────────── 신규(PAID) ────────────┬──────── 조리중(PREPARING) ────────┬──────── 픽업대기(READY) ────────┐
│ #A12  김지효 / 개발팀               │ #A11  우현호 / 기획팀              │ #A09  안태환 / 개발팀            │
│ 제육볶음 ×2, 김치찌개 ×1            │ 라면 ×1                            │ 떡볶이 ×2                        │
│ 13,000원  3분 전                    │ 6,500원  7분 전                    │ 9,000원  완성                    │
│ [조리시작]  [취소]                  │ [조리완료]  [취소]                 │ [수령완료]                       │
└────────────────────────────────────┴────────────────────────────────────┴──────────────────────────────────┘
```

---

## 7. 폴링 구현 가이드

### 핵심 규칙

- **3초 간격 폴링**, `setInterval` + `clearInterval`로 관리
- **백그라운드(탭 비활성) 진입 시 폴링 중단** — 배터리/요청량 보호
  - 브라우저는 `document.visibilitychange` 이벤트로 감지
- **포그라운드 복귀 시 즉시 재요청 후 타이머 재시작**
- 폴링 대상: 주문 목록, 주문 상태, 통계
- 추후 WebSocket 교체 가능성 → **데이터 레이어를 인터페이스로 분리** (UI 코드 수정 없이 교체 가능하게)

### React 훅 형태 권장 패턴

```typescript
// 의도만 표현. 실제 구현은 Next.js + SWR/React Query/직접 fetch 어떤 방식이든 가능.
function useOrdersPolling(restaurantId: string, status?: OrderStatus) {
  const [orders, setOrders] = useState<Order[]>([]);
  useEffect(() => {
    let timer: ReturnType<typeof setInterval> | null = null;
    const tick = async () => { /* GET /pos/orders/:restaurantId 호출 */ };
    const start = () => { tick(); timer = setInterval(tick, 3000); };
    const stop = () => { if (timer) clearInterval(timer); timer = null; };
    const onVis = () => (document.hidden ? stop() : start());
    document.addEventListener('visibilitychange', onVis);
    start();
    return () => { stop(); document.removeEventListener('visibilitychange', onVis); };
  }, [restaurantId, status]);
  return orders;
}
```

### 304 Not Modified 최적화

명세서상 `If-Modified-Since` 헤더로 변경 없으면 304만 받는 최적화가 정의되어 있으나, **PROGRESS.md 기준 미구현**. POS 측은 일반 200 응답 기준으로 구현하고, 백엔드 304 지원 여부 합의 후 추가 가능.

---

## 8. UI/UX 고려 사항

### 주방용 화면 특성
- 폰트는 큼직하게 (16~24px 본문, 28px 이상 헤딩) — 조리하면서 멀리서 보기
- 색 코드: 신규 주문 = 강조색(LunchSync 손님앱 주황 `#FF8C42` 또는 점주앱 청록 `#1DBFA3`), 픽업 대기 = 밝은 노랑
- 새 주문 진입 시 **소리 알림** + 토스트 — 조리실 환경에선 시각만으로 부족
- 한 번의 탭/클릭으로 다음 상태로 전이 (PAID→PREPARING→READY→COMPLETED 직선 진행)

### 호출 보드 특성
- 전광판/대형 모니터 풀스크린 가정
- 주문 번호를 4자리 이상 큼직하게 표시
- READY 진입 시 깜박임/소리로 손님 호출
- COMPLETED로 넘어가면 자동 사라짐(예: 1분 후)

### 점주앱과의 디자인 통일
- 컬러 팔레트는 손님앱 docs(`LUNCHSYNC_CODE_GUIDE.md` 3장)의 점주앱 컬러 사용 권장
  - primary `#1DBFA3` / primaryDark `#189E88` / primarySurface `#F0FBF9`
- 8px 그리드, 한글 Noto Sans 기반 typography

---

## 9. 환경 변수 / 설정

`.env.local` (Next.js)

```
NEXT_PUBLIC_BACKEND_BASE_URL=https://api.lunchsync.example.com/api
NEXT_PUBLIC_POLLING_INTERVAL_MS=3000
```

> ⚠️ Supabase URL/Anon key는 **POS에 들어가면 안 됨**. POS는 NestJS API만 호출.

---

## 10. 보안/배포 체크리스트

- [ ] JWT 저장: localStorage(편의) vs httpOnly Cookie(보안). 매장 PC 환경 가정 시 cookie 권장
- [ ] 자동 로그아웃 정책: 토큰 만료(7일) 시 로그인 화면으로 강제 이동
- [ ] 백엔드 CORS 화이트리스트에 POS 도메인 추가 요청 (현재 `origin: '*'` 개발용 → 실제 도메인 제한 예정)
- [ ] HTTPS 강제
- [ ] 콘솔 로그/디버그 코드 제거
- [ ] 잘못된 상태 전이 차단 (PAID에서 바로 COMPLETED로 가는 버튼 비활성)
- [ ] 취소 시 사유 필수 입력 강제

---

## 11. 백엔드 협의가 필요한 항목 (선결 과제)

| # | 항목 | 결정 필요 |
|---|---|---|
| 1 | POS 로그인 방식 | 카카오 SSO 재사용 vs 점포 ID/PW 별도 발급 |
| 2 | `users.restaurant_id` FK | 컬럼 신설 또는 매핑 테이블 도입 (POS 유저 ↔ 식당) |
| 3 | `GET /pos/orders/:restaurantId` 응답 보강 | `customer{name,org}`, `items[]{name,quantity}`, `statusLabel` 추가 |
| 4 | `POST /pos/orders/:id/cancel` Toss 실제 환불 연결 (POS-13) | 백엔드 TODO 해소 시점 |
| 5 | FCM 푸시 알림 발송 (신규 주문 시 POS에) | PROGRESS상 미구현. POS는 폴링으로만 받을지 결정 |
| 6 | 304 Not Modified 폴링 최적화 | 백엔드 미구현. 우선 200으로 구현 후 추가 가능 |

---

## 12. 단계별 구현 순서 (제안)

### Phase 1 — MVP (주문 받기/조리/완료)
1. Next.js 프로젝트 셋업, 환경 변수, 공용 fetch wrapper(JWT 자동 첨부)
2. 로그인 페이지 (`/login`) — 백엔드 합의된 방식으로
3. 주문 목록 폴링 훅 + 상태별 분리 칸반 페이지(`/dashboard`)
4. 상태 전이 버튼 (PAID→PREPARING→READY→COMPLETED) — `PATCH /pos/orders/:id/status`
5. 취소 모달 + `POST /pos/orders/:id/cancel`

### Phase 2 — 부가 기능
6. 통계 카드 (`GET /pos/orders/:restaurantId/stats`)
7. 주방 모드 풀스크린 화면 (`/kitchen`) — 큰 글씨 + 사운드
8. 호출 보드 (`/board`) — READY만 큼직하게

### Phase 3 — 운영
9. 자동 로그아웃, 에러/오프라인 핸들링
10. 일/주/월 매출 통계 (`/stats`)
11. (백엔드 합의 후) FCM 알림, 304 최적화, Toss 실 환불

---

## 13. 참고 파일 위치

| 문서 | 위치 | 활용 |
|---|---|---|
| 전체 명세 | `app/docs/LUNCHSYNC_SPECIFICATION.md` | 시스템 구조, DB ENUM, 상태 전이 |
| API DTO | `app/docs/LUNCHSYNC_DTO.md` | 요청/응답 스키마 (특히 12장 POS) |
| 코드 가이드 | `app/docs/LUNCHSYNC_CODE_GUIDE.md` | 디자인 시스템, 공용 응답 포맷 |
| 진행도 | `app/docs/LUNCHSYNC_PROGRESS.md` | 백엔드 구현 현황 |
| 머지 이력 | `app/docs/README.md`, `app/docs/hyunho.md` | 최신 변경사항 |


