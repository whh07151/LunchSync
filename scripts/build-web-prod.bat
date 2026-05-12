@echo off
REM ══════════════════════════════════════════════════════════
REM 파일 역할: 프로덕션(HTTPS) 웹 빌드 + 실행 스크립트
REM
REM 사용:
REM   1) HTTPS EC2 백엔드(Caddy + DuckDNS)가 살아있는 상태에서 실행
REM   2) Vercel 또는 Netlify 같은 정적 호스팅에 build/web/ 업로드 후
REM      도메인 매핑 → 카카오 redirect URI / Toss successUrl 갱신
REM
REM 환경변수(필요 시 수정):
REM   BACKEND_URL — 백엔드 API base URL (https 권장)
REM   TOSS_SUCCESS_URL / TOSS_FAIL_URL — 결제 콜백 URL (배포 도메인 기준)
REM ══════════════════════════════════════════════════════════

set BACKEND_URL=https://lunchsync-api.duckdns.org/api
set TOSS_SUCCESS_URL=https://lunchsync.vercel.app/payment/success
set TOSS_FAIL_URL=https://lunchsync.vercel.app/payment/fail

echo === BACKEND_URL: %BACKEND_URL%
echo === TOSS_SUCCESS_URL: %TOSS_SUCCESS_URL%
echo === TOSS_FAIL_URL: %TOSS_FAIL_URL%

flutter build web --release ^
  --dart-define=BACKEND_URL=%BACKEND_URL% ^
  --dart-define=TOSS_SUCCESS_URL=%TOSS_SUCCESS_URL% ^
  --dart-define=TOSS_FAIL_URL=%TOSS_FAIL_URL%

if %ERRORLEVEL% NEQ 0 (
  echo.
  echo *** 빌드 실패 — 위 로그 확인 ***
  exit /b %ERRORLEVEL%
)

echo.
echo === 빌드 산출물: build\web\
echo === 다음 단계: Vercel/Netlify 에 build\web\ 폴더 배포
