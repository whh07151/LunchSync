# LunchSync 인증·POS·결제 경계 검토

날짜: 2026-08-05
브랜치: `agent/reliability-observability`

## 해결하려는 문제

이번 기능 단위는 service-role Supabase 클라이언트와 외부 결제 API 앞에서
애플리케이션이 직접 소유해야 하는 보안·일관성 경계를 닫는다.

- 공개 휴대폰 인증 요청이 본문의 임의 사용자 ID를 계정 연결 대상으로 삼을 수 있었다.
- 이메일 가입 직후 일반 JWT가 발급되고 OTP를 건너뛸 수 있어 이메일 소유권이
  보호 API의 전제조건이 아니었다.
- 일반 USER JWT가 매장 소유권 확인 없이 POS 전용 API를 호출할 수 있었다.
- Toss 환불 성공 후 주문 상태 UPDATE 오류나 0행 갱신을 성공으로 응답했다.
- 알 수 없거나 생략된 결제 방식이 `SIMULATE`로 바뀌고, `CASH`도 고객 요청만으로
  즉시 `PAID`가 됐다.
- 일회용 PostgreSQL 테스트 스키마의 수량 상한은 실제 선언 스키마에 없는 제약이었다.

## 적용한 경계

### 휴대폰 계정 연결

- 공개 `POST /auth/verify-phone`은 Firebase ID token의 검증된 전화번호로만
  로그인 또는 가입 대상을 찾는다.
- 기존 계정 연결은 `POST /auth/verify-phone/attach`로 분리하고
  `JwtAuthGuard`를 적용한다.
- 대상 사용자 ID는 요청 본문에서 받지 않고 `req.user.userId`에서만 파생한다.
- production과 같은 `forbidNonWhitelisted` 검증에서 공개 요청의
  `existingUserId`는 400으로 거절된다.

### 이메일 OTP와 JWT

- 이메일 가입 응답 형태는 유지하되 10분짜리
  `purpose: EMAIL_VERIFICATION` 제한 토큰만 발급한다.
- `JwtStrategy`는 이 목적 토큰을 일반 보호 API에서 401로 거절한다.
- 이메일 로그인은 비밀번호가 맞아도 `email_verified_at`이 없으면
  `EMAIL_VERIFICATION_REQUIRED`로 거절하며 JWT를 서명하지 않는다.
- LSPOS의 `POST /pos/login-owner`도 같은 `email_verified_at` 조건을 적용해
  일반 이메일 로그인 차단을 우회해 USER/POS JWT를 받을 수 없게 한다.
- 이메일 조회는 wildcard를 escape한 `ILIKE`로 대소문자를 일관되게 처리한다.
  가입은 소문자로 정규화하고, 기존 mixed-case 계정도 로그인·OTP 복구가 가능하다.
- OTP 호출마다 session persistence와 자동 refresh를 끈 별도 Supabase Auth
  client를 사용한다. service-role 데이터 client의 인증 상태와 섞이지 않는다.
- OTP provider 검증과 `public.users.email_verified_at`의 정확한 1행 반영이
  모두 확인된 뒤에만 일반 JWT를 발급한다.
- 변경 전 발급된 일반 JWT도 매 요청에서 현재 계정의 `auth_provider`와
  `email_verified_at`을 확인한다. 계정 조회 장애는 401로 축소하지 않고 재시도 가능한
  `SESSION_ACCOUNT_LOOKUP_FAILED` 503으로 반환해 정상 세션 삭제를 유발하지 않는다.
- Flutter는 가입 응답의 제한 토큰을 저장하지 않는다. OTP 검증 응답의 일반
  `AuthResult`만 Riverpod과 SharedPreferences에 저장하며 건너뛰기 UI를 제거했다.

Supabase JavaScript UPDATE는 `.select()`를 연결해야 갱신 행을 반환하므로,
OTP·결제·환불 상태 전환은 반환 행을 확인한다. 참고:
<https://supabase.com/docs/reference/javascript/update>

### POS 권한과 매장 매핑

- POS token은 token의 `restaurantId`와 요청 매장이 같을 때만 허용한다.
- USER token은 `OWNER`이면서 `APPROVED`인지를 조회한 뒤 매장 소유권을 확인한다.
- 소유권의 기준은 고유 인덱스가 있는 `restaurants.owner_user_id`다.
- 기존 데이터 호환을 위해 canonical owner가 비어 있는 매장에 한해서만
  `users.restaurant_id` 일치를 허용한다. 다른 owner가 기록된 매장에는 legacy
  값이 같아도 접근할 수 없다.
