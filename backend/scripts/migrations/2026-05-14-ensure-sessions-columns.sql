-- ══════════════════════════════════════════════════════════
-- 마이그레이션: sessions 테이블 핵심 컬럼 보강 (2026-05-14)
--
-- 목적:
--   057ad30 에서 backend/src/sessions/sessions.service.ts 의 getTodaySessions
--   select 에 radius/budget/return_minutes/memo 를 추가했으나, 이 컬럼들이
--   sessions 테이블에 실제로 추가된 적이 명시적으로 기록된 마이그레이션이
--   부재. 2026-05-14-create-session-rpc.sql 의 INSERT 가 위 컬럼을 사용하므로
--   누락 시 RPC 호출이 silent 실패 또는 컬럼 미존재 에러 가능.
--
-- 안전성:
--   - ADD COLUMN IF NOT EXISTS — 이미 있으면 no-op (멱등)
--   - 모든 컬럼 NULL 허용 — 기존 세션 영향 없음
--   - DEFAULT 미지정 — 도메인 의미 강제 안 함 (호출부가 값 책임)
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → Run
--
-- 후속:
--   verify-schema.sql 로 컬럼 7개 모두 OK 확인.
-- ══════════════════════════════════════════════════════════

ALTER TABLE sessions
  ADD COLUMN IF NOT EXISTS radius         INT,
  ADD COLUMN IF NOT EXISTS budget         INT,
  ADD COLUMN IF NOT EXISTS return_minutes INT,
  ADD COLUMN IF NOT EXISTS memo           TEXT;

COMMENT ON COLUMN sessions.radius         IS '검색 반경 (m). 호스트가 세션 생성 시 지정';
COMMENT ON COLUMN sessions.budget         IS '1인 예산 (원). AI 추천 가격 적합도에 사용';
COMMENT ON COLUMN sessions.return_minutes IS '복귀 시각까지 남은 분 (점심 1시간 등)';
COMMENT ON COLUMN sessions.memo           IS '호스트 메모 / 조건 부연 설명';

-- 검증:
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name='sessions'
--     AND column_name IN ('radius', 'budget', 'return_minutes', 'memo')
--   ORDER BY column_name;
