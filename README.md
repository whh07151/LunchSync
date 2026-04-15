# LunchSync

그룹 점심 조율 앱 — 식당 추천 · 투표 · 주문 · 결제를 한 흐름으로 연결합니다.

---

## 팀 역할

| 이름 | 주요 담당 |
|---|---|
| 우현호 | 팀장 / AI 추천엔진 / 외부 API 연동 / 카카오 로그인 / 결제 시스템 |
| 장다연 | RAG 설계 / 식당 데이터 수집·정규화 / 추천 근거 / 운영 통계 |
| 김지효 | 모바일 프론트 / UX / 디자인 시스템 / 화면 연결 |
| 안태환 | 백엔드 API / POS 시뮬레이터 / 실시간 상태동기화 / QA |

---

## 기술 스택

| 영역 | 기술 |
|---|---|
| 모바일 앱 | Flutter + Riverpod |
| 백엔드 | NestJS (TypeScript) |
| DB / Auth | Supabase (PostgreSQL) |
| 결제 | Toss Payments v2 결제위젯 |
| 배포 | AWS (백엔드) |

---

## 프로젝트 구조

```
capstone/
├── lib/                        # Flutter 앱
│   ├── core/
│   │   ├── config/             # AppConfig (API URL, 앱 키)
│   │   ├── theme/              # 디자인 시스템 (색상, 타이포, 간격)
│   │   └── widgets/            # 공통 위젯 (버튼, 텍스트필드 등)
│   ├── features/
│   │   ├── auth/               # CU-02 카카오 로그인
│   │   ├── home/               # CU-06 홈 대시보드
│   │   ├── menu/               # CU-16 메뉴 목록
│   │   ├── onboarding/         # CU-03·05 프로필·조건 설정
│   │   ├── payment/            # CU-17·18·19 주문 검토·결제
│   │   ├── session/            # CU-08·09·10 멤버선택·세션생성·로비
│   │   └── splash/             # CU-01 스플래시
│   ├── models/                 # 데이터 모델 (Session, SessionMember 등)
│   ├── providers/              # Riverpod Provider (userProvider, cartProvider 등)
│   └── services/               # API 서비스 (sessions, invitations, payments 등)
│
├── backend/
│   └── src/
│       ├── auth/               # JWT 인증 가드
│       ├── invitations/        # 초대코드 생성·수락
│       ├── orders/             # 주문 생성·관리
│       ├── payments/           # Toss 결제 승인
│       ├── pos/                # 점주 주문 조회·처리
│       ├── recommendations/    # 그룹 추천 점수화
│       ├── restaurants/        # 식당 목록·메뉴
│       ├── sessions/           # 세션 CRUD·멤버 관리
│       ├── supabase/           # Supabase 클라이언트 모듈
│       ├── users/              # 유저 프로필
│       └── votes/              # 투표·결과 확정
│
├── docs/
│   ├── LUNCHSYNC_SPECIFICATION.md   # DB 스키마 + API 명세
│   ├── LUNCHSYNC_DTO.md             # 요청/응답 DTO 상세
│   ├── LUNCHSYNC_CODE_GUIDE.md      # 코드 구조 가이드
│   └── LUNCHSYNC_PROGRESS.md        # 구현 진행 현황
│
└── web/
    └── toss-checkout.html      # Toss 결제위젯 HTML (웹 전용)
```

---

## 로컬 실행

### 백엔드

```bash
cd backend
cp .env.example .env      # 팀원에게 .env 값 공유받아 채우기
npm install
npm run start:dev         # http://localhost:3000
```

### Flutter 앱

```bash
flutter pub get
flutter run -d chrome     # 웹 (결제 기능 사용 가능)
flutter run               # 연결된 기기/에뮬레이터
```

---

## 환경 변수 (.env)

`backend/.env` — git에 포함되지 않음. `.env.example` 참고.

| 변수 | 설명 |
|---|---|
| `SUPABASE_URL` | Supabase 프로젝트 URL |
| `SUPABASE_ANON_KEY` | Supabase anon 키 |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase service_role 키 (RLS 우회, 서버 전용) |
| `JWT_SECRET` | 자체 JWT 서명 시크릿 |
| `TOSS_SECRET_KEY` | Toss Payments 테스트 시크릿 키 |

---

## 테스트 스크립트

```bash
# DB 시드 (최초 1회 — 테스트용 식당·메뉴·세션 데이터 삽입)
cd backend && npx ts-node scripts/seed-test-data.ts

# 결제 흐름 E2E 검증 (카카오 로그인 없이 백엔드 결제 로직 단독 검증)
cd backend && npx ts-node scripts/test-payment-flow.ts
```

---

## 구현 현황

| ID | 화면 | 상태 | 담당 |
|---|---|---|---|
| CU-01 | 스플래시/서비스 소개 | ✅ 완료 | 김지효 |
| CU-02 | 카카오 로그인 | ✅ 완료 | 우현호 |
| CU-03 | 기본 프로필 설정 | ✅ 완료 | 김지효 |
| CU-05 | 기본 조건 설정 | ✅ 완료 | 김지효 |
| CU-06 | 홈 대시보드 | ⚠️ UI완료·API미연결 | 김지효 |
| CU-07 | 초대 링크 공유 | ✅ 완료 | 우현호 |
| CU-08 | 멤버 선택 | ✅ 완료 | 김지효 |
| CU-09 | 세션 생성 조건 설정 | ✅ 완료 | 우현호·김지효 |
| CU-10 | 세션 로비 | ✅ 완료 | 안태환·김지효 |
| CU-16 | 메뉴 목록/상세 | ⚠️ UI완료·API미연결 | 김지효 |
| CU-17~19 | 주문·결제 | ✅ 완료 | 우현호 |
| CU-22 | 알림함 | ❌ 미구현 | 안태환 |
| CU-23 | 내정보/설정 | ❌ 미구현 | 김지효 |

