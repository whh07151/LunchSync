# Supabase 빈 프로젝트 재구축 검토

작성일: 2026-07-29
대상 브랜치: `agent/reliability-observability`

## 문제

`lunchsync-dev` 원격 프로젝트는 `public` 테이블과 마이그레이션이 없는 빈
상태였다. 저장소의 `backend/scripts/migrations/`에는 기능별 증분 SQL은
있었지만 `users`, `restaurants`, `sessions`, `orders` 같은 핵심 테이블의
최초 생성 기준이 없었다. 따라서 기존 파일만 순서대로 실행해서는 새
Supabase 프로젝트를 동일한 상태로 만들 수 없었다.

원격 점검 결과는 다음과 같았다.

- `public` 애플리케이션 테이블 0개
- Supabase Auth 사용자 0명
- 적용된 마이그레이션 0개
- 보안·성능 Advisor 경고 0개
- Auth, Storage, Realtime 시스템 스키마는 정상

위 결과는 적용 전 기준선이다. 2026-07-30에 비운영 `lunchsync-dev`
프로젝트 참조값 `fbtmjgackdbgskukgmgd`를 다시 확인한 뒤 아래 기준선을
원격에 적용했다. 애플리케이션 행과 Auth 사용자는 추가하지 않았다.

## 재구축 기준

NestJS의 실제 `from(...)`, `rpc(...)`, 조회·삽입 필드와 기존 SQL을
대조해 다음 계약을 하나의 선언형 스키마로 정리했다.

- 애플리케이션 테이블 15개
- enum 타입 6개
- 백엔드 RPC 4개
- 주문·세션 `updated_at` 트리거
- 공개 읽기용 `order-photos` Storage 버킷
- FK 인덱스, 조회 패턴 인덱스, 값 범위 제약

새 빈 환경은 `supabase/schemas/lunchsync.sql`을 기준으로 생성한 초기
마이그레이션을 사용한다. 기존 증분 SQL은 과거 환경의 변경 이력으로 남겨
두며 새 기준과 함께 중복 적용하지 않는다.

## 주요 결정

### 백엔드 전용 Data API

Flutter 클라이언트는 Supabase에 직접 접속하지 않고 NestJS가
`service_role`로 접속한다. 이 경계를 DB 권한에도 반영했다.

- 모든 애플리케이션 테이블에 RLS 활성화
- `anon`, `authenticated` 테이블 권한 회수
- `service_role`에는 SELECT, INSERT, UPDATE, DELETE만 부여
- TRUNCATE와 TRIGGER 같은 소유자 수준 권한은 부여하지 않음
- 백엔드 RPC는 브라우저 역할의 실행 권한을 회수

### RPC 보안과 원자성

`create_session_with_host_member`, `delete_session_cascade`,
`create_order_with_items`, `check_schema_resources`는 모두
`SECURITY INVOKER`와 고정 `search_path`를 사용한다.

주문 RPC는 다음을 같은 트랜잭션에서 확인한다.

- 메뉴가 존재하고 주문 가능 상태인지
- 모든 메뉴가 요청 식당에 속하는지
- 요청 가격이 현재 메뉴 가격과 같은지
- 수량과 가격이 유효한지
- 주문 총액이 항목 합계와 같은지
- 주문 헤더와 항목이 모두 성공하거나 모두 롤백되는지

### 인증 모델

현재 앱은 Supabase Auth ID를 `public.users.id`와 연결하는 모델이 아니다.
이메일 OTP 발송에는 Supabase Auth를 사용하지만 앱 계정과 비밀번호 해시는
`public.users`에서 관리한다. 이번 재구축은 기존 앱 계약을 보존했으며,
인증 모델 통합은 별도 보안 설계 작업으로 분리했다.

### Storage

POS 조리 완료 사진 코드와 동일하게 `order-photos` 버킷을 사용한다.
공개 URL이 필요한 기능이라 공개 읽기를 허용하되 업로드는 백엔드
`service_role`로만 수행한다. 허용 형식은 JPEG, PNG, WebP이고 크기는
백엔드와 동일한 5 MiB다.

public 버킷의 객체 URL 다운로드에는 `storage.objects` SELECT 정책이
필요하지 않다. 초기 정책은 파일 목록 조회까지 허용한다는 Security Advisor
경고를 만들었으므로 별도 마이그레이션으로 제거했다. 공개 URL 다운로드는
유지하고 브라우저 역할의 버킷 전체 목록 조회는 허용하지 않는다.

## 원격 적용 결과

- 원격 마이그레이션 4개 적용
- 애플리케이션 테이블 15개와 enum 6개 생성
- 모든 애플리케이션 테이블 RLS 활성화, 애플리케이션 행 0개 유지
- RPC 4개 `SECURITY INVOKER`, 고정 `search_path`, `service_role` 전용 실행
- `anon`, `authenticated` 애플리케이션 테이블 CRUD 권한 0개
- `order-photos` public 버킷, 5 MiB, JPEG·PNG·WebP 제한 적용
- Security·Performance Advisor의 WARN·ERROR 0건
- REST/Auth 상태 확인과 백엔드 `.env`의 실제 헬스체크 RPC 호출 성공

초기 스키마를 MCP에 전달할 때 `check_function_bodies = false` 때문에
헬스체크 함수 본문의 전사 오류가 생성 시점에는 검출되지 않았다. 첫 실제
RPC 호출에서 오류를 확인했고 `repair_schema_healthcheck_contract`
마이그레이션으로 선언형 원본과 맞췄다. 교정 이력을 로컬에도 보존해 빈 DB
재적용과 원격 이력이 같은 순서를 갖는다.

## 검증

로컬 Docker Supabase PostgreSQL 17에서 다음을 확인했다.

- 빈 DB 전체 초기화와 마이그레이션 재적용 성공
- 빈 `seed.sql` 적용 성공
- pgTAP 계약 테스트 20개 통과
- 선언형 스키마와 마이그레이션 diff 없음
- NestJS Jest 테스트 47개 통과
- 별도 PostgreSQL 주문 통합 테스트 4개 통과
- NestJS 빌드 통과
- DB, Auth, Storage, REST, Realtime, Studio 핵심 컨테이너 정상

첫 DB 테스트에서 마지막 삭제 검증 하나가 실패했다. 원인은 한 SQL
표현식 안에서 부작용 함수 실행과 삭제 후 카운트를 동시에 평가해 SQL
평가 순서에 의존한 테스트였다. 함수 호출과 결과 카운트를 두 assertion으로
분리한 뒤 전체 20개가 통과했다. 제품 스키마 결함은 아니었다.

## 남은 경계

이번 작업은 새 비운영 개발 프로젝트의 빈 기준선 적용까지만 완료했다.
다음은 수행하지 않았다.

- 운영·개발 원격 데이터 삭제
- 실제 사용자 데이터 이관
- 운영 환경 변수 작성
- 운영 배포
- 실제 사용자·결제·사진을 사용하는 앱 스모크 테스트

후속 변경도 로컬 마이그레이션 검토·reset·계약 테스트·diff와 원격
Advisor·로그 검증을 포함해야 한다.
