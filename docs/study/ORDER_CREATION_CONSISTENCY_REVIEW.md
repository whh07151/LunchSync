# LunchSync 주문 생성 일관성 검토

날짜: 2026-07-29
브랜치: `agent/reliability-observability`
초안 PR: https://github.com/whh07151/LunchSync/pull/15

## 해결하려는 문제

기존 `POST /api/orders`는 `orders` 행과 `order_items` 행을 서로 다른 Supabase
요청으로 저장했다. 항목 INSERT 오류가 발생해도 서비스가 이를 주문 전체 실패로
처리하지 않고 가상 결제로 진행할 수 있어, 주문 헤더만 `PAID`로 남고 항목은 없는
부분 저장 상태가 가능했다.

이번 변경에는 게시 전 해결해야 할 보안 공백도 있다. PostgreSQL은 새 함수에
기본적으로 `PUBLIC EXECUTE`를 부여하므로, 새 RPC를 생성만 하고 실행 권한을
회수하지 않으면 Flutter가 사용하지 않더라도 `anon` 또는 `authenticated` 역할이
PostgREST RPC 표면을 통해 함수를 직접 호출할 가능성이 생긴다.

## 사용자 영향

손님은 성공 응답을 받았는데 매장에는 조리할 메뉴가 없는 주문이 보일 수 있다.
이 상태에서는 결제 금액, 주방 준비, 취소와 환불의 근거를 일관되게 설명할 수 없다.

RPC 권한이 넓게 열리면 NestJS의 JWT 인증, DTO 검증, 같은 식당 메뉴 검증,
서버 가격 계산을 우회해 데이터베이스 함수를 직접 호출할 수 있다. 따라서 주문
원자성과 RPC 실행 권한은 같은 게시 차단 기준으로 다룬다.

## 근본 원인

- Supabase `.from(...).insert(...)` 요청 두 번은 각각 별도 데이터베이스
  트랜잭션이므로 서비스 코드만으로 원자적 커밋을 보장하지 못했다.
- 저장소에 기존 `create_order_with_items` 함수가 있었지만 서비스가 사용하지
  않았고, 그 5-인자 계약에는 현재 필수인 `orders.restaurant_id`가 없었다.
- 새 함수의 기본 함수 ACL을 명시적으로 축소하지 않았다.
- 현재 HTTP 수용 테스트는 Supabase를 흉내 낸 메모리 테스트 더블을 사용한다.
  RPC가 오류를 반환할 때 NestJS가 500을 내고 가짜 목록에 주문을 노출하지 않는
  것은 검증하지만, 실제 PostgreSQL이 먼저 삽입한 주문 헤더를 롤백하는지는
  증명하지 못한다.

## 해결책

### HTTP와 서비스 경계

- 전역 `ValidationPipe`는 DTO에 없는 필드를 거절한다.
- 주문 DTO는 비어 있지 않은 `sessionId`, 1~100개 `items`, 각 항목의 문자열
  `menuItemId`와 1~999 정수 `quantity`, 선택 문자열 `paymentMethod`만 받는다.
- 사용자 ID는 요청 본문이 아니라 인증된 JWT에서 얻는다.
- 서비스가 `menu_items`를 조회해 모든 항목이 한 식당에 속하는지 확인하고,
  `restaurantId`, 주문 시점 단가 스냅샷, `totalPrice`를 계산한다.
- 클라이언트가 보낸 `restaurantId`, 항목 `price`, `totalPrice`는 계약에
  포함하지 않으며 정의되지 않은 필드로 거절한다.

### PostgreSQL 트랜잭션 경계

서비스는 다음 정확한 6-인자 함수 하나를 호출한다.

```text
public.create_order_with_items(
  uuid, uuid, uuid, integer, text, json
)
```

버전 마이그레이션은 알려진 obsolete 5-인자 함수를 제거하고, `restaurant_id`를
포함한 주문 헤더와 모든 주문 항목을 하나의 PL/pgSQL 함수 안에서 생성한다. 항목
INSERT 하나라도 예외를 발생시키면 함수 호출 전체가 실패하고 같은 트랜잭션의
주문 헤더도 롤백돼야 한다.

### RPC 실행 권한

게시 수용 기준은 다음과 같다.

- 함수 선언에 `SECURITY INVOKER`를 명시한다. 함수 소유자 권한으로 상승하는
  `SECURITY DEFINER`를 사용하지 않는다.
