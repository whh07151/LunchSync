-- ══════════════════════════════════════════════════════════
-- 파일 역할: menu_items 테이블에 is_available 컬럼 추가 (품절 토글)
--
-- 배경:
--   사장 메뉴 관리 화면 + LSPOS pos_memo §2 좌석 메뉴 추가 시
--   "오늘 품절" 토글이 필요. soft-delete 가 아니라 일시 품절 상태.
--
-- 운영:
--   - 사장 메뉴 관리 화면 → 품절 스위치 → PATCH /pos/menus/item/:id { isAvailable: false }
--   - 추천 엔진 / 식당 상세는 is_available=true 인 메뉴만 노출 (추후 코드 반영)
--
-- 적용:
--   Supabase SQL Editor → 본 파일 붙여넣기 → Run
-- ══════════════════════════════════════════════════════════

-- 기본값 true: 기존 메뉴는 모두 판매중으로 유지
ALTER TABLE public.menu_items
  ADD COLUMN IF NOT EXISTS is_available BOOLEAN NOT NULL DEFAULT TRUE;

-- 추천 엔진 / 메뉴 목록 조회 시 자주 필터링되므로 인덱스 추가
CREATE INDEX IF NOT EXISTS menu_items_restaurant_available_idx
  ON public.menu_items(restaurant_id, is_available);
