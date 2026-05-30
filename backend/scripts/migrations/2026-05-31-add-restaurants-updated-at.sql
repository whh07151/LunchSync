-- ══════════════════════════════════════════════════════════
-- 마이그레이션: restaurants.updated_at (2026-05-31)
--
-- 배경:
--   WOW#1 PATCH /api/pos/restaurants/:id/todays-note 가 500 으로 실패.
--   원인: pos.service.ts updateTodaysNote() 가
--         .select('id, todays_note, updated_at') 를 호출했는데
--         restaurants 테이블에 updated_at 컬럼이 없어 PostgREST 가
--         "column restaurants.updated_at does not exist" 에러 던짐.
--
-- 1차 fix (코드):
--   select / 반환 타입에서 updated_at 제거 (이 PR 동봉).
--
-- 2차 fix (DDL, 본 파일):
--   restaurants 에 updated_at TIMESTAMPTZ 컬럼 추가 + trigger 로 자동 갱신.
--   향후 누가 다시 updated_at 을 select 에 포함시켜도 안전하도록 사전 방지.
--
-- 안전성:
--   - ADD COLUMN IF NOT EXISTS — 멱등
--   - DEFAULT now() — 기존 row 도 즉시 채워짐
--   - trigger 는 CREATE OR REPLACE FUNCTION + DROP TRIGGER IF EXISTS 로 멱등
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → Run
--
-- 검증:
--   SELECT column_name, data_type FROM information_schema.columns
--     WHERE table_name='restaurants' AND column_name='updated_at';
-- ══════════════════════════════════════════════════════════

ALTER TABLE restaurants
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

COMMENT ON COLUMN restaurants.updated_at IS
  '식당 정보 마지막 갱신 시각 (todays_note 등 변경 시 trigger 로 자동 갱신)';

-- UPDATE 시 updated_at 을 자동 갱신하는 trigger 함수.
CREATE OR REPLACE FUNCTION set_restaurants_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_restaurants_updated_at ON restaurants;
CREATE TRIGGER trg_restaurants_updated_at
  BEFORE UPDATE ON restaurants
  FOR EACH ROW
  EXECUTE FUNCTION set_restaurants_updated_at();
