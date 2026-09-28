# LunchSync

> 그룹 점심 조율 앱 — 식당 추천 · 투표 · 주문 · 결제 · POS 까지 하나의 흐름으로 연결합니다.
>
> Flutter 단일 앱(역할 분기: 손님 / 사장) + NestJS 백엔드 + 별도 Next.js POS 단말 구성. 인증은 카카오 + 이메일 OTP + Firebase Phone Auth, 결제는 Toss Payments v2 결제위젯, 추천은 Gemini + 카카오 좌표 폴백, 푸시는 FCM 으로 동작합니다.

---

## 팀 / 역할

| 이름 | 주요 담당 |
|---|---|
| 우현호 | 팀장 / 백엔드(NestJS) / 카카오 로그인 · 세션 API / 결제 / AI 추천 / EC2 배포 |
| 장다연 | RAG 설계 / 식당 데이터 수집·정규화 / 추천 근거 / 운영 통계 / LSPOS |
| 김지효 | 모바일 프론트(Flutter) / UX / 디자인 시스템 / 화면 연결 / POSJIHYO |
| 안태환 | 백엔드 보조 / POS 시뮬레이터 / 실시간 상태동기화 / QA |

---

## 기술 스택

| 영역 | 기술 |
|---|---|
| 모바일 / 웹 앱 | Flutter + Riverpod (단일 앱, `role` 분기로 손님 / 사장 화면) |
| 백엔드 API | NestJS 11 (TypeScript) — `backend/src/` |
| DB / Auth Storage | Supabase (PostgreSQL, service_role 키로만 접근) |
| 인증 | 카카오 SDK + 이메일 OTP + Firebase Phone Auth + 자체 JWT |
| 결제 | Toss Payments v2 결제위젯 (test_ck / live_ck) |
| AI 추천 | Google Gemini (`gemini-2.0-flash`) + 카카오 로컬 API 좌표 폴백 |
| 외부 데이터 | 네이버 검색 API (식당 메타) · Unsplash (메뉴 사진) |
| 푸시 알림 | Firebase Cloud Messaging |
| POS 단말 | LSPOS / POSJIHYO (별도 Next.js + Vercel) |
| 백엔드 배포 | AWS EC2 (`13.125.165.80`) + DuckDNS HTTPS 도메인 |

---

## 저장소 구성

LunchSync 는 GitHub 상에서 세 개의 폴더를 함께 사용합니다. 본 저장소(`LunchSync`)가 모바일 앱 + 백엔드 본체이고, POS 는 별도 Next.js 리포로 분리되어 있습니다.

```
D:\LunchSyncFr\
├── LunchSync\              ← 본 저장소 (Flutter 앱 + NestJS 백엔드)
│   ├── lib\                # Flutter 소스 (features/, providers/, services/, models/, core/)
│   ├── backend\src\        # NestJS 모듈
│   │   ├── auth\           # 카카오 / 이메일 OTP / Firebase Phone Auth / JWT
│   │   ├── sessions\       # 점심 세션 CRUD · 멤버 · 상태 전이
│   │   ├── invitations\    # 초대코드 발급 / 수락
│   │   ├── restaurants\    # 식당 · 메뉴 · 카테고리
│   │   ├── recommendations\# 추천 점수화 (v3 옵션)
│   │   ├── crawl\          # 네이버 + Gemini 식당/메뉴 폴백
│   │   ├── gemini\         # Gemini LLM 클라이언트
│   │   ├── votes\          # 투표 · 결과 확정
│   │   ├── orders\         # 주문 · 카트 · order_items
│   │   ├── payments\       # Toss confirm / 환불
│   │   ├── pos\            # 점주 주문 · 메뉴 · 좌석 · 예약
│   │   ├── friends\        # 친구 · 가중치
│   │   ├── notifications\  # 알림함 + FCM 푸시
│   │   ├── users\          # 프로필 · role · fcm_token
│   │   └── supabase\       # Supabase 클라이언트 모듈
│   ├── backend\scripts\    # 시드 · E2E 테스트 · migrations\*.sql
│   ├── web\                # Flutter 웹 빌드 진입점 + toss-checkout.html
│   ├── docs\               # 명세서 / DTO / 인증 결정 등
│   └── USER_GUIDE.md       # 최종 사용자 가이드 (220 라인)
│
├── LunchSync-LSPOS\        ← Next.js POS 단말 (다연 운영, Vercel)
└── LunchSync-POSJIHYO\     ← Next.js POS 단말 (지효 운영, Vercel, 사장 계정 로그인 인프라)
```

