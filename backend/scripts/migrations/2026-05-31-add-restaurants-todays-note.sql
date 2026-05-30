-- ══════════════════════════════════════════════════════════
-- 마이그레이션: restaurants.todays_note (2026-05-31)
--
-- 목적:
--   WOW 포인트 1순위 — "사장님 오늘의 한 줄". 사장이 POS/사장앱에서
--   당일 한 줄(예: "비 오니까 얼큰순두부 강추 🌧")을 입력하면 손님
--   추천 카드 상단에 인용구로 노출되고, 추천 점수에 +가중치가 추가
--   되도록 한다.
--
-- 컬럼:
--   restaurants.todays_note (TEXT NULL)
--     - 최대 길이 제약은 application 단에서 (200자 권장)
--     - NULL 의미 = 오늘의 한 줄 없음 (UI 미노출)
--     - 매일 자정 cron 으로 자동 NULL 화 (운영 단에서 추후 구현)
--
-- 안전성:
--   - ADD COLUMN IF NOT EXISTS — 이미 있으면 no-op (멱등)
--   - NULL 허용 + DEFAULT 없음 — 기존 식당 영향 없음
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → Run
--
-- 후속:
--   verify-schema.sql 의 컬럼 검증에 restaurants.todays_note 추가
--   별도 PR.
-- ══════════════════════════════════════════════════════════

ALTER TABLE restaurants
  ADD COLUMN IF NOT EXISTS todays_note TEXT;

COMMENT ON COLUMN restaurants.todays_note IS
  '사장이 당일 입력하는 한 줄 메시지 (NULL = 미입력, 매일 자정 초기화 예정)';

-- 검증:
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name='restaurants' AND column_name='todays_note';
