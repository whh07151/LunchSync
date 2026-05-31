-- ══════════════════════════════════════════════════════════
-- 마이그레이션: menu_items.allergens / users.allergens 보강 (CORE-09)
--
-- 목적:
--   1) 메뉴 알레르기 정확 매칭 검증기(CORE-09) 구현을 위한 보강.
--      - menu_items.allergens 는 2026-05-12 마이그레이션에서 이미 추가됐지만
--        이 파일을 단독으로 실행해도 결과가 동일하도록 멱등 패턴 재선언.
--      - users.allergens 는 CU-04 동시 작업과 충돌 없이 추가되도록
--        IF NOT EXISTS 패턴으로만 보강. 동일 컬럼을 두 PR 이 동시에 추가해도
--        먼저 적용된 쪽 결과를 신뢰하고 뒤 적용은 no-op 으로 떨어진다.
--
--   2) 손님앱이 GET /api/menus/restaurant/:id/check-allergens?userId= 호출 시
--      users.allergens ∩ menu_items.allergens 교집합을 빠르게 계산할 수 있도록
--      menu_items.allergens GIN 인덱스(이미 2026-05-12 추가됨)도 멱등 재선언.
--
-- 사용처:
--   - backend/src/menus/menus.service.ts checkAllergens()
--   - lib/features/menu/menu_screen.dart (메뉴 카드 ⚠️ 배지)
--
-- 안전성:
--   - ADD COLUMN IF NOT EXISTS, CREATE INDEX IF NOT EXISTS 모두 멱등.
--   - 기존 행은 DEFAULT '{}' 로 채워져 NOT NULL 제약과 충돌하지 않는다.
--   - PostgREST silent failure 차단 — verify-schema.sql 에 같이 등록.
-- ══════════════════════════════════════════════════════════

-- ── 1) 메뉴 알레르기 컬럼 (2026-05-12 와 동일하지만 멱등 재선언) ──
ALTER TABLE menu_items
  ADD COLUMN IF NOT EXISTS allergens TEXT[] DEFAULT '{}'::TEXT[];

-- 알레르기 교집합 조회를 위한 GIN 인덱스
-- 배열 contains/overlap 연산자(`&&`, `@>`) 가속용.
CREATE INDEX IF NOT EXISTS idx_menu_items_allergens
  ON menu_items USING GIN (allergens);

-- ── 2) 사용자 알레르기 컬럼 (CU-04 와 IF NOT EXISTS 로 공존) ──
--   users.allergens TEXT[] — 사용자가 회피하고 싶은 알레르기 키워드 배열.
--   예: ['nuts', 'egg', '땅콩'] 등. 키워드 정규화는 백엔드 서비스에서 수행.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS allergens TEXT[] DEFAULT '{}'::TEXT[];

-- ── 3) 검증 쿼리 ──────────────────────────────────────────
-- SELECT column_name, data_type, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND (
--     (table_name = 'menu_items' AND column_name = 'allergens') OR
--     (table_name = 'users'      AND column_name = 'allergens')
--   );
--
-- 기대값:
--   menu_items.allergens : ARRAY ('{}'::text[])
--   users.allergens      : ARRAY ('{}'::text[])
