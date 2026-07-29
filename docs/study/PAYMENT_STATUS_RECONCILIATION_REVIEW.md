# 결제 상태 대사와 복구 경계 검토

날짜: 2026-07-29

브랜치: `agent/reliability-observability`

범위: 합성 데이터와 Toss 테스트 모드

## 해결하려는 문제

결제 승인과 주문 DB 갱신은 하나의 원자적 트랜잭션이 아니다. Toss 승인이 성공한 직후 `orders.status = PAID` 갱신이 실패하면 외부 결제는 완료됐지만 로컬 주문은 `PENDING`으로 남을 수 있다.

기존 구현은 이 DB 오류를 로그만 남기고 `PAID` 성공 응답을 반환했다. 사용자는 결제가 완료됐다고 보지만 점주 화면에서는 주문이 나타나지 않는 모순이 생기며, 같은 요청을 재시도하면 Toss 승인을 중복 호출하는지 알 수 없었다.

## 선택한 최소 경계

새 메시지 브로커나 별도 대사 테이블을 추가하지 않고 기존 `orders.status`와 `orders.payment_key`를 복구 기준으로 사용한다.

1. 서버는 주문 소유자, 주문 금액, 현재 상태와 저장된 `payment_key`를 확인한다.
2. Toss 승인 POST에 UUID 주문 ID로 만든 주문 단위 `Idempotency-Key`를 전달한다. 같은 주문의 서로 다른 paymentKey 요청도 Toss에서는 하나의 승인 연산으로 취급한다.
3. 승인 성공 후 DB 갱신은 `id = 요청 주문`과 `status = PENDING`을 모두 만족하는 한 행만 `PAID`로 바꾼다.
4. 갱신 오류 또는 0행이면 주문을 다시 읽는다.
5. 다른 요청이 같은 paymentKey로 이미 `PAID`를 저장했다면 대사 완료로 인정한다.
6. 여전히 `PENDING`이면 성공을 가장하지 않고 재시도 가능한 503을 반환한다.
7. 이미 `PAID`인 주문은 저장된 키와 요청 키가 정확히 같을 때만 멱등 성공으로 처리한다. 다른 키나 저장 키가 없는 과거 주문은 자동 추정하지 않고 409로 차단한다.
8. `PAID`도 `PENDING`도 아닌 주문은 Toss 호출 전에 `ORDER_NOT_PAYABLE`로 차단한다.

Toss 공식 문서는 같은 멱등키의 반복 POST가 최초 응답을 다시 반환한다고 설명한다. 멱등키는 최대 300자이며 15일 동안 유효하다. 현재 키는 충분히 무작위적인 UUID 주문 ID를 사용하므로 이 길이 제한 안에 있다.

- 공식 헤더 문서: <https://docs.tosspayments.com/reference/using-api/authorization>
- 결제 승인·조회 문서: <https://docs.tosspayments.com/reference>

## 공개 결과

### 대사 필요

HTTP `503`

```json
{
  "code": "PAYMENT_APPROVED_DB_SYNC_PENDING",
  "retryable": true,
  "orderId": "<order uuid>",
  "paymentKey": "<same client-supplied test payment key>"
}
```

의미: Toss 승인 응답은 성공했지만 DB의 `PAID` 상태를 확인하지 못했다. 같은 `orderId`, `paymentKey`, `amount`로 재시도해야 한다. 서버 로그에는 주문 상태 갱신 실패 원인이 남는다.

### 대사 완료

HTTP `201`

- 첫 DB 갱신이 성공하면 `alreadyPaid: false`, `status: PAID`
- 동시 요청이 먼저 같은 키를 저장했거나 같은 키로 다시 호출하면 `alreadyPaid: true`, `reconciled: true`, `status: PAID`

### 결제 키 충돌

HTTP `409`

```json
{
  "code": "PAYMENT_KEY_MISMATCH",
  "retryable": false,
  "orderId": "<order uuid>"
}
```

의미: 주문은 이미 `PAID`지만 저장된 paymentKey가 요청과 다르다. 자동 덮어쓰기나 Toss 재호출을 하지 않고 테스트 결제 내역과 서버 로그를 사람이 확인해야 한다.

### 결제 불가 주문 상태

HTTP `409`, 코드 `ORDER_NOT_PAYABLE`, `retryable: false`

의미: 취소됐거나 이미 후속 처리 단계로 이동한 주문이다. Toss를 호출하지 않으며 주문 상태를 먼저 사람이 확인해야 한다.

### Toss 성공 응답 불일치

HTTP `502`, 코드 `TOSS_PAYMENT_MISMATCH`, `retryable: false`

의미: 성공 응답의 `paymentKey`, `orderId`, `totalAmount`, `status`가 요청과 일치하지 않는다. 로컬 주문을 `PAID`로 바꾸지 않으며, 전체 공급자 응답 대신 불일치한 필드 여부만 서버 로그에 남긴다.

### Toss 멱등 요청 처리 중

HTTP `409`, 코드 `IDEMPOTENT_REQUEST_PROCESSING`, `retryable: true`

의미: 같은 주문 단위 멱등 요청이 Toss에서 아직 처리 중이다. 일반 400 오류로 평탄화하지 않고 같은 주문·paymentKey·금액으로 잠시 후 다시 시도하도록 명시한다.

### Toss 일시 장애

- Toss가 HTTP 5xx를 반환하면 HTTP `503`, 코드 `TOSS_SERVICE_UNAVAILABLE`,
  `retryable: true`로 전달한다.
- Toss 응답을 받지 못한 네트워크 오류는 HTTP `503`, 코드
  `TOSS_COMMUNICATION_FAILED`, `retryable: true`로 전달한다.