# 0414-1 머지 내용 정리

**날짜:** 2026-04-14
**브렌치:** `feat/hyunho` → `feat/jihyo` (fast-forward merge) + 버그수정/DTO정렬/CU-09 추가
**작업자:** 우현호(백엔드/결제) + 김지효(버그수정/DTO정렬/CU-09)
한줄요약: 초대코드·세션 생성·주문상태 버그 수정 + DB 불일치 수정 + CU-09 세션 조건 설정 화면 구현
---

## 1. 머지 개요

`feat/hyunho` 브렌치를 `feat/jihyo`에 fast-forward 머지 후,
머지 과정에서 발견된 버그 및 DTO 불일치 사항을 추가 수정함.

**feat/hyunho 포함 커밋 3개:**
- `49b0b46` feat: 백엔드 7개 모듈 신규 생성 + 30개 API 엔드포인트 구현
- `5bc4033` feat: 토스페이먼츠 v2 결제위젯 전체 연동 (CU-17/18/19, CORE-10)
- `192d356` chore: 결제 흐름 DB seed + API E2E 테스트 스크립트 추가

**김지효 추가 수정 (커밋 완료):**
- `invitations.service.ts` — 초대 코드 즉시 만료 버그 수정 + `created_by` 불필요 컬럼 제거
- `sessions.service.ts` — DTO 응답 구조 정렬 (createdBy 객체화, memberCount, statusLabel, getSessionMembers 구조 변경)
- `restaurants.service.ts` — 메뉴 응답 구조 정렬 (`{ categories[], menus[] }`)
- `backend/.env` — `TOSS_SECRET_KEY` 실제 테스트 키로 교체
- `main.dart` — 결제 복귀 시 provider 빌드 중 수정 에러 수정 (`_restoreUserFromSession` → `addPostFrameCallback`)
- `session_create_screen.dart` — CU-09 세션 조건 설정 화면 신규 구현 (섹션 9 참고)

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

## 9. CU-09 세션 생성 조건 설정 화면 (김지효)

### 신규 화면

**`lib/features/session/session_create_screen.dart`**
- CU-08 멤버 선택 → "조건 설정하기" 버튼으로 진입
- 입력 항목: 세션 이름, 점심 시간, 반경(m), 예산(원), 복귀시간(분), 메모
- "조건 초기화" — 반경 500m / 예산 15,000원 / 복귀 30분으로 리셋
- "세션 만들기" — `POST /sessions` + `POST /invitations` → SessionLobbyScreen(호스트 모드) 진입
- 단계 표시바 2단계(조건) 활성

### DB 컬럼 추가

```sql
ALTER TABLE sessions ADD COLUMN radius INT;
ALTER TABLE sessions ADD COLUMN budget INT;
ALTER TABLE sessions ADD COLUMN return_minutes INT;
ALTER TABLE sessions ADD COLUMN memo TEXT;
```

### 수정 파일

- `backend/src/sessions/sessions.service.ts` — `CreateSessionDto` 및 insert/select/return에 신규 필드 반영
- `backend/src/sessions/sessions.controller.ts` — DTO 유효성 검사 데코레이터 추가
- `lib/models/session.dart` — `Session` 모델에 `radius`, `budget`, `returnMinutes`, `memo` 추가
- `lib/services/sessions_api_service.dart` — `createSession` 파라미터 추가
- `lib/features/home/home_screen.dart` — `onNext` 콜백 → `SessionCreateScreen` 라우팅 연결
- `lib/core/widgets/app_text_field.dart` — `maxLines` 파라미터 추가

---

## 10. 미연결 (추후 작업)

| 항목 | 이유 |
|---|---|
| `menu_screen` → `GET /restaurants/:id/menus` | mock UUID와 seed UUID 일치하므로 연결 시 바로 동작 가능 |
| `home_screen` → sessions/recommendations API | UI 연결 작업 필요 |
| `member_select_screen` → `GET /users` | 백엔드 `GET /users` 엔드포인트 미구현 |

## 앱 실행법
### Localhost
#### Chrome(web) 사용시
1. 서버 시작: npm run start:dev (이때 터미널 위치:capstone\backend>)
2. 플러터 실행: flutter run -d chrome --web-port 8080 (터미널 위치: capstone>)
#### Android 실제 기기 (04/15 기준 아이폰은 서버 시작만 하면 잘 돌아감)
1. 서버 시작: npm run start:dev (이때 터미널 위치:capstone\backend>)
2. 플러터 실행: $IP = (ipconfig | Select-String "IPv4" | Select-Object -First 1) -replace '.*:\s*', '' -replace '\s', ''; echo $IP; flutter run --dart-define=BACKEND_HOST=$IP (터미널 위치: capstone>)