- `PUBLIC`, `anon`, `authenticated`에서 정확한 6-인자 시그니처의 `EXECUTE`를
  회수한다.
- NestJS 서버가 보관하는 `service_role`에만 애플리케이션 호출용 `EXECUTE`를
  부여한다. 함수 소유자와 DB 관리자의 관리 권한은 별도다.
- 마이그레이션을 반복 실행해도 넓은 기본 권한이 다시 남지 않아야 한다.

### 결제 상태 경계와 잔여 위험

RPC 트랜잭션은 `orders`와 `order_items` 생성까지만 보호하며 주문은 `PENDING`으로
생성한다.

- `SIMULATE`: 비운영이면서 `ALLOW_SIMULATED_PAYMENTS=true`일 때만 RPC가
  커밋된 뒤 별도 Supabase UPDATE로 `PAID`와 `payment_key`를 기록한다. 플래그가
  없거나 production이면 RPC 전에 거절한다.
- `TOSS`: 생성 단계에서는 `PENDING`을 유지하고 `/api/payments/confirm`에서
  승인 후 상태를 별도로 갱신한다.
- `CARD`/`CASH`: 정규화해 저장·응답하되, 외부 승인 또는 POS 수납 결과가
  명시적으로 기록될 때까지 `PENDING`을 유지한다.

따라서 결제 후 상태 UPDATE가 실패하는 경우는 이번 원자적 생성 트랜잭션의 보호
범위 밖이다. 주문 생성 경로는 저장·결제 분기·응답에 같은 정규화 결제 방식을
사용하고, 비운영 `SIMULATE` 상태 UPDATE 오류를 500으로 반환해 거짓 `PAID`
응답을 막는다. 다만 이 시점에는 이미 `PENDING` 주문이 생성됐으므로 안전한
재시도·중복 방지·복구가 필요하다. Toss confirm 경로의 외부 승인 성공 뒤 DB
UPDATE 실패도 별도 조정 경계다. 이 두 불일치를 탐지·재시도하는 idempotency와
reconciliation, 운영 절차는 후속 reliability 수직 기능 단위로 추적한다.

## 주요 파일

- `backend/src/orders/orders.controller.ts`
- `backend/src/orders/orders.service.ts`
- `backend/src/orders/orders.consistency.spec.ts`
- `backend/test/orders.postgres-spec.ts`
- `backend/test/support/disposable-postgres.ts`
- `backend/test/jest-postgres.json`
- `backend/scripts/migrations/2026-07-27-create-order-with-items-v2.sql`
- `backend/scripts/migrations/2026-07-29-schema-introspection-function-signatures.sql`
- `backend/src/app.module.ts`
- `backend/src/supabase/schema-healthcheck.service.ts`
- `backend/src/supabase/schema-healthcheck.service.spec.ts`
- `backend/package.json`
- `backend/package-lock.json`
- `docs/LUNCHSYNC_CODE_GUIDE.md`
- `docs/study/ORDER_CREATION_CONSISTENCY_REVIEW.md`

## 기술 선택과 대안

PostgreSQL이 트랜잭션 경계를 소유하도록 선택했다. 이미 사용하는
Supabase/PostgreSQL 스택 안에서 두 관계형 쓰기를 가장 작은 단위로 묶고, 프로세스
중단과 무관한 실제 롤백 의미를 제공하기 때문이다.

- 선택: 하나의 `SECURITY INVOKER` 데이터베이스 함수 + 축소된 함수 ACL.
- 제외: 항목 저장 실패 후 보상 DELETE. 프로세스 종료나 정리 실패 시 부분 주문이
  다시 남을 수 있다.
- 제외: NestJS에서 트랜잭션을 지원하는 PostgreSQL 클라이언트를 이 변경만을 위해
  추가. 새 연결 계층과 자격 증명 경로를 도입할 필요 없이 RPC로 해결할 수 있다.
- 후속 작업: 결제 승인과 주문 상태 갱신을 연결하는 사가·아웃박스·조정.
  주문 헤더·항목 생성 원자성과는 별도 실패 경계다.

## 검증

### NestJS 회귀 검사

```powershell
cd backend
cmd /c npm test -- --runInBand
cmd /c npm run test:postgres
cmd /c npm run build
```

현재 `orders.consistency.spec.ts`의 HTTP 수용 테스트는 다음만 증명한다.

