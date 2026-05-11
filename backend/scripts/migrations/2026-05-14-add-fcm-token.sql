-- ══════════════════════════════════════════════════════════
-- 마이그레이션: users.fcm_token 컬럼 추가 (2026-05-14)
--
-- 목적:
--   FCM(Firebase Cloud Messaging) 푸시 알림 발송용 단말 토큰을 저장합니다.
--   - 손님 단말: 주문 상태 변경(ACCEPTED/PREPARING/DONE) 시 푸시 수신
--   - 사장 단말: 새 주문(PAID) 도착 시 푸시 수신
--
-- 동작:
--   - Flutter 앱 로그인 직후 POST /api/users/me/fcm-token 으로 저장
--   - 동일 사용자 다중 단말은 가장 최근 토큰만 유지 (단일 컬럼 UPSERT 정책)
--   - 토큰이 NULL 이면 푸시 발송 건너뜀
--
-- 안전성:
--   - IF NOT EXISTS 패턴 — 재실행해도 안전
--   - NULL 허용 — 기존 사용자도 영향 없음
-- ══════════════════════════════════════════════════════════

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- 검증: 컬럼 존재 확인
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name='users' AND column_name='fcm_token';
