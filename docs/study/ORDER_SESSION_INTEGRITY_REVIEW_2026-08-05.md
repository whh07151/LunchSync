# 주문 세션 무결성 검토

날짜: 2026-08-05
브랜치: `agent/reliability-observability`

## 해결한 문제

인증된 사용자는 기존 `POST /api/orders`에 임의의 `sessionId`를 넣을 수 있었다.
서비스와 주문 RPC는 다음 세 가지를 강제하지 않았다.

- 사용자가 해당 세션의 `session_members` 행을 갖는지
- 세션이 `ORDERED`이고 우승 식당이 확정됐는지
- 주문 식당과 모든 메뉴의 식당이 세션 우승 식당과 같은지

NestJS가 `service_role`로 RPC를 호출하므로 RLS만으로 이 경계를 대신할 수 없다.
서비스 사전 점검만 추가하면 점검과 INSERT 사이에 세션 상태나 멤버십이 바뀌는
TOCTOU 경쟁도 남는다.

## 사용자 영향

- 비회원은 세션 존재 여부를 추측할 수 없도록 `404 ORDER_SESSION_NOT_FOUND`를 받는다.
- 투표가 끝나지 않았거나 우승 식당이 없으면 `409 ORDER_SESSION_NOT_READY`를 받는다.
- 우승 식당 이외의 메뉴는 `409 ORDER_SESSION_RESTAURANT_MISMATCH`로 거절된다.
- 정상 `CASH` 주문은 외부 수납 확인 전까지 `PENDING`으로 저장된다.
- 주문 헤더나 품목 중 하나라도 실패하면 둘 다 남지 않는다.

## 구현 경계

### NestJS 사전 점검

`OrdersService.createOrder()`는 JWT의 사용자 ID로 멤버십을 먼저 확인하고, 그 다음
세션 상태와 우승 식당을 조회한다. 비회원과 없는 세션은 같은 404 응답으로 축약한다.
조회 장애는 안정적인 503 코드와 `retryable: true`로 반환하고 원본 DB 메시지는
클라이언트나 로그에 남기지 않는다.

메뉴 가격과 식당은 서버가 다시 조회해 계산한다. 클라이언트는 사용자 ID, 식당 ID,
가격 또는 합계를 확정할 수 없다.

### PostgreSQL 원자 경계

`public.create_order_with_items(uuid, uuid, uuid, integer, text, json)`는 한 트랜잭션에서
다음 순서로 잠그고 검증한다.

1. `sessions` 행을 `FOR SHARE`로 잠근다.
2. 해당 `session_members` 행을 `FOR KEY SHARE`로 잠근다.
3. 요청된 `menu_items`를 UUID 정렬 순서로 `FOR SHARE` 잠근다.
4. 멤버십, `ORDERED` 상태, 우승 식당, 메뉴 식당, 가격과 합계를 검증한다.
5. `orders`와 `order_items`를 함께 INSERT한다.

세션을 먼저 잠그는 순서는 `delete_session_cascade()`의 순서와 같아 교착 가능성을
줄인다. 함수 안의 검증은 서비스 사전 점검 이후 멤버 탈퇴, 상태 변경, 우승 식당 변경,
메뉴 변경이 동시에 일어나도 생성 시점의 계약을 보존한다.

### 마이그레이션과 선언형 스키마

- `supabase/schemas/lunchsync.sql`은 새 기준 함수 정의를 가진다.
- `20260805113000_enforce_order_session_integrity.sql`은 이미 기준 마이그레이션이
  기록된 DB에서 구형 5인자 overload를 제거하고 같은 정의를 적용한다.
- `20260805113100_ensure_order_photos_bucket.sql`은 Storage API 기동 시점에 의존하지
  않고 `order-photos` bucket 계약을 idempotent하게 만든다.
- 함수는 `SECURITY INVOKER`, 고정 `search_path = pg_catalog, pg_temp`를 사용한다.
- 실행 권한은 `PUBLIC`, `anon`, `authenticated`에서 회수하고 `service_role`에만 둔다.

## 오류 계약