> 본 README 는 `LunchSync` 본체 저장소만 다룹니다. POS 두 리포는 각자의 `README.md` / `DEPLOY_VERCEL.md` 를 참고하세요.

---

## 로컬 실행

### 사전 준비

- Node.js 22+, npm
- 백엔드는 Firebase Auth/FCM만 사용하므로 `backend/.npmrc`에서 사용하지 않는
  Firebase Firestore/Cloud Storage 선택 의존성을 설치하지 않습니다.
- Flutter 3.x 안정 채널 (Dart 3+)
- `backend/.env.example`을 기준으로 한 로컬 설정과 승인된 비밀 관리자 또는
  런타임 환경 변수 주입 경로
- Supabase 프로젝트 접근 권한 + 최신 마이그레이션 적용 상태
- (선택) Android 실기기 USB 디버깅, Chrome (웹 결제 테스트)

### 1) 백엔드 (NestJS)

PowerShell:

```powershell
Copy-Item backend\.env.example backend\.env   # 최초 1회, 값 채우기
Set-Location backend
npm install
npm run start:dev                              # http://localhost:3000  (글로벌 prefix: /api)
```

bash (보조):

```bash
cp backend/.env.example backend/.env
cd backend && npm install && npm run start:dev
```

빌드만 검증할 때:

```powershell
Set-Location backend; npx nest build           # 에러 0건이어야 정상
```

### 2) Flutter 웹 (Chrome)

카카오 로그인 redirect URI 및 카카오 지도 JavaScript SDK 허용 도메인과 일치시키기 위해 로컬 웹은 **포트 8080**을 사용합니다. `BACKEND_URL` 생략 시 로컬 백엔드가 기본값입니다. 지도는 로그인 앱과 별도의 카카오맵 사용 앱 JavaScript 키가 필요하며, 키 없이 빌드하면 지도 대신 식당 목록과 안내를 표시합니다.

지도 무료 앱의 JavaScript 키를 Git 제외 `.local/kakao-map-js-key.local`에 저장한 뒤 앱·웹을 빌드합니다. 로그인 앱 키는 그대로 유지됩니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-local-client.ps1 -Target web
node scripts/local-web.cjs                    # http://localhost:8080
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-local-client.ps1 -Target apk
```

지도 및 메뉴 데이터 출처와 로컬 카카오 키 설정은 `docs/study/NEARBY_PLACES_AND_MENU_SOURCES_2026-09-28.md`를 참고하세요.

```powershell
flutter pub get
flutter run -d chrome --web-port 8080 `
  --dart-define=BACKEND_URL=https://<DuckDNS-도메인>/api
```

로컬 백엔드를 가리킬 때:

```powershell
flutter run -d chrome --web-port 8080 `
  --dart-define=BACKEND_URL=http://localhost:3000/api
