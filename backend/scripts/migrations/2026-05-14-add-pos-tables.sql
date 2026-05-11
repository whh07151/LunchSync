-- ══════════════════════════════════════════════════════════
-- 마이그레이션: pos_seats 테이블 추가 (2026-05-14)
--
-- 목적:
--   LSPOS 좌석 모듈 백엔드 통합. 기존에 localStorage 로만 유지되던
--   좌석 상태를 식당별로 서버에 보관해 단말 교체/새로고침 시에도 유지.
--
-- 데이터 모델:
--   - label / status / started_at / items(JSONB) / sort_order
--   - items 는 [{ menuId, name, price, quantity, addedAt }] 배열 형태
--
-- 안전성:
--   - IF NOT EXISTS — 재실행 안전
--   - FK CASCADE — 식당 삭제 시 좌석도 함께 정리
-- ══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS pos_seats (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  label         TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'empty' CHECK (status IN ('empty', 'occupied')),
  started_at    TIMESTAMPTZ,
  items         JSONB NOT NULL DEFAULT '[]'::jsonb,
  sort_order    INT NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 식당별 좌석 조회를 빠르게
CREATE INDEX IF NOT EXISTS idx_pos_seats_restaurant
  ON pos_seats(restaurant_id, sort_order);

-- 검증:
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name='pos_seats' ORDER BY ordinal_position;
