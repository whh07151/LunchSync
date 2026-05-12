-- ══════════════════════════════════════════════════════════
-- 파일 역할: orders.payment_method 컬럼 추가
--
-- 배경:
--   - orders.service.createOrder 가 dto.paymentMethod 를 받지만 DB 에 저장 안 됨
--   - LSPOS 매출 통계 (#9b 백엔드 협의) 와 사장 매출 화면이 결제수단별 분리 필요
--
-- ENUM:
--   TOSS     — 토스 결제위젯 v2 (손님앱 흐름)
--   CARD     — 매장용 카드 단말 결제 (POS 좌석 결제)
--   CASH     — 현금 (POS 좌석 결제)
--   SIMULATE — 가상 결제 (테스트/캡스톤 시연)
--
-- 적용:
--   Supabase SQL Editor → 본 파일 붙여넣기 → Run
-- ══════════════════════════════════════════════════════════

-- ── ENUM 정의 ────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE payment_method_type AS ENUM ('TOSS', 'CARD', 'CASH', 'SIMULATE');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── orders.payment_method 컬럼 추가 ───────────────────
-- NULL 허용: 기존 행은 method 모름 → NULL 그대로
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_method payment_method_type;

-- ── 매출 집계 인덱스 ────────────────────────────────────
-- POS 매출 통계 시 restaurant_id + status + payment_method 로 자주 GROUP BY
CREATE INDEX IF NOT EXISTS orders_restaurant_method_idx
  ON public.orders(restaurant_id, status, payment_method);
