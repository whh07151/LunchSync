-- ══════════════════════════════════════════════════════════
-- 파일 역할: POS-13 Toss POS 시뮬 결제 대응 마이그레이션
--
-- 배경:
--   - POS 단말(LSPOS)에서 사장님이 매장 손님에게 직접 결제를 받는 흐름 추가
--   - body: { method: 'CARD' | 'CASH', receivedAmount? } 를 받아 orders.status=PAID +
--     payment_method 를 'POS_TOSS' 또는 'POS_CASH' 로 기록
--   - 기존 payment_method_type ENUM(TOSS/CARD/CASH/SIMULATE) 에 POS 결제 두 값을
--     추가해 손님앱 토스 결제(=TOSS)와 매장 POS 결제(=POS_TOSS/POS_CASH)를 구분
--
-- 멱등 패턴:
--   · ENUM 미존재 환경(과거 마이그 미실행) 대비 CREATE TYPE 도 IF NOT EXISTS 처리
--   · ALTER TYPE ... ADD VALUE IF NOT EXISTS 는 PostgreSQL 9.6+ 표준 — 두 번 실행해도 안전
--   · orders.payment_method 컬럼은 2026-05-13 마이그에서 이미 추가된 환경 다수이므로
--     IF NOT EXISTS 로 재시도 시 NOOP
--
-- 적용:
--   Supabase Dashboard → SQL Editor → 본 파일 붙여넣기 → Run
--   적용 후 2026-05-14-verify-schema.sql 에 ENUM 검증 쿼리 보강 권장
-- ══════════════════════════════════════════════════════════

-- ── 1) payment_method_type ENUM 보장 ────────────────────
-- 과거 마이그가 누락된 환경 대응. 이미 존재하면 EXCEPTION 무시.
DO $$ BEGIN
  CREATE TYPE payment_method_type AS ENUM ('TOSS', 'CARD', 'CASH', 'SIMULATE');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── 2) POS 결제 두 값 ADD VALUE ─────────────────────────
-- POS_TOSS: POS 단말에서 토스 카드 결제 (시뮬 단계 — 실제 토스 POS API 미연동)
-- POS_CASH: POS 단말에서 현금 수납
ALTER TYPE payment_method_type ADD VALUE IF NOT EXISTS 'POS_TOSS';
ALTER TYPE payment_method_type ADD VALUE IF NOT EXISTS 'POS_CASH';

-- ── 3) orders.payment_method 컬럼 보장 ──────────────────
-- 2026-05-13-add-payment-method.sql 미적용 환경 대비. NULL 허용 유지.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_method payment_method_type;

-- ── 4) 매출 집계 인덱스 보장 ────────────────────────────
-- restaurant_id + status + payment_method 로 GROUP BY 잦음 (POS-08 매출 통계)
CREATE INDEX IF NOT EXISTS orders_restaurant_method_idx
  ON public.orders(restaurant_id, status, payment_method);
