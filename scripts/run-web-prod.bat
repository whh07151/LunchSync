@echo off
REM ══════════════════════════════════════════════════════════
REM 파일 역할: 프로덕션 백엔드(HTTPS)에 연결된 상태로 로컬 Chrome 실행
REM
REM 사용:
REM   1) EC2 HTTPS 백엔드가 살아있는 상태에서 실행
REM   2) 로컬 Chrome 이 실제 prod 데이터로 동작 — 카카오 redirect URI 일치 필수
REM
REM 카카오 콘솔 셋업:
REM   redirect URI 에 http://localhost:8080/oauth 가 등록돼 있어야 함
REM   (메모리: project_flutter_web_run.md — --web-port 8080 고정 필수)
REM ══════════════════════════════════════════════════════════

set BACKEND_URL=https://lunchsync-api.duckdns.org/api

echo === BACKEND_URL: %BACKEND_URL%
echo === 카카오 redirect URI: http://localhost:8080/oauth (콘솔에 등록돼 있어야 동작)

flutter run -d chrome --web-port 8080 ^
  --dart-define=BACKEND_URL=%BACKEND_URL%
