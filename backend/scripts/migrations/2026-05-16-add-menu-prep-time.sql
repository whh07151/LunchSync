-- ══════════════════════════════════════════════════════════
-- 마이그레이션: menu_items.prep_time_minutes 컬럼 추가 (2026-05-16)
--
-- 배경 (배민 패턴 — 자율 발전 로드맵 단계 2):
--   사장이 메뉴별 예상 조리 시간 입력 → 손님 주문 추적 화면에
--   "약 N분 후 픽업 가능" ETA 카드 표시.
--
-- 데이터 모델:
--   prep_time_minutes INT (1~120, NULL 허용, DEFAULT 15)
--   - 기존 메뉴는 DEFAULT 15 (사장 미입력 시)
--   - 사장 의도와 다를 수 있어 검토 권장
--
-- ETA 계산식 (백엔드):
--   estimated_ready_at = accepted_at(또는 created_at) + max(prep_time_minutes)
--   한 주문 중 가장 오래 걸리는 메뉴 기준 (배민 패턴)
--
-- 안전성:
--   - ADD COLUMN IF NOT EXISTS — 멱등성
--   - 기존 행 영향 0 (DEFAULT 15 자동 적용)
--   - CHECK 제약 — 1~120 또는 NULL
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → Run
-- ══════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE menu_items
  ADD COLUMN IF NOT EXISTS prep_time_minutes INT DEFAULT 15;

-- prep_time_minutes 범위 제약 (1~120 또는 NULL)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'menu_items_prep_time_range'
  ) THEN
    ALTER TABLE menu_items
      ADD CONSTRAINT menu_items_prep_time_range
      CHECK (prep_time_minutes IS NULL OR (prep_time_minutes BETWEEN 1 AND 120));
  END IF;
END $$;

COMMENT ON COLUMN menu_items.prep_time_minutes IS '메뉴별 예상 조리 시간 (분, 1~120, NULL=미설정)';

COMMIT;

-- ── 검증 ─────────────────────────────────────────────────
-- SELECT column_name, data_type, column_default FROM information_schema.columns
--   WHERE table_name='menu_items' AND column_name='prep_time_minutes';
-- 기대: prep_time_minutes / integer / 15