1. 실제 NestJS 라우트로 `POST /api/orders`를 호출한다.
2. Supabase 테스트 더블의 RPC 오류를 500으로 변환한다.
3. 이어진 `GET /api/orders/today`에 테스트 더블의 부분 주문이 노출되지 않는다.

이 테스트 더블은 RPC 호출 전에 실제 주문 헤더를 PostgreSQL에 쓰지 않으므로
데이터베이스 트랜잭션 롤백의 증거가 아니다.

### 게시 전 PostgreSQL 계약 검사

`npm run test:postgres`는 일회용 `postgres:16-alpine` 컨테이너를 만들고 실제
PostgreSQL을 사용하는 별도 Jest 설정을 실행한다. Docker Engine이 실행 중이어야
하며, 테스트는 다음을 자동 검증한다.

1. 필요한 최소 스키마와 v2 마이그레이션을 실제 PostgreSQL에 적용한다.
2. service-role로 6-인자 RPC를 직접 호출하고 존재하지 않는 메뉴 FK를 항목
   INSERT에 전달해 실제 PostgreSQL 제약 실패를 유도한다.
3. 호출 실패 후 실제 PostgreSQL row count와 `GET /api/orders/today` 빈 목록을
   함께 확인해 주문 헤더·항목 롤백을 증명한다.
4. 알려진 구형 5-인자 함수가 제거되고 기대한 6-인자 함수가 존재하는지 확인한다.
5. 주문 함수가 고정 `search_path`의 `SECURITY INVOKER`이고 `PUBLIC`/`anon`/
   `authenticated` 실행 권한이 없으며 `service_role` 실제 호출만 성공하는지
   확인한다.
6. introspection 함수가 고정 `search_path`의 `SECURITY DEFINER`이며 동일한
   최소 ACL을 갖고, 매개변수 이름·타입과 JSON 반환 계약을 정확히 보고하는지
   확인한다.

테스트가 DB 미가동으로 건너뛰어졌거나, 마이그레이션을 적용하지 않았거나, 테스트
더블만 사용했다면 PostgreSQL 계약 검사를 통과한 것으로 기록하지 않는다.

2026-07-29 현재 체크포인트에서 실제 실행한 결과는 다음과 같다.

- 기본 Jest: 7개 스위트·47개 테스트 통과
- PostgreSQL 전용 Jest: 2개 스위트·5개 테스트 통과
- NestJS 빌드: 통과

PostgreSQL 전용 검사는 일회용 `postgres:16-alpine`에 v2 주문 마이그레이션과
2026-07-29 introspection 마이그레이션을 적용해 실제 롤백, 알려진 구형 overload
제거와 기대한 6-인자 함수 존재,
실제 역할별 함수 호출, 두 함수의 ACL·보안 모드·search path, 정확한 6-인자
PostgREST 계약 보고를 확인했다. 운영 데이터베이스 마이그레이션과 라이브 Toss
결제는 실행하지 않았다.

## 보안과 개인정보 검토

- 사용자 ID는 인증된 서버 요청에서만 가져온다.
- 식당 ID, 메뉴 단가, 합계는 서버가 DB 메뉴 레코드로부터 도출한다.
- Flutter는 `service_role` 키를 가지지 않고 Supabase에 직접 접근하지 않는다.
- RPC는 고정 `search_path`의 `SECURITY INVOKER`이며 API 역할 중
  `service_role`만 실행할 수 있다.
- `service_role` 실값은 승인된 비밀 관리자 또는 배포 플랫폼의 보호된 환경 변수로
  NestJS 런타임에만 주입하고 Git·문서·메신저에 복사하지 않는다.
- 오류 응답과 테스트 픽스처에 주문 내용, 자격 증명, 실제 결제 정보, 실제 고객
  레코드를 넣지 않는다.
- 주문 생성과 결제 상태 UPDATE 실패는 클라이언트에 고정된 일반 500 메시지만
  반환하고 내부 원인은 서버 로그에 남긴다. 다른 엔드포인트의 공통 오류 포맷은
  별도 보안 검토 범위다.

## 배포

1. 비운영 PostgreSQL 리허설 환경에
   `2026-07-27-create-order-with-items-v2.sql`을 먼저 적용한다.
2. 이어서
   `2026-07-29-schema-introspection-function-signatures.sql`을 적용한다.
3. 정확한 6-인자 시그니처, `SECURITY INVOKER`, 축소된 ACL과
   `check_schema_resources()` 응답을 검사한다.
