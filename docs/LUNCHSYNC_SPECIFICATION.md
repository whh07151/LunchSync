# LunchSync 소프트웨어 명세서
**작성일:** 2026-04-08
**버전:** 1.2 (orders.restaurant_id 추가)

**구현 진행도:** [`LUNCHSYNC_PROGRESS.md`](./LUNCHSYNC_PROGRESS.md) 참조 (이 파일과 분리 운영)

---

## 목차
1. [소프트웨어 개요](#1-소프트웨어-개요)
2. [팀 구성 및 담당](#2-팀-구성-및-담당)
3. [기술 스택](#3-기술-스택)
4. [아키텍처 설계](#4-아키텍처-설계)
5. [기능 명세 (CU/OW/POS)](#5-기능-명세)
6. [DB 설계](#6-db-설계)
7. [API 흐름](#7-api-흐름)
8. [MVC 구현 흐름](#8-mvc-구현-흐름)
9. [보안 및 제약 조건](#9-보안-및-제약-조건)

---

## 1. 소프트웨어 개요

**서비스명:** LunchSync
**목적:** 직장인/팀원들이 함께 점심 식당을 정하고, 투표하고, 주문까지 한 번에 할 수 있는 AI 기반 점심 조율 앱

**핵심 흐름:**
```
로그인 → 세션 생성 → 멤버 초대 → AI 식당 추천 → 투표 → 메뉴 선택 → 결제 → 주문 추적
```

**플랫폼:**
- 손님앱: Android / iOS (Flutter)
- 점주앱: Android / iOS (Flutter)
- POS: 웹 (Next.js)

---

## 2. 팀 구성 및 담당

| 이름 | 담당 영역 |
|---|---|
| 김지효 | 모바일 프론트 / UX / 디자인 시스템 |
| 우현호 | 백엔드 API / 카카오 로그인 / 세션 생성 |
| 안태환 | 백엔드 API / 세션 로비 / 투표 / 주문 추적 |
| 장다연 | AI/RAG / 식당 데이터 / Seed 데이터 |

---

## 3. 기술 스택

| 영역 | 기술 | 역할 |
|---|---|---|
| 손님앱/점주앱 | Flutter + Riverpod | UI 렌더링, 프론트 세션 캐시 |
| POS 웹 | Next.js | 주방/카운터 웹 화면 |
| 서버 | NestJS | 비즈니스 로직, 권한 검증, 트랜잭션 |
| DB | Supabase (PostgreSQL) | 데이터 저장 (DB 역할만) |
| 인증 | 카카오 SDK + JWT | 로그인, 토큰 관리 |
| 결제 | Toss Payments | 개인 결제 처리 |
| 푸시 알림 | FCM (Firebase Cloud Messaging) | 점주 주문 알림, 손님 상태 알림 |

### Riverpod 역할 명확화
- Riverpod = **프론트 세션 캐시** (source of truth 아님)
- Source of truth = **Supabase DB**
- 흐름: NestJS API 응답 → Riverpod 캐시 → 화면 표시

---

## 4. 아키텍처 설계

### 확정된 원칙 (2026-04-08)

```
Flutter 앱 (Android/iOS)
    ↕ HTTP API만 호출
    ↕ (Supabase 직접 접근 절대 금지)
NestJS 서버 [단일 문지기]
    - 권한 검증
    - 비즈니스 로직
    - 트랜잭션 처리
    - FCM 발송
    ↕ SQL 쿼리
Supabase PostgreSQL [DB 전용]
    - 데이터 저장/조회
    - 제약 조건 강제 (UNIQUE, FK, ENUM)
    - ACID 보장
```

### 결정 근거
- Flutter가 Supabase에 직접 접근하면 NestJS 권한 검증을 우회할 수 있음 (보안 구멍)
- 배달의민족 등 실서비스는 앱이 DB에 직접 접근하지 않음
- NestJS = 단일 문지기로 권한 로직 일원화

### 실시간 처리 방식
- **확정: 폴링 (3초 간격)**
- 최적화: HTTP 304 Not Modified (변경 없으면 빈 응답)
- ⚠️ 추후 WebSocket 교체 가능성 있음
  - 교체 용이성을 위해 데이터 레이어를 인터페이스로 분리 구현
  - UI 코드는 수정 없이 데이터 레이어만 교체

### 폴링 생명주기 처리 (필수)
```
앱 백그라운드 진입 → timer.cancel() [배터리 보호]
앱 포그라운드 복귀 → 타이머 재시작
```
- Flutter `WidgetsBindingObserver` 사용
- 적용 화면: 세션 로비, 투표 현황, 주문 추적, 점주 대시보드

---

## 5. 기능 명세

### 손님앱 (CU)

| ID | 기능 | 담당 | 상태 | 완료 기준 |
|---|---|---|---|---|
| CU-01 | 스플래시/서비스 소개 | 김지효 | ✅ 완료 | 탭 1회로 로그인 화면 진입 |
| CU-02 | 카카오 로그인 | 김지효/우현호 | ✅ 완료 | 카카오 인증 후 신규/기존 분기 |
| CU-03 | 기본 프로필 설정 | 김지효 | ⚠️ UI완료 | 프로필 저장 후 다음 온보딩 이동 |
| CU-05 | 기본 조건 설정 | 김지효 | ⚠️ UI완료 | 반경/예산/속도 조건 저장 및 홈 진입 |
| CU-06 | 홈 대시보드 | 김지효 | ⚠️ UI완료 | 주요 플로우 3개 이상 바로 접근 |
| CU-08 | 친구/멤버 리스트 | 김지효 | ⚠️ UI완료 | 선택 멤버가 세션 생성 화면으로 전달 |
| CU-09 | 점심 세션 생성 | 우현호 | ❌ 미구현 | 세션 생성 후 로비 진입 |
| CU-10 | 세션 로비 | 안태환 | ❌ 미구현 | 멤버 참여 실시간 확인 |
| CU-13 | 식당 상세/비교 | 장다연 | ❌ 미구현 | 식당 정보 상세 확인 |
| CU-14 | 투표 화면 | 안태환 | ❌ 미구현 | 식당 투표 및 결과 확인 |
| CU-16 | 메뉴 목록/장바구니 | 김지효 | ⚠️ UI완료 | 개인별 장바구니 구성 가능 |
| CU-19 | 주문/결제 | - | ❌ 미구현 | Toss Payments 결제 완료 |
| CU-20 | 주문/예약 추적 | 안태환 | ❌ 미구현 | 주문 상태 단계별 확인 |
| CU-22 | 알림함 | 김지효 | ❌ 미구현 | 핵심 이벤트 4종 이상 확인 |
| CU-23 | 내정보/설정 | 김지효 | ❌ 미구현 | 온보딩 데이터 재수정 가능 |

### 점주앱 (OW)

| ID | 기능 | 담당 | 상태 |
|---|---|---|---|
| OW-02 | 오늘 운영 대시보드 | 김지효 | ❌ 미구현 (Q6 앱분리 합의 후 착수) |

### POS 웹 (POS)

| ID | 기능 | 담당 | 상태 |
|---|---|---|---|
| POS-07 | POS 주방 모드 | 김지효 | ❌ 미구현 |
| POS-10 | 호출 결과 보드 | 김지효 | ❌ 미구현 |

---

## 6. DB 설계

### ERD 관계

```
Users ──── 1:N (방장) ──── Sessions ──── 1:N ──── Orders ──── 1:N ──── Order_Items
  │                           │
  └──── M:N (참여자) ─────────┘
       [session_members]

Sessions ──── 1:N ──── Votes
Restaurants ──── 1:N ──── Menu_Items
Users ──── 1:N ──── Cart_Items ──── N:1 ──── Menu_Items
Users ──── 1:N ──── Notifications
```

### 테이블 상세

#### users
```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kakao_id VARCHAR(50) UNIQUE NOT NULL,
  name VARCHAR(20) NOT NULL,
  org VARCHAR(30),
  profile_image TEXT,
  radius VARCHAR(10) DEFAULT '500m',
  budget INTEGER,
  speed VARCHAR(10),
  role user_role DEFAULT 'CUSTOMER',
  status VARCHAR(20) DEFAULT 'ACTIVE',
  fcm_token TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

#### sessions
```sql
CREATE TABLE sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(50) NOT NULL,
  status session_status DEFAULT 'WAITING',
  created_by UUID NOT NULL REFERENCES users(id),
  winner_restaurant_id UUID REFERENCES restaurants(id),
  scheduled_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);
```


#### session_members
```sql
CREATE TABLE session_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(session_id, user_id) -- 중복 참여 방지
);
-- ⚠️ 방장 본인도 세션 생성 트랜잭션 시 자동 INSERT 필수
```

#### restaurants
```sql
CREATE TABLE restaurants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(100) NOT NULL,
  lat DECIMAL(10, 8),
  lng DECIMAL(11, 8),
  category VARCHAR(50),
  price_range INTEGER, -- 평균 가격
  address TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);
```

#### menu_items
```sql
CREATE TABLE menu_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  price INTEGER NOT NULL,
  category VARCHAR(50),
  description TEXT,
  image_url TEXT
);
```

#### votes
```sql
CREATE TABLE votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  restaurant_id UUID NOT NULL REFERENCES restaurants(id),
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, session_id) -- 중복 투표 원천 차단 (핵심 제약)
);
```

#### cart_items
```sql
CREATE TABLE cart_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  menu_item_id UUID NOT NULL REFERENCES menu_items(id),
  quantity INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, session_id, menu_item_id)
);
```

#### orders
```sql
CREATE TABLE orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES sessions(id), -- 세션별 주문 추적 필수
  user_id UUID NOT NULL REFERENCES users(id),
  restaurant_id UUID NOT NULL REFERENCES restaurants(id),
  -- 어느 식당에 주문했는지 직접 참조 (order_items 조인 없이 바로 조회 가능)
  -- 투표 winner_restaurant_id와 일치 여부는 NestJS에서 소프트 검증
  status order_status DEFAULT 'PENDING',
  total_price INTEGER NOT NULL,
  payment_key TEXT, -- Toss Payments 결제 키
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

#### order_items
```sql
CREATE TABLE order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  menu_item_id UUID NOT NULL REFERENCES menu_items(id),
  quantity INTEGER NOT NULL,
  price INTEGER NOT NULL -- 주문 시점 가격 스냅샷
);
```

#### notifications
```sql
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(50) NOT NULL,
  -- ORDER_RECEIVED / ORDER_ACCEPTED / ORDER_DONE / VOTE_RESULT 등
  title VARCHAR(100),
  message TEXT,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);
-- FCM 발송과 항상 세트로 INSERT
-- CU-22 알림함의 데이터 원본
```

### ENUM 타입 정의 (PostgreSQL 네이티브)

```sql
-- VARCHAR 대신 PostgreSQL 네이티브 ENUM 사용
-- DB 레벨에서 잘못된 값 원천 차단

CREATE TYPE session_status AS ENUM (
  'WAITING',   -- 세션 생성됨, 멤버 대기 중
  'VOTING',    -- 투표 진행 중
  'ORDERED',   -- 주문 완료
  'DONE'       -- 세션 종료
);

CREATE TYPE order_status AS ENUM (
  'PENDING',    -- 주문 접수, 점주 확인 대기
  'ACCEPTED',   -- 점주 수락
  'PREPARING',  -- 조리 중
  'DONE',       -- 조리 완료
  'CANCELLED'   -- 취소
);

CREATE TYPE user_role AS ENUM (
  'CUSTOMER',  -- 손님앱 사용자
  'OWNER',     -- 점주앱 사용자
  'POS'        -- POS 사용자
);
```

### sessions 상태 전이 규칙

```
WAITING ──→ VOTING
  조건: 방장이 "투표 시작" 버튼 탭
  처리: NestJS PATCH /sessions/:id/status { status: 'VOTING' }
  제약: session_members가 1명 이상이어야 함

VOTING ──→ ORDERED
  조건: 아래 중 하나 충족
    ① 모든 세션 멤버가 투표 완료
       (votes COUNT == session_members COUNT)
    ② 방장이 "투표 종료" 버튼 수동 탭
  처리: NestJS가 최다 득표 restaurant_id를 sessions.winner_restaurant_id에 저장
  동점 처리: 동점 시 방장이 최종 선택

ORDERED ──→ DONE
  조건: 방장이 "세션 종료" 버튼 탭
  처리: NestJS PATCH /sessions/:id/status { status: 'DONE' }
```

sessions 테이블에 winner_restaurant_id 컬럼 추가:
```sql
ALTER TABLE sessions
  ADD COLUMN winner_restaurant_id UUID REFERENCES restaurants(id),
  ADD COLUMN status session_status DEFAULT 'WAITING'; -- VARCHAR → ENUM으로 변경
```

### 투표 종료 조건 및 결과 처리

```
투표 종료 트리거:
  ① 자동: 모든 멤버 투표 완료 감지
     → NestJS에서 votes COUNT == session_members COUNT 체크
  ② 수동: 방장 "투표 종료" 버튼

결과 집계 (별도 테이블 불필요):
  SELECT restaurant_id, COUNT(*) as vote_count
  FROM votes
  WHERE session_id = :id
  GROUP BY restaurant_id
  ORDER BY vote_count DESC
  LIMIT 1

결과 저장:
  → sessions.winner_restaurant_id = 최다 득표 restaurant_id
  → sessions.status = 'ORDERED'
```

### 삭제 정책 (CASCADE/RESTRICT)

| 테이블 | 부모 삭제 시 |
|---|---|
| session_members | sessions 삭제 시 CASCADE |
| votes | sessions 삭제 시 CASCADE |
| cart_items | sessions/users 삭제 시 CASCADE |
| order_items | orders 삭제 시 CASCADE |
| notifications | users 삭제 시 CASCADE |
| orders | sessions 삭제 시 RESTRICT (주문 있으면 세션 삭제 불가) |

---

## 7. API 흐름

### 인증
```
POST /auth/kakao          카카오 토큰 검증 → JWT 발급
```

### 유저
```
POST   /users             프로필 생성 (온보딩)
GET    /users/me          내 프로필 조회
PATCH  /users/me          프로필/조건 수정 (JWT에서 user_id 추출)
GET    /users             팀원 목록 조회 (멤버 선택)
```

### 세션
```
POST   /sessions          세션 생성 (트랜잭션: sessions + session_members + 방장 포함)
GET    /sessions/today    오늘 세션 조회 (홈 대시보드)
GET    /sessions/:id      세션 상세
GET    /sessions/:id/members  세션 멤버 목록 (폴링)
PATCH  /sessions/:id/status   세션 상태 변경
```

### 식당
```
GET    /restaurants       식당 목록 (조건 필터링: 반경/예산/속도)
GET    /restaurants/:id   식당 상세
GET    /restaurants/:id/menus  메뉴 목록
```

### 투표
```
POST   /votes             투표 (UNIQUE 제약으로 중복 차단)
GET    /sessions/:id/votes  투표 현황 (폴링)
```

### 장바구니
```
POST   /cart              메뉴 담기
GET    /cart/:session_id  장바구니 조회
PATCH  /cart/:id          수량 수정 (디바운싱 1초)
DELETE /cart/:id          항목 삭제
```

### 주문
```
POST   /orders            주문 생성 (트랜잭션: orders + order_items + cart 비우기)
GET    /orders/:id        주문 상세/상태 (폴링)
GET    /orders/today      오늘 주문 목록 (점주앱)
PATCH  /orders/:id/status 주문 상태 변경 (점주 수락/거절, POS 완료)
```

### 알림
```
GET    /notifications     알림 목록 (CU-22)
PATCH  /notifications/:id/read  읽음 처리
```

### 폴링 최적화 (304 Not Modified)
```
요청: GET /sessions/:id/members
      Header: If-Modified-Since: {마지막 응답 시각}

응답:
  데이터 변경 있음 → 200 + 데이터
  데이터 변경 없음 → 304 (빈 응답, Flutter는 기존 데이터 유지)
```

---

## 8. MVC 구현 흐름

### 카카오 로그인

```
[버튼 탭] "카카오로 시작하기"

View (LoginScreen)
  → KakaoAuthService.login() 호출

Service
  → 카카오 SDK → 카카오 서버 인증
  → kakao_id, nickname, profile_image 수신
  → NestJS POST /auth/kakao 전달

Controller (NestJS)
  → users 테이블에서 kakao_id 조회
  → 신규: users INSERT → isNewUser: true
  → 기존: JWT 발급 → isNewUser: false

View
  → isNewUser true  → ProfileSetupScreen
  → isNewUser false → HomeScreen
  → Riverpod userProvider 캐시 저장
```

### 세션 생성

```
[버튼 탭] "세션 시작"

View (SessionCreateScreen)
  → NestJS POST /sessions
    body: { name, time, member_ids[] }

Controller (NestJS) [트랜잭션 시작]
  ① sessions INSERT
     { name, status: 'WAITING', created_by, time }
  ② session_members INSERT × 선택 멤버 수
  ③ session_members INSERT (방장 본인) ← 필수
  [트랜잭션 커밋]

View
  → SessionLobbyScreen 이동 (session_id 전달)
```

### 세션 로비 (폴링)

```
View (SessionLobbyScreen)
  → WidgetsBindingObserver 등록
  → Timer.periodic(3초) 시작

  매 3초:
  → NestJS GET /sessions/:id/members
    Header: If-Modified-Since

    304 응답 → 화면 그대로
    200 응답 → 멤버 목록 갱신

  앱 백그라운드 → timer.cancel()
  앱 포그라운드 → 타이머 재시작

  ⚠️ 추후 WebSocket 교체 시 이 부분만 교체
```

### 장바구니 "담기"

```
[버튼 탭] "담기"

View (MenuScreen)
  → 이전 상태 백업 (롤백용)
  → Riverpod cartProvider 낙관적 업데이트 (즉시 UI 반영)
  → NestJS POST /cart 호출
    body: { session_id, menu_item_id, quantity: 1 }

  성공 → 캐시 확정
  실패 → 백업 상태로 롤백 + 사용자 알림 표시

[수량 +/-] 연타 시
  → 디바운싱: 마지막 탭 후 1초 대기
  → NestJS PATCH /cart/:id 1회만 호출
```

### 주문 생성

```
[버튼 탭] "주문하기"

View
  → 다이얼로그 표시
    ├── 개인 결제 선택
    │     → Toss Payments SDK 결제창
    │     → 결제 완료 callback
    │     → NestJS POST /orders
    │         body: { session_id, cart_items[] }
    │
    │       Controller [트랜잭션]
    │         ① Toss Payments 결제 검증
    │         ② orders INSERT { session_id, user_id, status: 'PENDING' }
    │         ③ order_items INSERT × 장바구니 항목 수
    │         ④ cart_items DELETE (장바구니 비우기)
    │         [트랜잭션 커밋]
    │         ⑤ notifications INSERT + FCM 발송 (점주에게)
    │
    └── N분의 1 선택
          → "개발 중입니다 🚧" 안내
```

### 점주 주문 수락

```
[FCM 수신] 점주 폰에 푸시 알림
  → 알림 탭 → 점주앱 진입

View (OrderDashboard)
  → NestJS GET /orders/today 폴링 3초
  → 주문 카드 목록 표시

[버튼 탭] "수락"
  → NestJS PATCH /orders/:id/status
    body: { status: 'ACCEPTED' }

Controller
  → role 검증 (OWNER만 가능)
  → orders UPDATE
  → notifications INSERT + FCM 발송 (손님에게)

View (손님 OrderTrackScreen)
  → 폴링으로 ACCEPTED 감지
  → "점주가 수락했습니다" 표시
```

---

## 9. 보안 및 제약 조건

### 필수 DB 제약
- `votes`: `UNIQUE(user_id, session_id)` — 중복 투표 원천 차단
- `session_members`: `UNIQUE(session_id, user_id)` — 중복 참여 방지
- `orders`: `session_id` FK 필수 — 세션별 주문 추적
- 모든 상태값: ENUM 강제 — 데이터 오염 방지

### 권한 체계
- JWT 토큰 기반 인증 (모든 API)
- `users.role`: CUSTOMER / OWNER / POS
- 투표: 해당 세션 참여자만 가능
- 주문 수락: OWNER만 가능
- POS 완료 처리: POS만 가능

### 트랜잭션 필수 처리
- 세션 생성: sessions + session_members (방장 포함) 묶음
- 주문 생성: orders + order_items + cart 비우기 묶음

### 보안 참고 메모 (후순위)
- SQL Injection 대비
- 딕셔너리 어택 대비
- 레인보우 테이블 공격 대비

---

## 미결 사항

| 항목 | 내용 |
|---|---|
| Q6 앱 분리 구조 | 손님앱/점주앱/POS 분리 방식 팀 합의 필요 (OW-02 착수 전제조건) |
| sessions 테이블 분리 | sessions/session_state/voting_round 분리 여부 팀 합의 필요 |
| 카카오 회원목록 미표시 | 개발자 콘솔 회원목록 미표시 원인 미확인 |

---

*본 명세서는 2026-04-08 기준 확정된 설계를 반영합니다.*
*변경 사항은 project_decisions.md에 과정·이유와 함께 기록합니다.*