- 요청은 기본 10초(`TOSS_API_TIMEOUT_MS`, 100~60000ms) 안에 응답이 없으면
  중단하며, 비JSON 5xx 응답도 `TOSS_SERVICE_UNAVAILABLE`로 분류한다.
- 두 경우 모두 서버 로그에는 주문 ID, 상태 코드, 오류 코드만 남기며 응답 본문,
  인증 헤더, 시크릿 키는 기록하지 않는다.

## TDD 증거

HTTP 수용 테스트에서 다음 RED를 순서대로 재현했다.

1. Toss 승인 후 DB 오류를 성공으로 반환함
2. 같은 요청 재시도의 Toss 멱등키가 없음
3. 조건부 DB 갱신이 0행이어도 성공으로 보일 수 있음
4. 동시 요청이 같은 키로 이미 대사를 끝냈는데 503으로 오판함
5. 이미 결제된 주문에 다른 paymentKey를 보내도 성공함
6. `CANCELLED` 주문도 Toss 승인 API를 호출함
7. Toss 성공 응답의 paymentKey가 달라도 로컬 DB 갱신을 시도함
8. 같은 주문의 서로 다른 paymentKey가 서로 다른 멱등키를 사용해 중복 승인될 수 있음
9. Toss `IDEMPOTENT_REQUEST_PROCESSING`을 일반 400 오류로 평탄화함

`payments.consistency.spec.ts`는 외부 Toss와 DB를 시스템 경계에서만 합성 구현으로 바꾸고 실제 HTTP 엔드포인트를 호출한다.

`payments.postgres-spec.ts`는 disposable PostgreSQL에서 다음 전체 흐름을 검증한다.

- 첫 승인 응답 뒤 합성 DB 쓰기 오류 → HTTP 503, 실제 행은 `PENDING`
- 같은 멱등키 재시도 → 실제 조건부 UPDATE 한 행, `PAID`와 paymentKey 저장
- 세 번째 같은 요청 → Toss 미호출, 이미 대사된 성공

검증 명령:

```powershell
cmd /c npm test -- --runInBand
cmd /c npm run test:postgres
cmd /c npm run build
```

최종 로컬 결과:

- 기본 Jest: 7개 스위트, 47개 테스트 통과
- disposable PostgreSQL: 2개 스위트, 5개 테스트 통과
- Nest 빌드: 성공

## 스키마 결정

이 수직 기능 단위에는 새 마이그레이션이 필요하지 않다.

- `orders.status`가 로컬 결제 상태를 보유한다.
- `orders.payment_key`가 같은 결제의 멱등 재시도인지 다른 결제의 충돌인지 구분한다.
- `PENDING → PAID` 조건부 UPDATE가 동시 요청의 덮어쓰기를 막는다.

미해결 대사 건을 여러 주문에 걸쳐 검색하고 운영자가 일괄 처리해야 한다는 측정된 요구가 생기면, 그때 별도 대사 이벤트/시도 테이블과 운영 조회 API를 검토한다. 현재 한 건의 즉시 재시도 경계만을 위해 Kafka, Redis 또는 새 유료 인프라를 추가하지 않는다.

## 보안·개인정보

- 주문 소유자와 금액 검증을 Toss 호출 전에 유지한다.
- 저장된 paymentKey가 다른 `PAID` 주문은 자동으로 덮어쓰지 않는다.
- 테스트는 `test_sk_` 형태의 합성 문자열과 합성 UUID만 사용한다.
- 실제 Toss, 운영 DB, 라이브 키, 실제 카드, 실제 결제를 호출하지 않았다.
- 503의 paymentKey는 인증된 주문 소유자가 같은 요청에서 제출한 값이다. 서버 로그에는 전체 Toss 시크릿이나 인증 헤더를 남기지 않는다.

## 롤백

애플리케이션 변경만 이전 구현으로 되돌릴 수 있으며 DB 마이그레이션 롤백은 없다. 다만 이전 구현은 DB 저장 실패를 성공으로 가장하므로, 롤백 시에는 결제 승인 후 주문 상태 불일치 위험이 다시 열린다는 점을 명시해야 한다.

## 남은 위험과 사람 검증

- 멱등키 유효 기간 15일을 넘긴 미해결 건은 자동 재시도하지 말고 Toss 테스트 결제 조회로 확인해야 한다.
- 주문 단위 멱등키의 최초 승인 요청이 실패하면 같은 주문 ID의 후속 요청도 15일 동안 최초 오류를 받을 수 있다. 자동으로 다른 paymentKey를 승인하지 말고 기존 주문을 취소한 뒤 새 주문 ID로 다시 시작해야 한다.
- 현재 즉시 복구 경계는 영속적인 대사 작업 큐가 아니다. 프로세스가 재시작돼도 클라이언트가 동일 세 필드를 보존해야 재시도할 수 있다.
- PostgreSQL 수용 테스트는 실제 행의 `PENDING → PAID` 조건부 갱신과 저장 결과를 검증하지만, 첫 쓰기 장애는 SQL 실행 전 합성하며 Supabase/PostgREST 캐시·RLS 동작까지 재현하지 않는다. 이 부분은 비운영 Supabase에서 사람이 별도로 확인해야 한다.
- 네트워크 타임아웃으로 Toss 승인 응답 자체를 받지 못한 경우는 이번 “승인 응답 성공 후 DB 실패” 범위와 다르다. paymentKey 조회 또는 웹훅 기반 복구는 후속 기능이다.
- 배포 전 사람은 Toss 테스트 키로 같은 멱등키 재시도 응답, 테스트 결제 조회 결과, DB `payment_key` 일치를 비운영 환경에서 확인해야 한다.
