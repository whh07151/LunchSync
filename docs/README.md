# 0414-1 머지 내용 정리

**날짜:** 2026-04-14
**브렌치:** `feat/hyunho` → `feat/jihyo` (fast-forward merge) + 버그수정/DTO정렬 추가
**작업자:** 우현호(백엔드/결제) + 김지효(버그수정/DTO정렬)
한줄요약: 초대코드, 세션 생성, 주문상태 에대한 버그 및 이것과 관련된 DB 불일치 수정(일부는 코드,일부는 디비 수정)
---

## 1. 머지 개요

`feat/hyunho` 브렌치를 `feat/jihyo`에 fast-forward 머지 후,
머지 과정에서 발견된 버그 및 DTO 불일치 사항을 추가 수정함.

**feat/hyunho 포함 커밋 3개:**
- `49b0b46` feat: 백엔드 7개 모듈 신규 생성 + 30개 API 엔드포인트 구현
- `5bc4033` feat: 토스페이먼츠 v2 결제위젯 전체 연동 (CU-17/18/19, CORE-10)
- `192d356` chore: 결제 흐름 DB seed + API E2E 테스트 스크립트 추가

**김지효 추가 수정 (미커밋, 이 문서와 함께 커밋 예정):**
- `invitations.service.ts` — 초대 코드 즉시 만료 버그 수정 + `created_by` 불필요 컬럼 제거 이유: 초대 생성자를 클라이언트에 내려줄 필요 없음
- `sessions.service.ts` — DTO 응답 구조 정렬 (createdBy 객체화, memberCount, statusLabel, getSessionMembers 구조 변경)
- `restaurants.service.ts` — 메뉴 응답 구조 정렬 (`{ categories[], menus[] }`)
- `backend/.env` — `TOSS_SECRET_KEY=test_dummy` 추가 (로컬 테스트용)

---

## 2. 백엔드 신규 모듈 (우현호)

| 모듈 | 엔드포인트 수 | 주요 기능 |
|---|---|---|
| `sessions` | 7개 | 세션 CRUD, 멤버 관리, 상태 전이 [CU-09] |
| `invitations` | 3개 | 초대 링크 생성/수락 [CU-07] |
| `restaurants` | 3개 | 식당 목록/상세/메뉴 [CU-11] |
| `recommendations` | 1개 | 그룹 추천 점수화 + 최근 7일 중복 회피 [CORE-07/08] |
| `votes` | 3개 | 투표 + 결과 집계/확정 [CU-15] |
| `orders` | 4개 | 주문 생성 + 메뉴 충돌 검증 [CORE-09/10, CU-17/18/19] |
| `payments` | 1개 | 토스 결제 승인 [CU-19] |
| `pos` | 4개 | 점주 주문 조회/통계/취소/환불 [OW-10, POS-08/09/13] |

> ⚠️ `pos` 취소/환불(POS-13)은 TODO — Toss 실제 환불 API 미연결

---

## 3. 프론트엔드 추가 (우현호)

**신규 화면:**
- `lib/features/payment/order_review_screen.dart` — 주문 확인 화면
- `lib/features/payment/payment_success_screen.dart` — 결제 성공 화면
- `lib/features/payment/payment_fail_screen.dart` — 결제 실패 화면
- `lib/features/payment/payment_web_bridge.dart/html/stub` — Toss 결제위젯 web bridge

**신규 API 서비스:**
- `lib/services/sessions_api_service.dart`
- `lib/services/orders_api_service.dart`
- `lib/services/payments_api_service.dart`
- `lib/services/restaurants_api_service.dart`
- `lib/services/invitations_api_service.dart`

**신규 모델:**
- `lib/models/session.dart` — Session / SessionMember 모델

**기타:**
- `lib/main.dart` — 결제 왕복 리턴 처리 (paymentStatus 쿼리 감지)
- `web/toss-checkout.html` — 토스 결제위젯 HTML

---

## 4. 버그 수정 (김지효)

### `invitations.service.ts` — 초대 코드 즉시 만료 버그

**원인:** `createInvitation` 에서 `expires_at` 미설정 → DB에 `null` 저장 →
`new Date(null)` = 1970년 → 생성 즉시 만료 처리

**수정:** insert 시 `expires_at: 생성시각 + 24시간` 명시적으로 설정

