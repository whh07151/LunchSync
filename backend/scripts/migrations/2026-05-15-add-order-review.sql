-- ══════════════════════════════════════════════════════════
-- 마이그레이션: orders.review_score + orders.review_text 컬럼 추가 (2026-05-15)
--
-- 배경 (배민 패턴 — 자율 발전 로드맵):
--   점심 후 별점 + 리뷰 작성 = 다음 주 의사결정 참고 데이터.
--   사장 어플에서 매장별 평균 평점 + 손님 리뷰 표시 (POS-13 후속).
--
-- 데이터 모델:
--   - review_score   INT (1~5, NULL 허용)
--   - review_text    TEXT (최대 500자, NULL 허용)
--   - review_at      TIMESTAMPTZ (작성 시각, NULL = 미작성)
--
-- 정책:
--   - COMPLETED 상태에서만 리뷰 작성 가능 (서비스 단 검증)
--   - 1주문 1리뷰 (중복 시 update)
--   - 사장 거절 (CANCELLED) 은 리뷰 불가
--
-- 안전성:
--   - ADD COLUMN IF NOT EXISTS — 멱등성
--   - 기존 행 영향 0 (NULL DEFAULT)
--   - CHECK 제약 — review_score 는 1~5 만 (또는 NULL)
--
-- 코드 동기화:
--   backend/src/orders/orders.service.ts 의 addReview 메서드와 1:1 일치.
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → Run
-- ══════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS review_score INT,
  ADD COLUMN IF NOT EXISTS review_text  TEXT,
  ADD COLUMN IF NOT EXISTS review_at    TIMESTAMPTZ;

-- review_score 범위 제약 (1~5 또는 NULL)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'orders_review_score_range'
  ) THEN
    ALTER TABLE orders
      ADD CONSTRAINT orders_review_score_range
      CHECK (review_score IS NULL OR (review_score BETWEEN 1 AND 5));
  END IF;
END $$;

COMMENT ON COLUMN orders.review_score IS '별점 (1~5, NULL=미작성)';
COMMENT ON COLUMN orders.review_text  IS '손님 리뷰 본문 (최대 500자)';
COMMENT ON COLUMN orders.review_at    IS '리뷰 작성 시각';

-- 빠른 평점 집계를 위한 인덱스 (사장 어플 매장 평점 표시)
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_review
  ON orders (restaurant_id, review_score)
  WHERE review_score IS NOT NULL;

COMMIT;

-- ── 검증 ─────────────────────────────────────────────────
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name='orders' AND column_name LIKE 'review_%';
-- 기대: review_score / integer, review_text / text, review_at / timestamp with time zone
