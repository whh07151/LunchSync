-- ══════════════════════════════════════════════════════════
-- 파일 역할: users 테이블에 restaurant_id 컬럼 추가
--           (OWNER 사용자 ↔ 운영 식당 매핑용)
--
-- 배경:
--   - 5/7 회원가입/인증 결정에서 OWNER 가입 + business_name/business_number는 받지만
--     restaurants.id 와의 직접 매핑은 미해결 상태였음
--   - 사장 홈(owner_home_screen)에서 GET /api/pos/restaurants/:id/orders 를 호출하려면
--     "현재 로그인한 OWNER가 어떤 식당의 사장인지" 알아야 함
--   - LSPOS DEV_LOG 백엔드 협의 #2 와도 동일 항목
--
-- 운영 흐름:
--   1. 사용자가 OWNER로 가입 → users.restaurant_id 는 NULL
--   2. 운영자(우현호)가 Supabase 콘솔에서 직접 매핑:
--        UPDATE users SET restaurant_id = '<해당 식당 UUID>' WHERE id = '<owner UUID>';
--   3. OWNER가 다음 로그인 시 owner_home_screen 에 실제 주문 데이터 표시
--
-- 적용 방법:
--   Supabase Dashboard → SQL Editor → 이 파일 내용 붙여넣기 → Run
--
-- 안전성:
--   - ADD COLUMN IF NOT EXISTS — 이미 컬럼 있어도 실패하지 않음
--   - FK 제약은 restaurants 테이블 존재 시에만 추가 (예외 무시)
-- ══════════════════════════════════════════════════════════

-- ── 1) restaurant_id 컬럼 추가 ───────────────────────────
-- NULL 허용: 기존 카카오 가입 손님 + 미매핑 OWNER 모두 NULL 상태로 유지
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS restaurant_id UUID;

-- ── 2) restaurants 외래키 (가능한 경우에만) ─────────────
-- restaurants 테이블이 없거나 제약이 이미 있으면 조용히 패스
DO $$ BEGIN
  ALTER TABLE public.users
    ADD CONSTRAINT users_restaurant_id_fkey
    FOREIGN KEY (restaurant_id)
    REFERENCES public.restaurants(id)
    ON DELETE SET NULL;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_table THEN NULL;
END $$;

-- ── 3) 조회 인덱스 ───────────────────────────────────────
-- 사장 홈에서 자주 사용. NULL 인 행은 인덱스에서 제외해서 크기 절약
CREATE INDEX IF NOT EXISTS users_restaurant_id_idx
  ON public.users(restaurant_id)
  WHERE restaurant_id IS NOT NULL;

-- ══════════════════════════════════════════════════════════
-- 검증 쿼리:
--   SELECT column_name, data_type, is_nullable
--   FROM information_schema.columns
--   WHERE table_schema='public' AND table_name='users' AND column_name='restaurant_id';
--
-- 외래키 확인:
--   SELECT conname, conrelid::regclass, confrelid::regclass
--   FROM pg_constraint
--   WHERE conname='users_restaurant_id_fkey';
-- ══════════════════════════════════════════════════════════
