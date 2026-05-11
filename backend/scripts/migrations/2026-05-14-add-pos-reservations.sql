-- ══════════════════════════════════════════════════════════
-- 마이그레이션: pos_reservations 테이블 추가 (2026-05-14)
--
-- 목적:
--   LSPOS 예약/웨이팅 모듈 백엔드 통합. localStorage 만 사용하던
--   웨이팅(즉시 대기) / 예약(시각 지정) 목록을 서버에 보관.
--
-- 데이터 모델:
--   - kind        'WAITING' | 'RESERVATION'
--   - status      'OPEN' | 'SEATED' | 'CANCELLED'
--   - scheduled_at: RESERVATION 만 사용. WAITING 은 NULL.
--
-- 안전성:
--   - IF NOT EXISTS — 재실행 안전
--   - FK CASCADE — 식당 삭제 시 예약도 정리
-- ══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS pos_reservations (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id  UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  kind           TEXT NOT NULL CHECK (kind IN ('WAITING', 'RESERVATION')),
  customer_name  TEXT NOT NULL,
  party_size     INT NOT NULL CHECK (party_size > 0),
  scheduled_at   TIMESTAMPTZ,
  note           TEXT,
  status         TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'SEATED', 'CANCELLED')),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 식당별 + OPEN 상태 빠른 조회 (대시보드 카운트용)
CREATE INDEX IF NOT EXISTS idx_pos_reservations_restaurant
  ON pos_reservations(restaurant_id, status, created_at DESC);

-- 검증:
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name='pos_reservations' ORDER BY ordinal_position;