- owner가 비어 있는 legacy 매장은 POS 토큰 발급 전에 조건부 UPDATE로 canonical
  소유권을 승격한다. 같은 legacy 매장이 둘 이상의 사용자에 연결돼 있으면 어느
  계정도 선착순으로 점유하지 못하게 차단한다.
- owner-backed POS JWT는 `ownerUserId`와 `authMode: OWNER`를 포함하고, 각 요청에서
  승인 상태와 현재 canonical 매핑을 다시 확인한다. 구형 POS 토큰은 거절한다.
- `GET /users/me`는 canonical 매장 ID를 우선 반환해 Flutter가 새 등록 매장으로
  정상 라우팅되도록 한다.
- 자기 매장 주문 차단도 legacy 사용자 필드뿐 아니라 `restaurants.owner_user_id`를
  확인한다. 신규 점주처럼 `users.restaurant_id`가 NULL이어도 자기 매장 주문으로
  매출·단골 통계를 오염시킬 수 없다.
- 매장 ID와 전 매장 공용 `POS_PIN`만으로 토큰을 만드는 경로는 production에서
  항상 비활성이다. 비운영에서도 `POS_SHARED_PIN_LOGIN_ENABLED=true`와 PIN을
  모두 명시한 시연에만 허용한다. 운영 POS는 검증된 승인 점주 로그인으로
  매장 범위를 파생한다.

service-role은 RLS를 우회하므로 이 검사는 편의 기능이 아니라 실제 인가 경계다.
RLS 참고: <https://supabase.com/docs/guides/database/postgres/row-level-security>

### 주문 결제 방식

- 생략된 결제 방식의 기본값은 `TOSS`이며 주문은 `PENDING`이다.
- 알 수 없는 결제 문자열은 400으로 거절하고 `SIMULATE`로 폴백하지 않는다.
- `SIMULATE`는 비운영 환경이면서 `ALLOW_SIMULATED_PAYMENTS=true`를 명시한 경우에만
  허용한다. 환경변수가 없거나 빈 문자열·`false`면 fail-closed로 거절한다.
- `CASH`, `CARD`, `TOSS`는 고객 주문 생성만으로 결제 증거가 되지 않으므로
  `PENDING`을 유지한다. 현금 수납은 권한 있는 POS 확인 경계에서 처리한다.
- 비운영 환경의 명시적 `SIMULATE`만 테스트용 `PAID` 전환을 허용한다. POS `CARD`
  시뮬레이션과 환불 시뮬레이션도 각각 별도 명시 플래그가 필요하고 실제 결제키에는
  적용할 수 없다.
- 고객의 `PATCH /orders/:id/status`는 `CANCELLED`만 받는다. `PAID`는 DTO와
  서비스 전이표에서 모두 제거해 Toss/POS 경계를 우회할 수 없다.
- 고객 취소 UPDATE는 읽은 기존 상태를 조건으로 사용한다. 결제 승인과 경합해
  상태가 먼저 바뀌면 덮어쓰지 않고 `ORDER_STATUS_CHANGED` 409를 반환한다.

### Toss 환불과 DB 조정

- 외부 취소 요청에는 주문별 안정 키 `lunchsync-cancel:{orderId}`를
  `Idempotency-Key`로 전달한다.
- `TOSS_API_TIMEOUT_MS`는 100~60,000ms만 허용하고 기본 10초로 제한한다.
- 성공 응답의 `paymentKey`, `orderId`, 전체 결제 상태, 최신 cancel 상태와
  양수 환불 금액을 검증한다.
- 결제 확인은 `TOSS` 주문에만 허용한다. 공급자 승인 뒤 고객 취소가 DB를 먼저
  선점하면 즉시 보상 환불하고, 보상 실패는 별도 재조정 필요 503으로 반환한다.
- POS 취소 UPDATE는 최초로 읽은 status와 payment key에 정확히 묶는다. PENDING/no-key
  스냅샷 뒤 결제가 승인되면 최신 결제키를 다시 읽어 실제 환불 경로로 전환한다.
