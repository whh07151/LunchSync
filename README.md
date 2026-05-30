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

- Node.js 20+, npm
- Flutter 3.x 안정 채널 (Dart 3+)
- `backend/.env` 값 확보 (팀원에게 공유 받음, 또는 `backend/.env.example` 참고)
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

카카오 로그인 redirect URI 와 일치시키기 위해 **포트 8080 고정**, EC2 / DuckDNS 백엔드를 가리키도록 `BACKEND_URL` dart-define 필수입니다. (생략 시 `lib/core/config/app_config.dart` 의 EC2 기본값을 사용합니다.)

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
| `SUPABASE_ANON_KEY` | Supabase anon 키 | `.env.example` 에 명시 |
| `SUPABASE_SERVICE_ROLE_KEY` | RLS 우회용 service_role 키 | **서버 전용** · `.env.example` 미포함이므로 직접 추가 |
| `JWT_SECRET` | 자체 JWT 서명 시크릿 | 필수 |
| `JWT_EXPIRES_IN` | JWT 만료 (기본 `7d`) | |
| `TOSS_SECRET_KEY` | Toss Payments 시크릿 키 | 테스트는 `test_sk_...` |
| `TOSS_API_BASE_URL` | Toss API 베이스 | 기본 `https://api.tosspayments.com` |
| `NAVER_CLIENT_ID` / `NAVER_CLIENT_SECRET` | 네이버 검색 API (식당 메타) | crawl 모듈에서 사용 |
| `KAKAO_REST_API_KEY` | 카카오 로컬 API (좌표 / 식당) | crawl · recommendations 폴백 |
| `GEMINI_API_KEY` | Gemini LLM API 키 | 미설정 시 AI 메뉴/식당 폴백 비활성 |
| `GEMINI_MODEL` | Gemini 모델명 | 기본 `gemini-2.0-flash` |
| `FIREBASE_PROJECT_ID` | Firebase 프로젝트 ID (`lunchsync-cf32f`) | Phone Auth + FCM |
| `FIREBASE_ADMIN_KEY_PATH` | Firebase Admin 서비스 계정 JSON 경로 | 미설정 시 Phone Auth / FCM 푸시 비활성 |
| `CORS_ALLOWED_ORIGINS` | 운영 모드 CORS 허용 origin (쉼표) | `NODE_ENV=production` 일 때만 활성 |
| `NODE_ENV` | `production` 설정 시 에러 메시지 마스킹 + CORS 화이트리스트 적용 | |
| `RECO_V3_ENABLED` | 추천 v3 (친구 가중치 등) on/off | `'true'` 일 때 활성 |

> `.env.example` 에 누락된 키(`SUPABASE_SERVICE_ROLE_KEY`, `GEMINI_*`, `FIREBASE_*`, `CORS_*`, `RECO_V3_*`)는 팀 노션 / 팀원 공유 채널에서 받아 직접 추가해야 합니다.

Flutter 측 키(카카오 앱 키, Toss 클라이언트 키)는 `lib/core/config/app_config.dart` 에 하드코딩되어 있고 이 파일은 `.gitignore` 처리 상태입니다.

---

## AWS 배포 (EC2 + DuckDNS)

운영 백엔드는 AWS EC2 (`13.125.165.80`) 위에서 NestJS 가 직접 동작하며, DuckDNS 도메인으로 HTTPS 종단됩니다. Flutter 앱 기본값(`app_config.dart`)도 이 주소를 가리킵니다.

배포 원칙은 memory 의 `feedback_aws_deploy.md` 에 정리된 대로 **로컬에서 빌드 성공 + 핵심 흐름 검증이 끝난 코드만 배포**합니다.

대략적인 절차 (구체 명령은 운영자만 사용):

1. `main` (또는 머지 대상 브랜치)에 push → CI 빌드 확인
2. EC2 에 SSH 접속 → `git pull` → `npm ci` → `npx nest build`
3. 새 마이그레이션이 있다면 Supabase 대시보드에서 `backend/scripts/migrations/<날짜>-*.sql` 수동 실행
4. `pm2 restart <프로세스명>` (혹은 동등 명령)
5. Flutter 앱(또는 LSPOS) 빌드는 dart-define `BACKEND_URL=https://<DuckDNS>/api` 로 재빌드
6. 손님 / 사장 두 흐름을 실기기에서 한 번씩 검증 (홈 → 세션 → 투표 → 주문 → 결제)

> `<DuckDNS-도메인>` 실값과 PM2 프로세스 이름, 키 보관 경로는 팀 운영 채널에 별도 공유합니다.

---

## DB 스키마 변경 규칙 (silent failure 방지)

`CLAUDE.md` 의 핵심 규칙이며 위반 시 PostgREST 가 누락 컬럼을 silent 하게 무시해 "코드는 정상인데 DB 는 비어있는" 사고가 발생합니다 (2026-05-13 `image_url` 사고 사례).

- 새 컬럼 / 테이블을 `select` 또는 `insert` 에 추가할 때는 **반드시 같은 PR 에 DDL 마이그레이션을 동봉**합니다.
- 마이그레이션 위치: `backend/scripts/migrations/YYYY-MM-DD-<설명>.sql`
- 모든 DDL 은 멱등 패턴 — `CREATE TABLE IF NOT EXISTS`, `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`
- 마이그레이션 추가 시 `backend/scripts/migrations/2026-05-14-verify-schema.sql` 검증 쿼리도 갱신
- 운영 적용: Supabase 대시보드에서 수동 실행 → verify-schema 한 번 더 돌려 확인

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
