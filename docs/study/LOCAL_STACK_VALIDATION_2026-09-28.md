# 로컬 독립 실행 검증

AWS·DuckDNS·운영 Supabase 없이 합성 데이터로 실행한다. `scripts/prepare-local.ps1 -Start`는 독립 `lunchsync-local` Docker 프로젝트와 저장소의 여섯 마이그레이션을 사용한다. 원격 link/push/reset은 호출하지 않는다. Supabase CLI가 이 PC에서 포트를 전체 인터페이스에 공개해 `scripts/bind-local-containers.cjs`가 네 개의 프로젝트 소유 컨테이너 공개 포트를 `127.0.0.1`에 묶는다. 주문 행 수를 재생성 전후 비교하고 named volume은 보존한다. Docker Desktop 재시작 후에도 포트와 주문 2건 보존을 확인했다.

`scripts/local-backend.ps1`은 매번 Nest를 빌드하고, 기존 `backend/.env`를 읽지 않으며, 상속된 Firebase/Gemini/결제 키를 지운 뒤 루프백 Supabase와 `.local/jwt-secret.local`만 사용한다. Flutter 웹은 debug 빌드 후 `node scripts/local-web.cjs`로 `127.0.0.1:8080`에 연다. Android 에뮬레이터 기본 백엔드는 `10.0.2.2:3000/api`, 웹은 `localhost:3000/api`다. Release 빌드는 명시적 HTTPS `BACKEND_URL`이 없으면 거부한다.

실제 로컬 REST 검증: 가입→제한 JWT→SMTP OTP→검증→정상 로그인, 사용자 A/B 세션·초대·투표·승자 결정, A의 9,000원 모의 결제/DB 저장, 외부 사용자 C의 주문 조회 거절까지 32개 HTTP 검사 통과. 재부팅 후 다시 32개 검사 통과. 브라우저에서도 합성 A 로그인 후 홈의 로컬 가상 한식당과 주문현황의 결제 완료 주문 표시 확인. 스크린샷 `D:\취업하자\테스트증거\2026-09-27_local\lunchsync-browser-login.png`, `lunchsync-order-status.png`. backend Jest 30 suites/222 tests, Flutter 전체 32 tests 및 변경 구성 테스트 2 tests, Dart analyze 통과.

2026-09-28 후속 확인: 사용자가 LunchSync 카카오 본인 로그인이 성공한다고 알려 줬다. 이는 사용자 확인 결과이며 자동화된 OAuth 왕복이나 운영 설정 검증으로 확대하지 않는다. 실제 Toss 결제·원격 DB·HTTPS 운영 연결은 실행하지 않았다. `.local`에는 합성 계정과 로컬 키가 있어 Git에 추가하지 않는다. DB/서비스를 멈출 때 `--no-backup` 또는 전체 Docker prune을 사용하지 않는다.