| 조건 | HTTP | 공개 코드 |
| --- | ---: | --- |
| UUID가 아닌 `sessionId` | 400 | DTO validation error |
| 세션 없음 또는 비회원 | 404 | `ORDER_SESSION_NOT_FOUND` |
| 멤버십 조회 장애 | 503 | `ORDER_SESSION_MEMBERSHIP_LOOKUP_FAILED` |
| 세션 조회 장애 | 503 | `ORDER_SESSION_LOOKUP_FAILED` |
| 주문 가능 상태 아님 | 409 | `ORDER_SESSION_NOT_READY` |
| 우승 식당 불일치 | 409 | `ORDER_SESSION_RESTAURANT_MISMATCH` |
| 알 수 없는 RPC 실패 | 500 | 일반 주문 생성 실패 메시지 |

RPC는 경쟁 상황에서 같은 marker를 반환하고 서비스가 이를 위 표의 HTTP 계약으로
매핑한다. 원본 PostgreSQL 오류는 공개 응답에 포함하지 않는다.

## 주요 파일

- `backend/src/orders/orders.service.ts`
- `backend/src/orders/orders.consistency.spec.ts`
- `backend/test/orders.postgres-spec.ts`
- `backend/test/payments.postgres-spec.ts`
- `backend/test/support/disposable-postgres.ts`
- `backend/scripts/migrations/2026-07-27-create-order-with-items-v2.sql`
- `supabase/schemas/lunchsync.sql`
- `supabase/migrations/20260805113000_enforce_order_session_integrity.sql`
- `supabase/migrations/20260805113100_ensure_order_photos_bucket.sql`
- `supabase/tests/database/lunchsync_schema.test.sql`

## 검증 결과

2026-08-05 로컬에서 다음을 실행했다.

```powershell
cd backend
cmd /c npm test -- --runInBand
cmd /c npm run test:postgres
cmd /c npm run build

cd ..
cmd /c npx --yes supabase@2.109.1 db reset --local
cmd /c npx --yes supabase@2.109.1 test db --local supabase/tests/database/lunchsync_schema.test.sql
cmd /c npx --yes supabase@2.109.1 db diff --local
```

- NestJS: 27 suites, 164 tests 통과
- PostgreSQL 수락: 2 suites, 9 tests 통과
- NestJS build: 통과
- Supabase 빈 DB reset: 프롬프트 없이 통과
- pgTAP: 25/25 통과
- declarative schema diff: `No schema changes found`

PostgreSQL 수락 테스트는 비회원, 주문 전 세션, 우승 식당 불일치, 품목 식당 불일치,
실제 INSERT 실패 롤백, 정상 현금 주문과 결제 조정 복구를 실제 일회용 DB에서 확인한다.
pgTAP은 같은 음성 경로와 구형 overload 부재를 선언형 Supabase 경계에서 다시 확인한다.

## 보안·개인정보 검토

- 사용자 ID는 요청 본문이 아니라 검증된 JWT에서 가져온다.
- 비회원 응답은 세션 존재 여부를 숨긴다.
- `service_role` 키, 결제 키, 실제 사용자·주문 데이터는 테스트와 문서에 넣지 않았다.
- 원격 DB 마이그레이션, 실제 결제, 운영 배포는 수행하지 않았다.

## 롤백

운영 적용 전에는 백엔드와 두 증분 마이그레이션 파일을 함께 되돌린다. 이미 적용한
환경에서는 마이그레이션 이력을 삭제하거나 수정하지 않고, 검토된 후속 마이그레이션으로
이전 함수 정의를 복원한다. 먼저 주문 생성 엔드포인트를 중지하고 현재 6인자 함수의
호출이 없는지 확인한 뒤 백엔드를 되돌린다.

## AI 사용 범위와 사람의 검증 범위

AI는 실행 경로 조사, 서비스·SQL·테스트·문서 수정, 로컬 Docker/Supabase 검증을
수행했다. 사람은 원격 환경에 적용하기 전 실제 마이그레이션 대상과 백업, 앱의
404/409 사용자 안내, 운영 모니터링과 롤백 순서를 최종 승인해야 한다.

현재 Flutter 주문 API는 비정상 응답을 일반 실패 안내로 축약한다. 보안 계약에는
문제가 없지만, 사용자가 “투표가 아직 끝나지 않음”과 “다른 식당 메뉴”를 구분하도록
하려면 후속 UI 작업에서 공개 오류 코드별 안내를 연결해야 한다.