```typescript
// 수정 전
.insert({
  session_id: dto.sessionId,
  invite_code: inviteCode,
  created_by: userId,
})

// 수정 후
const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
.insert({
  session_id: dto.sessionId,
  invite_code: inviteCode,
  expires_at: expiresAt,
})
```

---

### `invitations.service.ts` — `created_by` 컬럼 논리 충돌

**충돌 과정:**
1. `POST /invitations` 호출 시 500 에러 발생
2. 에러 메시지: `Could not find the 'created_by' column of 'invitations'`
3. DB에 `created_by` 컬럼이 없음을 확인

**논리 검토:**
- DTO 응답 명세에 `createdBy` 필드 없음 → 초대 생성자를 클라이언트에 내려줄 필요 없음
- 초대 수락 흐름: `invite_code` → `session_id` 조회 → 멤버 추가. `created_by` 불필요
- 초대 취소/관리 기능은 현재 명세에 없음

**결론:** DB에 없는 컬럼을 추가하는 것이 아니라, **불필요한 insert 코드를 제거**하는 것이 맞음

**수정:** insert 및 select에서 `created_by` 제거

```typescript
// 수정 전
.insert({
  session_id: dto.sessionId,
  invite_code: inviteCode,
  created_by: userId,   // DB에 없는 컬럼 → 500
  expires_at: expiresAt,
})

// 수정 후
.insert({
  session_id: dto.sessionId,
  invite_code: inviteCode,
  expires_at: expiresAt,
})
```

---

## 5. 테스트 스크립트 (우현호)

**사용 순서 (로컬 테스트 시):**
```bash
# 1. 백엔드 실행
cd backend && npm run start:dev

# 2. DB 시드 (최초 1회)
npx ts-node scripts/seed-test-data.ts

# 3. 결제 흐름 E2E 검증 (필요 시 반복)
npx ts-node scripts/test-payment-flow.ts
```

**seed-test-data.ts:** Flutter `_mockMenuItems`와 UUID 1:1 매칭되는 실DB 레코드 삽입
**test-payment-flow.ts:** JWT 직접 발급해 카카오 로그인 우회 후 주문→결제→위변조방어 순서 검증

---

## 6. DTO 응답 구조 불일치 수정 (김지효)

### `sessions.service.ts` — createdBy UUID → 객체 변환

**원인:** DTO 명세는 `createdBy: { id, name }` 객체인데 서비스는 UUID 문자열만 반환

**수정:**
- `createSession` / `getSessionById` / `getTodaySessions` 에서 users 테이블 join하여 `{ id, name }` 객체로 반환
- `getTodaySessions`에 `statusLabel`(한글), `memberCount` 추가
- N+1 방지: `getTodaySessions`에서 멤버 수·생성자 정보를 세션 목록 단위로 일괄 조회

### `sessions.service.ts` — getSessionMembers 응답 구조 변환

**원인:** DTO 명세는 `{ totalCount, joinedCount, members[] }` 구조인데 배열만 반환

**수정:**
- `{ totalCount, joinedCount, members[] }` 구조로 감싸기
- 멤버 필드 `userId` → `id` 변경
- `isHost` 필드 추가 (세션 `created_by`와 비교)

### `restaurants.service.ts` — getMenusByRestaurant 응답 구조 변환

**원인:** DTO 명세는 `{ categories[], menus[] }` 구조인데 flat 배열만 반환

**수정:**
- 메뉴 목록에서 카테고리 추출 후 `['전체', ...고유카테고리]` 배열 생성
- `{ categories, menus }` 구조로 반환

---

## 7. ENUM 불일치 수정 (김지효)

### `session_status` — DECIDED/COMPLETED → ORDERED/DONE

**원인:** DB spec의 `session_status` ENUM은 `WAITING, VOTING, ORDERED, DONE`인데
코드는 `DECIDED`, `COMPLETED`를 사용 → DB INSERT 시 PostgreSQL ENUM 제약 위반

**수정 파일:**
- `sessions/sessions.service.ts` — 주석 + `statusLabel` 매핑 수정
  - `DECIDED: '식당 확정'` → `ORDERED: '주문 완료'`
  - `COMPLETED: '완료'` → `DONE: '세션 종료'`
- `votes/votes.service.ts` — 투표 확정 시 `status: 'DECIDED'` → `status: 'ORDERED'`

---

### `order_status` — DB에 PAID/READY/COMPLETED 값 추가 필요