4. 실제 PostgreSQL 정상 커밋·강제 실패 롤백 계약 테스트를 통과시킨다.
5. NestJS 전체 테스트와 운영 빌드를 통과시킨다.
6. 리허설 통과 후 승인된 운영자가 실제 백엔드 대상 DB에 두 마이그레이션을
   2026-07-27 → 2026-07-29 순서로 적용한다.
7. 같은 대상 DB에서 정확한 6-인자 시그니처, `SECURITY INVOKER`, 축소된 ACL과
   `check_schema_resources()` 응답을 다시 검사한다.
8. 대상 DB 검증이 끝난 뒤에만 6-인자 RPC를 호출하는 백엔드를 배포한다.
9. 명시적으로 허용한 비운영 `SIMULATE` 후속 UPDATE와 Toss·`CARD`·`CASH`의
   `PENDING` → 외부 승인/수납 흐름을 사람 손으로 확인한다.

백엔드를 두 마이그레이션보다 먼저 배포하면 PostgREST가 일치하는 함수
시그니처를 찾지 못해 주문 생성이 실패하거나 부트 헬스체크가 현재 RPC 계약을
정확히 판별하지 못할 수 있다.

실제 대상 DB 마이그레이션과 백엔드 배포는 승인된 운영자의 남은 작업이며, 이번
코드·문서 작성과 일회용 PostgreSQL 검증에서는 실행하지 않았다.

## 롤백

1. 새 주문 생성을 중지하거나 안전하게 차단한다.
2. 6-인자 RPC를 호출하는 백엔드를 먼저 이전 버전으로 되돌린다.
3. 실행 중인 호출자가 새 시그니처를 더 이상 사용하지 않는지 확인한다.
4. 검토된 유지보수 작업에서 이전 함수 계약과 최소 권한 ACL을 복원하고 6-인자
   함수를 제거한다.
5. 이미 생성된 실제 주문 데이터를 임의로 삭제하지 않는다. 데이터 변환 또는
   복구가 필요하면 별도 승인된 계획을 따른다.

새 백엔드가 호출 중인 6-인자 함수를 먼저 삭제해서는 안 된다. 롤백 SQL도 함수
권한을 다시 `PUBLIC`에 열지 않는지 별도 검토한다.

## AI 사용 범위

AI는 코드·SQL 검사, HTTP 수용 테스트와 실제 PostgreSQL 계약의 증거 수준 분리,
최소 RPC 통합 및 문서 작성에 사용됐다. 라이브 결제, 백엔드 배포, 운영 DB
마이그레이션은 수행하지 않았다.

## 사람의 검증 범위

- 비운영 Supabase/PostgreSQL에서 v2 마이그레이션의 반복 적용 가능성을 검토한다.
- 알려진 5-인자 함수가 제거되고 기대한 정확한 6-인자 함수가 해석되는지 확인한다.
- 함수의 `prosecdef = false`와 실행 ACL을 직접 확인한다.
- 강제 항목 제약조건 실패 뒤 주문 헤더가 남지 않는지 DB에서 직접 확인한다.
- 명시적으로 허용한 비운영 `SIMULATE` 주문의 `PENDING` → `PAID` 후속 업데이트와
  플래그 누락·production 거절을 확인한다.
- 정상 Toss 주문의 생성 `PENDING`과 승인 후 상태 변경을 확인한다.
- `CARD`/`CASH` 입력이 정규화되고 외부 승인 또는 POS 수납 결과가 기록되기
  전까지 `PENDING`을 유지하는지 확인한다.
- 상태 UPDATE 실패를 강제로 재현해 현재 reconciliation 공백을 별도 이슈로
  추적한다.
- 서버 로그에는 원인 진단 정보가 남되 클라이언트와 PR 산출물에 비밀 정보나 실제
  고객·결제 데이터가 포함되지 않는지 확인한다.

## 관련 문서

- [LunchSync 코드 가이드](../LUNCHSYNC_CODE_GUIDE.md)
- [LunchSync DTO](../LUNCHSYNC_DTO.md)
- [LunchSync 명세](../LUNCHSYNC_SPECIFICATION.md)
- [관측 가능성 PR 검토](OBSERVABILITY_PR_REVIEW.md)
- [v2 주문 생성 RPC 마이그레이션](../../backend/scripts/migrations/2026-07-27-create-order-with-items-v2.sql)
- [함수 시그니처 introspection 마이그레이션](../../backend/scripts/migrations/2026-07-29-schema-introspection-function-signatures.sql)
