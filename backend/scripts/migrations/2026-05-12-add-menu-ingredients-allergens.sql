-- ══════════════════════════════════════════════════════════
-- 마이그레이션: menu_items 에 ingredients/allergens/source 추가
--
-- 목적:
--   1) Gemini AI 가 생성한 메뉴의 재료/알레르기 정보 저장
--   2) 손님앱 추천 엔진이 알레르기 필터링 시 활용
--   3) 메뉴 출처 추적 (네이버 크롤링 vs AI 생성 vs 사장 수동)
--
-- 컬럼:
--   ingredients TEXT[]      - 주재료 배열 (예: ['돼지고기', '양배추', '식초'])
--   allergens   TEXT[]      - 8대 알레르기 (예: ['밀', '대두'])
--   source      TEXT        - CRAWL_NAVER | AI_GEMINI | MANUAL (기본 MANUAL)
--
-- 안전성:
--   - IF NOT EXISTS 패턴
--   - 기본값 빈 배열로 기존 행에 영향 없음
-- ══════════════════════════════════════════════════════════

ALTER TABLE menu_items
  ADD COLUMN IF NOT EXISTS ingredients TEXT[] DEFAULT '{}'::TEXT[];

ALTER TABLE menu_items
  ADD COLUMN IF NOT EXISTS allergens TEXT[] DEFAULT '{}'::TEXT[];

ALTER TABLE menu_items
  ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'MANUAL'
  CHECK (source IN ('CRAWL_NAVER', 'AI_GEMINI', 'MANUAL'));

-- 알레르기 필터링 빠른 조회 인덱스 (GIN — 배열 contains 연산)
CREATE INDEX IF NOT EXISTS idx_menu_items_allergens
  ON menu_items USING GIN (allergens);

-- 검증:
-- SELECT column_name, data_type, column_default
-- FROM information_schema.columns
-- WHERE table_name='menu_items' AND column_name IN ('ingredients','allergens','source');
