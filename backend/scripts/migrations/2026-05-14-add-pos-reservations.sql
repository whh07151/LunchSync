-- ══════════════════════════════════════════════════════════
-- 마이그레이션: pos_reservations 테이블 추가 (2026-05-14)
--
-- 목적:
--   LSPOS 예약/웨이팅 모듈 백엔드 통합 — 식당별 예약(RESERVATION) /
--   웨이팅(WAITING) 목록을 서버에 보관. 단말 교체/새로고침에도 유지.
--
-- 데이터 모델:
--   - kind        예약 종류: WAITING / RESERVATION
--   - customer_name 손님 이름 (필수)
--   - party_size    인원 수 (필수, 양수)
--   - scheduled_at  예약 시각 (RESERVATION 만 사용, WAITING 은 NULL)
--   - note          비고 (선택)
--   - status        OPEN(대기) → SEATED(착석) / CANCELLED
--
-- 안전성:
--   - IF NOT EXISTS — 재실행 안전
--   - FK CASCADE — 식당 삭제 시 예약도 함께 정리
--   - status / kind CHECK 제약 — 잘못된 값 INSERT 차단
--
-- 코드와의 동기화:
--   backend/src/pos/pos-reservations.service.ts 의 select 컬럼 목록과
--   1:1 일치. 둘 중 하나만 바뀌면 PostgREST 가 silent 하게 null 반환하므로
--   함께 갱신할 것.
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → Run
-- ══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS pos_reservations (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  kind          TEXT NOT NULL CHECK (kind IN ('WAITING', 'RESERVATION')),
  customer_name TEXT NOT NULL,
  party_size    INT  NOT NULL CHECK (party_size > 0),
  scheduled_at  TIMESTAMPTZ,
  note          TEXT,
  status        TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'SEATED', 'CANCELLED')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 식당별 최신 예약 조회를 빠르게 (controller list 가 created_at DESC 정렬)
CREATE INDEX IF NOT EXISTS idx_pos_reservations_restaurant_created
  ON pos_reservations (restaurant_id, created_at DESC);

-- 활성 예약(OPEN) 만 빠르게 필터링 (대시보드 등 향후 활용)
CREATE INDEX IF NOT EXISTS idx_pos_reservations_status
  ON pos_reservations (restaurant_id, status)
  WHERE status = 'OPEN';

-- 검증 (선택, 실행 후 확인용)
-- SELECT column_name, data_type
-- FROM information_schema.columns
-- WHERE table_name = 'pos_reservations'
-- ORDER BY ordinal_position;