**원인:** 코드(`orders.service.ts`, `payments.service.ts`, `pos.service.ts`)는
`PAID → PREPARING → READY → COMPLETED` 흐름을 사용하는데,
초기 DB ENUM에는 `PENDING, ACCEPTED, PREPARING, DONE, CANCELLED`만 존재

**코드 흐름:**
```
PENDING  — 주문 생성, Toss 결제 대기
PAID     — 결제 승인 완료 (Toss confirm 또는 SIMULATE/CASH 즉시 처리)
PREPARING — 점주 조리 시작
READY    — 조리 완료
COMPLETED — 주문 종료
CANCELLED — 취소/환불
```

**DB 조치 (Supabase SQL 에디터에서 실행 필요):**
```sql
ALTER TYPE order_status ADD VALUE 'PAID';
ALTER TYPE order_status ADD VALUE 'READY';
ALTER TYPE order_status ADD VALUE 'COMPLETED';
```

> ⚠️ `ACCEPTED`, `DONE`은 초기 설계 잔재로 DB에 남아있음. PostgreSQL ENUM 특성상 삭제 불가, 미사용 상태로 유지.

---

### Flutter 모델 DTO 불일치 수정 (김지효)

**원인:** `sessions.service.ts` 수정으로 응답 구조가 바뀌었는데 Flutter 모델이 구버전 기준

**수정 파일 — `lib/models/session.dart`:**
- `SessionCreator` 클래스 추가 — `createdBy`가 `{ id, name }` 객체로 내려오므로
  기존 `String` 캐스팅 시 런타임 에러 발생 → 전용 클래스로 파싱
- `Session` 모델에 `memberCount`, `statusLabel` 필드 추가
- `SessionMember.userId` → `id` 변경 (백엔드가 `id` 키로 반환)
- `SessionMember`에 `isHost` 필드 추가
- `SessionMembersResponse` 래퍼 클래스 추가 — 백엔드가 배열 대신
  `{ totalCount, joinedCount, members[] }` 구조로 반환

**수정 파일 — `lib/services/sessions_api_service.dart`:**
- `getSessionMembers` 반환 타입 `List<SessionMember>` → `SessionMembersResponse?`
- 응답 파싱을 래퍼 구조에 맞게 수정

---

## 8. 세션 생성 + 초대코드 + 참가 흐름 구현 (김지효)

### 신규 화면

**`lib/features/session/session_lobby_screen.dart`**
- 세션 생성 후 진입하는 로비 화면
- 호스트 모드: 초대코드 카드(복사 버튼) + 멤버 목록 폴링
- 참가자 모드: 멤버 목록 폴링만 (inviteCode 없음)
- `WidgetsBindingObserver`로 백그라운드 진입 시 폴링 자동 중단/재시작
- `initialSession` 파라미터: createSession 응답을 바로 넘겨 재조회 없이 즉시 표시

**`lib/features/session/join_session_screen.dart`**
- 초대코드 입력 후 세션 참가 화면
- `POST /invitations/:code/accept` 호출 → 성공 시 SessionLobbyScreen(참가자 모드) 진입

### 수정 파일

**`lib/services/invitations_api_service.dart`**
- `acceptInvitation` 반환 타입 `bool` → `String?` (sessionId 반환)
- 참가 후 로비로 이동하기 위해 sessionId가 필요

**`lib/features/session/member_select_screen.dart`**
- "초대 링크 복사하기" 버튼 동작 변경: 클립보드 복사 → SessionLobbyScreen으로 이동
- `createSession` 응답을 `initialSession`으로 넘겨 재조회 방지

**`lib/features/home/home_screen.dart`**
- "친구 초대" 버튼 → "코드로 참가" 버튼으로 변경 (JoinSessionScreen 진입)

### DB 조치 — invitations 테이블 생성
기존 테이블이 컬럼 누락 상태로 잘못 생성되어 있어 DROP 후 재생성

```sql
DROP TABLE IF EXISTS invitations;

CREATE TABLE invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  invite_code VARCHAR(8) UNIQUE NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);
```

---

## 9. 미연결 (추후 작업)

| 항목 | 이유 |
|---|---|
| `menu_screen` → `GET /restaurants/:id/menus` | mock UUID와 seed UUID 일치하므로 연결 시 바로 동작 가능 |
| `home_screen` → sessions/recommendations API | UI 연결 작업 필요 |
| `member_select_screen` → `GET /users` | 백엔드 `GET /users` 엔드포인트 미구현 |