```

### 3) Flutter 안드로이드 실기기

```powershell
$IP = (ipconfig | Select-String "IPv4" | Select-Object -First 1) -replace '.*:\s*', '' -replace '\s', ''
echo $IP
flutter run --dart-define=BACKEND_HOST=$IP
```

EC2(DuckDNS) 백엔드로 바로 붙이려면:

```powershell
flutter run --dart-define=BACKEND_URL=https://<DuckDNS-도메인>/api
```

### 4) 정적 분석

```powershell
flutter analyze                                # 에러 0건이어야 정상
```

---

## 환경 변수

`backend/.env` 는 git 에 포함되지 않습니다. `backend/.env.example` 를 복사해서 채우세요.

| 키 | 용도 | 비고 |
|---|---|---|
| `PORT` | NestJS 리스닝 포트 | 기본 3000 |
| `SUPABASE_URL` | Supabase 프로젝트 URL | 필수 |
| `SUPABASE_SERVICE_ROLE_KEY` | RLS 우회용 service_role 키 | **서버 전용** · 승인된 비밀 관리자에서 런타임 환경 변수로 주입하고 파일·메신저·문서에 실값을 남기지 않음 |
| `SUPABASE_ANON_KEY` | sessionless OTP Auth client 키 | 권장 · 미설정 호환 경로는 service-role 사용 |
| `JWT_SECRET` | 자체 JWT 서명 시크릿 | 필수 |
| `JWT_EXPIRES_IN` | JWT 만료 (기본 `7d`) | |
| `TOSS_SECRET_KEY` | Toss Payments 시크릿 키 | 테스트는 `test_sk_...` |
| `TOSS_API_BASE_URL` | Toss API 베이스 | 기본 `https://api.tosspayments.com` |
| `TOSS_API_TIMEOUT_MS` | 결제 승인 응답 제한 시간(100~60000ms) | 기본 `10000` |
| `NAVER_CLIENT_ID` / `NAVER_CLIENT_SECRET` | 네이버 검색 API (식당 메타) | crawl 모듈에서 사용 |
| `KAKAO_REST_API_KEY` | 카카오 로컬 API (좌표 / 식당) | crawl · recommendations 폴백 |
| `GEMINI_API_KEY` | Gemini LLM API 키 | 미설정 시 AI 메뉴/식당 폴백 비활성 |
| `GEMINI_MODEL` | Gemini 모델명 | 기본 `gemini-2.0-flash` |
| `FIREBASE_PROJECT_ID` | Firebase 프로젝트 ID (`lunchsync-cf32f`) | Phone Auth + FCM |
| `FIREBASE_ADMIN_KEY_PATH` | Firebase Admin 서비스 계정 JSON 경로 | 미설정 시 Phone Auth / FCM 푸시 비활성 |
| `CORS_ALLOWED_ORIGINS` | 운영 모드 CORS 허용 origin (쉼표) | `NODE_ENV=production` 일 때만 활성 |
| `NODE_ENV` | `production` 설정 시 에러 메시지 마스킹 + CORS 화이트리스트 적용 | |
| `POS_SHARED_PIN_LOGIN_ENABLED` / `POS_PIN` | 공용 PIN POS 시연 | 비운영에서 명시적으로 켠 경우만 허용 |
| `ALLOW_SIMULATED_PAYMENTS` | 고객 모의 결제 | 비운영에서 정확히 `true`인 경우만 허용 |
| `ALLOW_REFUND_SIMULATION` | 모의 결제 환불 시연 | 실제 결제키에는 적용 불가 |
| `ALLOW_POS_CARD_SIMULATION` | POS CARD 수납 시연 | 비운영에서 정확히 `true`인 경우만 허용 |
| `RECO_V3_ENABLED` | 추천 v3 (친구 가중치 등) on/off | `'true'` 일 때 활성 |

> `.env.example` 에 누락된 키(`GEMINI_*`, `FIREBASE_*`, `CORS_*`, `RECO_V3_*`)는
> 환경별 설정 절차에 따라 추가합니다. `SUPABASE_SERVICE_ROLE_KEY` 실값은 승인된
> 비밀 관리자 또는 배포 플랫폼의 보호된 환경 변수에서 서버 런타임에만 주입하며,
> Notion·메신저·공유 문서·Git에는 복사하지 않습니다.

Flutter 측 키(카카오 앱 키, Toss 클라이언트 키)는 `lib/core/config/app_config.dart` 에 하드코딩되어 있고 이 파일은 `.gitignore` 처리 상태입니다.

---

## AWS 배포 (EC2 + DuckDNS)

운영 백엔드는 AWS EC2 (`13.125.165.80`) 위에서 NestJS 가 직접 동작하며, DuckDNS 도메인으로 HTTPS 종단됩니다. Flutter 앱 기본값(`app_config.dart`)도 이 주소를 가리킵니다.

배포 원칙은 memory 의 `feedback_aws_deploy.md` 에 정리된 대로 **로컬에서 빌드 성공 + 핵심 흐름 검증이 끝난 코드만 배포**합니다.

대략적인 절차 (구체 명령은 승인된 운영자만 사용):

1. 머지 대상 브랜치의 CI와 로컬 검증 결과를 확인
2. 비운영 PostgreSQL 리허설 환경에
   `backend/scripts/migrations/2026-07-27-create-order-with-items-v2.sql` 적용
3. 이어서
   `backend/scripts/migrations/2026-07-29-schema-introspection-function-signatures.sql`
   적용
4. 비운영 환경에서 정확한 6-인자 주문 RPC, `SECURITY INVOKER`, 최소 실행 ACL과
   스키마 introspection 응답을 검사
