# LunchSync 로컬 Supabase

이 디렉터리는 빈 Supabase 프로젝트에서 LunchSync 개발 DB를 재현하기
위한 기준 정보다. 실제 사용자 데이터나 운영 비밀 정보는 포함하지 않는다.
2026-07-30에 비운영 원격 `lunchsync-dev`
(`fbtmjgackdbgskukgmgd`)에 이 기준선을 적용했다. 애플리케이션 데이터는
넣지 않았다.

## 구성

- `config.toml`: PostgreSQL 17, 로컬 포트, Auth, Storage 서비스 설정
- `schemas/lunchsync.sql`: 선언형 데이터베이스 기준 스키마
- `migrations/`: 빈 DB 초기화, 권한 보강, 원격 적용 중 발견한 헬스체크
  교정과 Storage 목록 노출 제한 이력
- `seed.sql`: 의도적으로 비어 있는 개발 시드
- `tests/database/lunchsync_schema.test.sql`: 스키마·권한·RPC 계약 테스트

기존 `backend/scripts/migrations/`는 과거 환경을 보정하던 증분 SQL이다.
새 빈 프로젝트는 그 파일들을 순서대로 실행하지 않고 이 디렉터리의
마이그레이션만 사용한다.

## 로컬 실행

Docker Desktop이 실행 중인 상태에서 저장소 루트에서 다음을 실행한다.

```powershell
npx --yes supabase@2.109.1 start
npx --yes supabase@2.109.1 db reset --local
npx --yes supabase@2.109.1 test db --local supabase/tests/database/lunchsync_schema.test.sql
npx --yes supabase@2.109.1 db diff --local
```

정상 기준은 DB 테스트 전체 통과와 `No schema changes found`다.

사용을 마치면 기본 개발 키로 열린 로컬 서비스를 계속 노출하지 않도록
중지한다.

```powershell
npx --yes supabase@2.109.1 stop
```

로컬 접속값이 필요하면 다음 명령으로 현재 값을 확인하되 출력 내용을
문서, 이슈, 커밋 또는 채팅에 복사하지 않는다.

```powershell
npx --yes supabase@2.109.1 status
```

NestJS는 `SUPABASE_URL`과 `SUPABASE_SERVICE_ROLE_KEY`를 요구한다. 개발
접속값은 커밋하지 않는 로컬 환경 변수로만 주입한다.

## 보안 경계

- 모든 `public` 애플리케이션 테이블에 RLS가 켜져 있다.
- `anon`과 `authenticated`는 애플리케이션 테이블을 직접 읽거나 쓸 수 없다.
- NestJS의 `service_role`만 필요한 CRUD와 네 개 RPC 실행 권한을 갖는다.
- RPC는 모두 `SECURITY INVOKER`이며 고정된 `search_path`를 사용한다.
- `order-photos`는 공개 읽기 버킷이며 JPEG, PNG, WebP와 5 MiB 한도를 사용한다.
- public 버킷 URL 다운로드는 유지하되 `storage.objects`의 광범위한 SELECT
  정책은 두지 않아 클라이언트의 버킷 전체 목록 조회를 허용하지 않는다.
- 로컬 Analytics는 앱 기능에 필요하지 않고 Windows Docker의 로그 소켓
  접근 오류를 피하기 위해 꺼져 있다.

Supabase CLI의 로컬 포트는 기본적으로 네트워크 인터페이스에 바인딩될 수
있다. 신뢰할 수 없는 네트워크에서는 실행하지 말고, 사용 후 스택을
중지한다.

## 원격 기준선

2026-09-25 MCP 읽기 점검에서 원격에는 다음 네 마이그레이션만 순서대로 기록돼 있었다.

- `20260729161550_initial_lunchsync_schema`
- `20260729161642_harden_data_api_and_storage`
- `20260729161703_repair_schema_healthcheck_contract`
- `20260729161955_restrict_order_photos_listing`

로컬에는 다음 두 파일이 추가로 있지만 **원격 적용 이력에는 없다**. 원격 함수가 수동으로 수정됐는지는 현재 읽기 권한으로 확인하지 못했다.

- `20260805113000_enforce_order_session_integrity`
- `20260805113100_ensure_order_photos_bucket`

MCP가 부여한 앞의 네 버전과 로컬 파일명을 맞췄다. 이후 원격 스키마 변경은
`supabase/migrations/`에 새 파일을 먼저 만들고 로컬 reset·pgTAP·diff를
통과시킨 뒤 적용한다. 기존 프로젝트 초기화, 데이터 삭제, 운영 배포는
별도 명시적 승인 없이는 수행하지 않는다.
