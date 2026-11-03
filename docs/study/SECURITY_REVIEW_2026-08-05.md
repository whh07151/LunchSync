# LunchSync 보안 검토 — 2026-08-05

## 결론

정적 분석에서 확인한 계정 탈취, 매장 간 권한 상승, 세션 BOLA, 사용자 IDOR를
코드와 회귀 테스트로 차단했다. 운영 배포나 원격 Supabase 변경은 수행하지 않았다.

## 수정한 경계

- 휴대폰 인증의 대상 계정을 요청 본문 `existingUserId`가 아니라 인증된 JWT 주체로 고정했다.
- 이메일 OTP는 짧은 수명의 `EMAIL_VERIFICATION` 목적 토큰에 사용자 ID와 이메일을 묶고,
  일반 API JWT와 분리했다. 발송/검증에는 분당 제한을 적용했다.
- POS는 승인된 `OWNER`와 실제 매장 소유권을 매 요청 재검증한다. 운영 환경의 공용 PIN은
  닫혀 있으며 PIN 미설정도 실패로 처리한다.
- `owner_user_id`와 과거 `users.restaurant_id` 매핑을 로그인·조회·생성에서 같은 규칙으로
  해석해 레거시 점주가 두 번째 매장을 만들지 못하게 했다.
- 세션 상세, 구성원, 궁합, 추천, 투표, 초대 발급 전에 세션 구성원 여부를 확인한다.
- 알레르기와 단골 포인트 조회 대상은 쿼리 `userId`가 아니라 JWT 사용자로 고정했다.
- 운영 환경에서는 개발용 승격 경로가 설정값과 무관하게 닫힌다.
- 요청 로그에는 라우트 템플릿만 남기며 미매칭 URL은 `unmatched`로 기록한다.

## 데이터와 비밀정보

- 로컬 `supabase/` 스키마는 공개 스키마 테이블에 RLS를 켜고 anon/authenticated 권한을
  회수하며 service role만 허용하는 거부 우선 형태다. 다만 원격 프로젝트 적용 상태는
  이번 작업에서 확인하지 않았다. Supabase도 노출 스키마의 RLS와 명시적 권한 관리를
  권장한다: <https://supabase.com/docs/guides/database/postgres/row-level-security>
- `backend/.env`는 추적되지 않고 `.gitignore`에 포함된다. 키·인증서 형태의 추적 파일은
  정적 패턴 검사에서 발견되지 않았다.

## 의존성 감사

`npm audit --omit=dev`의 최초 결과는 19건(critical 1, high 8, moderate 9, low 1)이었다.
비파괴 범위의 잠금파일 업데이트 후 production 결과는 moderate 8, high/critical 0이다.
남은 항목은 `firebase-admin` 하위 Google Cloud/UUID 트리이며 자동 해결은 메이저 버전
변경을 요구한다. 별도 호환성 브랜치에서 `firebase-admin` 14 전환을 검증해야 한다.

## 검증

- `cmd /c npm test -- --runInBand`: 26 suites, 152 tests 통과
- `cmd /c npm run build`: 통과
- `cmd /c C:\flutter\bin\flutter.bat test --no-pub --reporter expanded`: 12 tests 통과
- 전체 `dart analyze --fatal-infos`: 문제 0건
- Docker Desktop Linux 엔진이 꺼져 있어 PostgreSQL 전용 계약 검사는 재실행하지
  못했으며 성공으로 간주하지 않는다.

## 운영 전 남은 조치

1. `firebase-admin` 14 호환성 테스트와 production 의존성 감사 0건 확인
2. 원격 Supabase migration/RLS/grant를 별도 승인 후 드라이런과 pgTAP으로 확인
3. 실제 PostgreSQL, Toss sandbox, 동시 취소 재조정 시나리오 검증
4. 결제 ledger/outbox, `REFUNDING` 상태와 재시작 가능한 reconciliation worker 구현
5. Firebase 웹 API 키의 허용 도메인/API 제한을 콘솔에서 확인