- 외부 환불 뒤 DB 저장을 확인하지 못하면 성공을 가장하지 않고
  `REFUND_COMPLETED_DB_SYNC_PENDING` 503을 반환한다.
- 동시 취소가 이미 같은 주문을 `CANCELLED`로 만들었다면 재조회 후 멱등 성공으로
  조정한다. 환불 직후 조리 상태가 먼저 진행된 경우 최신 상태·결제키를 대상으로
  최대 5회의 bounded CAS로 `CANCELLED`에 수렴시킨다.
- Toss 5xx와 비 JSON 5xx는 503, 멱등 요청 처리 중은 재시도 가능한 409,
  확정적 4xx만 400으로 구분한다.
- 로그에는 전체 결제사 응답이나 원문 payment key를 남기지 않는다.

Toss 결제 취소 API의 멱등키와 취소 응답 계약을 기준으로 구현했다. 참고:
<https://docs.tosspayments.com/reference#결제-취소>

외부 승인·환불과 DB 쓰기는 하나의 트랜잭션이 될 수 없다. 현재 요청 안의 보상과
bounded CAS는 프로세스 중단 뒤까지 살아남지 않는다. 남은 중간 위험은 provider
작업 ledger/outbox, `REFUNDING` 선점 상태, 재시작 가능한 reconciliation worker,
운영 재조정 화면과 감사 원장으로 닫아야 한다.

## PostgreSQL 테스트 계약

일회용 테스트 스키마의 `order_items.quantity`를 실제 선언과 같은 `> 0`으로
맞췄다. 트랜잭션 롤백 검사는 가짜 수량 상한 10에 의존하지 않고, service-role이
실제 RPC를 호출해 존재하지 않는 메뉴 FK 삽입을 실패시킨 뒤 주문 헤더와 항목이
모두 0행인지 확인한다.

## 검증

실행 완료:

```powershell
cd backend
cmd /c npm test -- --runInBand
cmd /c npm run build

cd ..
cmd /c C:\flutter\bin\flutter.bat test --no-pub --reporter expanded
cmd /c C:\flutter\bin\cache\dart-sdk\bin\dart.exe analyze --fatal-infos
git diff --check
```

결과:

- NestJS Jest: 26개 스위트, 152개 테스트 통과.
- NestJS build: 통과.
- Flutter: 12개 테스트 통과.
- Dart analyze: 문제 0개.
- production npm audit: high/critical 0개, `firebase-admin` 하위 트리 moderate 8개.
- `git diff --check`: 통과. Windows 줄바꿈 안내만 있었다.

`npm run test:postgres`는 Docker Desktop Linux 엔진이 실행 중이지 않아 이번
세션에서 실행하지 못했다. 따라서 수정된 실제 PostgreSQL 롤백 테스트는 통과로
기록하지 않는다.

## 배포·롤백과 사람 검토

- 실제 Supabase 마이그레이션, Toss 요청, 운영 배포는 수행하지 않았다.
- 배포 전 비운영 복제본에서 `restaurants.owner_user_id`와
  `users.restaurant_id` 불일치·NULL·중복 매핑을 read-only join으로 집계한다.
- 기존 미인증 이메일 계정 수와 구버전 앱의 `existingUserId` 요청 여부를 확인한다.
- Docker를 실행한 뒤 PostgreSQL 전용 계약 검사를 다시 실행한다.
- Toss 테스트 키로 동일 주문 취소 재시도, timeout 후 재시도와 DB 조정 상태를
  사람이 확인한다.
- durable 결제 outbox를 추가할 때는 선언형 `supabase/schemas/`를 먼저 변경하고
  Docker가 준비된 환경에서 migration을 생성·검증한다. 이번 주기에는 migration을
  손으로 만들거나 원격 DB에 적용하지 않았다.
- 롤백 시에도 IDOR·미인증 JWT·POS USER 우회를 다시 열지 않는다. 호환 문제가
  생기면 구버전 API를 복원하는 대신 명시적 버전 응답과 데이터 매핑 보정으로 해결한다.

AI는 코드 경로 매핑, 위협 모델, 회귀 테스트와 구현 초안을 작성했다. 사람은 실제
사용자 데이터의 매핑, 이메일 전달성, Toss 대시보드 결과, 운영 로그와 배포 여부를
별도로 검증해야 한다.