5. 리허설이 통과한 뒤 승인된 운영자가 실제 백엔드가 연결할 대상 PostgreSQL에
   검토된 두 마이그레이션을 2026-07-27 → 2026-07-29 순서로 적용
6. 같은 대상 DB에서 정확한 함수 시그니처, `PUBLIC`/`anon`/`authenticated`
   실행 권한 회수, `service_role` 실행 권한과 `check_schema_resources()`
   introspection 응답을 다시 확인
7. 대상 DB 검증이 끝난 뒤에만 EC2 백엔드 코드 갱신 → `npm ci` →
   `npx nest build` →
   `pm2 restart <프로세스명>`(또는 동등 명령)
8. Flutter 앱(또는 LSPOS)은
   `BACKEND_URL=https://<DuckDNS>/api`로 빌드
9. 손님 / 사장 흐름과 `SIMULATE`/`CASH`, Toss·`CARD`의 `PENDING` → 외부 승인
   흐름을 비운영 환경에서 확인

6-인자 RPC를 호출하는 백엔드를 두 마이그레이션보다 먼저 배포하지 않습니다.
실제 대상 DB 마이그레이션과 백엔드 배포는 승인된 운영자의 남은 작업이며, 이
변경 작성·검증 과정에서는 실행하지 않았습니다.
`<DuckDNS-도메인>`과 PM2 프로세스 이름은 승인된 운영 런북에서 확인하고, 비밀
값은 승인된 비밀 관리자나 배포 플랫폼의 보호된 환경 변수로만 주입합니다.

주문 생성·스키마 헬스체크 변경의 핵심 확인 파일:

- `backend/scripts/migrations/2026-07-27-create-order-with-items-v2.sql`
- `backend/scripts/migrations/2026-07-29-schema-introspection-function-signatures.sql`
- `backend/src/orders/orders.controller.ts`
- `backend/src/orders/orders.service.ts`
- `backend/src/orders/orders.consistency.spec.ts`
- `backend/src/app.module.ts`
- `backend/src/supabase/schema-healthcheck.service.ts`
- `backend/src/supabase/schema-healthcheck.service.spec.ts`
- `backend/package.json`
- `backend/test/jest-postgres.json`
- `backend/test/orders.postgres-spec.ts`
- `backend/test/support/disposable-postgres.ts`

2026-07-29 현재 체크포인트에서 기본 Jest는 **7개 스위트·47개 테스트**, 실제
PostgreSQL 계약 검사는 **2개 스위트·5개 테스트**, NestJS 빌드는 통과했습니다.
이는 비운영 일회용 PostgreSQL 검증 결과이며 운영 DB 마이그레이션이나 라이브 결제
검증을 뜻하지 않습니다.

2026-08-05 인증·POS·결제 하드닝 체크포인트는 기본 Jest **26개 스위트·152개
테스트**, NestJS build, Flutter **12개 테스트**, Dart analyze를 통과했습니다.
Docker Desktop Linux 엔진이 꺼져 있어 변경된 PostgreSQL 전용 검사는 재실행하지
않았으며, 실제 Toss 호출·원격 DB 변경·배포는 수행하지 않았습니다.

---

## DB 스키마 변경 규칙 (silent failure 방지)

`CLAUDE.md` 의 핵심 규칙이며 위반 시 PostgREST 가 누락 컬럼을 silent 하게 무시해 "코드는 정상인데 DB 는 비어있는" 사고가 발생합니다 (2026-05-13 `image_url` 사고 사례).

- 새 Supabase 컬럼·테이블·함수는 먼저 `supabase/schemas/` 선언형 스키마에 반영합니다.
- Docker가 준비된 비운영 환경에서 Supabase CLI diff로 migration을 생성하고,
  reset·pgTAP·schema diff 없음까지 확인합니다. migration을 손으로 작성하지 않습니다.
- `backend/scripts/migrations/`는 기존 legacy 이력의 참고 위치이며 새 선언형 변경의
  source of truth가 아닙니다.
- 운영 적용: Supabase 대시보드에서 수동 실행 → verify-schema 한 번 더 돌려 확인

---

## 개발 우회 (QA / 자동 테스트용)

자동 QA 가 사장(OWNER) 모드를 검증하려면 본인 user 의 role/status/restaurant_id 를 매번 SQL 로 바꿔야 했음. 이를 라우트 한 번으로 대체:

