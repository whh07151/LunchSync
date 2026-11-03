# LunchSync 관측 가능성 PR 검토

날짜: 2026-07-26
브랜치: `agent/reliability-observability`
초안 PR: https://github.com/whh07151/LunchSync/pull/15

## 해결하려는 문제

LunchSync에는 핵심 점심 주문 흐름이 이미 있었지만 인시던트 진단은 임시 콘솔 출력과 수동 재현에 의존했다.
모바일 결제, 투표, POS 요청이 실패했을 때 사용자 제보와 백엔드 동작을 연결할 안정된 요청 식별자나 런타임 스냅샷이 없었다.

## 사용자 영향

PR은 실패를 더 빠르게 설명할 수 있는 작은 신뢰성 계층을 추가한다.

- 모든 HTTP 응답에 `x-request-id`를 부여한다.
- 백엔드 로그에 메서드, 경로, 상태 코드, 소요 시간, 요청 ID를 넣는다.
- 런타임 엔드포인트가 환경 변수나 비밀 정보를 노출하지 않고 프로세스 상태를 보고한다.

## 구현 지도

- `backend/src/observability/request-logging.middleware.ts`
  - 들어온 `x-request-id`를 사용하거나 UUID를 생성한다.
  - 응답이 끝난 뒤 구조화된 JSON 로그를 기록한다.
  - 상태 등급별 로그 수준 사용: 2xx/3xx 일반, 4xx 경고, 5xx 오류.
- `backend/src/observability/observability.service.ts`
  - 가동 시간, Node 버전, 메모리, 이벤트 루프 사용률로 대략적인 런타임 스냅샷을 만든다.
  - 데이터베이스 인증 정보, 헤더, 요청 본문, 사용자 데이터를 제외한다.
- `backend/src/observability/observability.controller.ts`
  - `GET /api/observability/runtime`을 노출한다.
  - 상태 폴링이 사용자용 API 할당량을 소모하지 않도록 속도 제한을 건너뛴다.
- `backend/src/app.module.ts`
  - `ObservabilityModule`을 등록한다.
  - 모든 라우트에 `RequestLoggingMiddleware`를 적용한다.

## 기술 선택

이 PR은 전체 텔레메트리 스택을 추가하지 않고 NestJS 기본 요소 안에 머문다.
현재 공백은 장기 메트릭 저장이 아니라 요청 연계와 런타임 가시성이므로 이 저장소에 올바른 첫 단계이다.
요청 형태와 상태 계약이 안정된 뒤 OpenTelemetry, Prometheus, 로그 전송을 추가할 수 있다.

## 검증

이 브랜치에서 이전에 실행:

```powershell
cmd /c npm test -- --runInBand
cmd /c npm run build
```

집중 테스트 파일:

- `backend/src/observability/request-logging.middleware.spec.ts`
- `backend/src/observability/observability.service.spec.ts`

## 보안과 개인정보 검토

- 비밀 정보를 기록하지 않는다.
- 요청 본문, 권한 헤더, 쿠키, 사용자 프로필 필드를 기록하지 않는다.
- 런타임 출력은 의도적으로 대략적인 프로세스 수준 정보만 제공한다.
- 이 엔드포인트를 신뢰 환경 밖에 노출하려면 내부 인증 또는 인프라 수준 허용 목록 뒤에 두는 것이 다음 강화 단계이다.

## 롤백

`backend/src/app.module.ts`의 관측 가능성 모듈 등록을 되돌리고 `backend/src/observability/` 폴더를 제거한다.
변경이 격리돼 있어 업무 데이터베이스 스키마나 결제 동작을 바꾸지 않는다.

## 면접 노트

가장 강한 설명은 운영 관점이다.

> 가장 작지만 유용한 관측 가능성 계층인 요청 연계와 런타임 상태를 먼저 추가했습니다. 프로젝트를 너무 일찍 큰 모니터링 플랫폼에 묶지 않으면서 유지보수자가 결제, 투표, POS 실패를 디버그할 충분한 근거를 제공합니다.

논의할 후속 주제:

- 인시던트 분류 중 요청 ID가 원시 로그보다 유용한 이유.
- 응답 종료 시점 로깅이 최종 상태 코드를 정확히 포착하는 이유.
- 엔드포인트를 Prometheus 메트릭이나 OpenTelemetry 트레이스로 발전시키는 방법.
- 로그에서 민감한 필드를 의도적으로 제외한 이유.
