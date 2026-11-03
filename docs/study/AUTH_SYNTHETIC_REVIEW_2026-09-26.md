# LunchSync 인증 장애 경계 검토 (2026-09-26)

카카오 DB 조회 실패를 신규 가입으로 오인하는 경로와 provider identity 검증 공백을 수정했다. token-info 앱 ID/양의 safe integer 사용자 ID/만료를 검사하고 user-me ID도 일치해야 한다. provider identity 확인 전 DB와 JWT를 사용하지 않는다. 두 요청 공유 timeout 기본5초/설정1~8초이며 DB 단계까지의 전체 deadline은 아니다. 401/403는 인증 실패, 공급자 장애·형식 오류는 retryable503으로 분리한다.

maybeSingle의 오류는 503으로 중단한다. 가입 unique23505는 같은 kakao_id로 다시 읽되 기존 권한·프로필·온보딩을 upsert하지 않는다. 기존 OWNER/PENDING 상태도 저장값을 유지한다. optional nickname/profile field 전체 스키마 검증이나 실제 provider 통신이 완성됐다는 의미는 아니다.

운영 KAKAO_APP_ID 필수·양의 safe decimal 검증을 추가했고 개발 .env에는 비밀값이 아닌 앱ID1534395를 설정했다. 운영 환경에도 별도 설정해야 한다. 전화번호 계정/충돌 조회 오류 역시 가입·계정 변경·JWT 전에 503으로 중단한다.

최종 Jest30 suites·216tests 및 Nest build 통과. 추가된 Kakao22·운영설정18·전화조회2 회귀가 포함된다. 일회용 PostgreSQL auth4/orders8/payments1=13tests 통과. PostgreSQL 검사는 합성 어댑터/공급자 입력을 사용하며 실결제·운영 Supabase 호출이 아니다. 테스트 container 생성 timeout8→30초는 Docker cold-start가 시험 한도를 넘기던 문제를 보강한다.

로그: D:\취업하자\테스트증거\2026-09-26_all-programs\lunchsync-backend-final.log. Flutter30·debug APK·카카오 취소 재현 수정은 KAKAO_LOGIN_REPRO_2026-09-26.md에 기록돼 있다. 실제 계정 로그인 완료·원격 backend 동일version·DBmigration·release서명은 미검증이며 운영 반영/푸시는 수행하지 않았다.

공식 identity API 근거: https://developers.kakao.com/docs/ko/kakaologin/rest-api