```
POST /api/dev/promote-to-owner
Authorization: Bearer <user JWT>
Body: { "restaurantId"?: "<uuid>" }     # 미지정 시 본인의 마지막 PAID 주문 식당으로 자동 매핑
      { "role": "CUSTOMER" }            # 원복용
```

활성 조건 (EC2):
```bash
ssh ubuntu@<EC2>
echo 'DEV_PROMOTE_ENABLED=true' >> /home/ubuntu/LunchSync/backend/.env
pm2 reload lunchsync-backend
```

보안 게이트: ① JwtAuthGuard 가 본인 JWT 만 수락 (다른 사용자 promote 불가) ② `DEV_PROMOTE_ENABLED='true'` 미설정 시 즉시 ForbiddenException ③ promote 발생마다 Logger.warn 기록. 캡스톤 마무리 후엔 환경변수 제거 권장.

---

## 문서 인덱스

- [`USER_GUIDE.md`](./USER_GUIDE.md) — 최종 사용자(손님 / 사장 / POS 운영자) 가이드 + FAQ
- [`docs/LUNCHSYNC_SPECIFICATION.md`](./docs/LUNCHSYNC_SPECIFICATION.md) — DB 스키마 + API 명세
- [`docs/LUNCHSYNC_DTO.md`](./docs/LUNCHSYNC_DTO.md) — 요청 / 응답 DTO 상세
- [`docs/LUNCHSYNC_CODE_GUIDE.md`](./docs/LUNCHSYNC_CODE_GUIDE.md) — 코드 구조 가이드
- [`docs/LUNCHSYNC_AUTH_DECISION.md`](./docs/LUNCHSYNC_AUTH_DECISION.md) — 회원가입 / 인증 의사결정 기록
- [`docs/LUNCHSYNC_PROGRESS.md`](./docs/LUNCHSYNC_PROGRESS.md) — 구현 진행 현황 (모듈별 상세)
- [`CLAUDE.md`](./CLAUDE.md) — 프로젝트 작업 시 지켜야 할 아키텍처 / 컨벤션 / DB 규칙

> 4/14 시점의 PR 머지 히스토리(이전 README 의 `0414-1 머지 내용 정리` 섹션)는 본 README 에서 제거되었습니다. 필요 시 git log 또는 별도 `CHANGELOG.md` 로 분리해 보관하세요.

---

## 구현 현황 (2026-05-30 기준 큰 영역)

| 영역 | 상태 | 비고 |
|---|---|---|
| 카카오 / 이메일 OTP / Firebase Phone Auth | 완료 | 단일 앱 + role 분기, OWNER 가입 승인제 |
| 세션 생성 · 초대 · 로비 · 멤버 폴링 | 완료 | 3초 폴링 + HTTP 304 최적화 |
| AI 식당 추천 (Gemini + 카카오 폴백) | 완료 | 빈 결과 시 좌표 동네에 가상 식당 자동 생성 + DB 저장 |
| 투표 / 결과 확정 / 룰렛 · 사다리 | 완료 | UNIQUE(user_id, session_id) 1인 1투표 |
| 메뉴 · 카테고리 · 알레르기 / 재료 | 완료 | Unsplash 메뉴 사진 폴백 |
| 주문 · 카트 · order_items + RPC | 완료 | 트랜잭션 RPC 로 묶음 처리 |
| Toss Payments v2 결제위젯 | 완료 | 결제수단별 매출 분리 집계 포함 |
| 사장 홈 · 메뉴 관리 · 매출 통계 · 매장 정보 수정 | 완료 | role=OWNER 전용 탭 |
| LSPOS / POSJIHYO (Next.js POS) | 진행 중 | 좌석 / 예약 백엔드 연결 완료, 사장 계정 로그인 인프라 적용 |
| FCM 푸시 · 알림함 | 완료 | `users.fcm_token` 저장 + best-effort 송신 |
| 친구 / 가중치 추천 v3 | 부분 적용 | `RECO_V3_ENABLED=true` 일 때 활성 |
| AWS EC2 + DuckDNS HTTPS 배포 | 운영 중 | Flutter 앱 기본값 = EC2 |

세부 상태(티켓 단위, 화면별 완료도)는 `docs/LUNCHSYNC_PROGRESS.md` 와 memory 의 `project_implementation_status.md` 를 참고하세요.
