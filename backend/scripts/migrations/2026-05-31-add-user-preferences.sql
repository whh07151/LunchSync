-- ══════════════════════════════════════════════════════════
-- 마이그레이션: users 취향/알레르기/비선호 카테고리 컬럼 추가 (2026-05-31)
--
-- 배경 (CU-04 — 3주 로드맵 1주차 잔여):
--   추천 엔진은 이미 users 의 구조화된 취향 데이터를 읽어
--   가중치를 계산하도록 설계되어 있으나, 손님이 이를 설정할
--   수 있는 화면이 없었음. 본 마이그레이션은 그 입력 채널을
--   열기 위한 DB 측 컬럼 추가.
--
-- 컬럼 정의:
--   - taste_tags TEXT[]            — 좋아하는 맛 태그
--       (예: ["매콤","담백","짠","단","신","쓴"])
--       추천 가중치 +α 용도.
--   - allergens TEXT[]             — 알레르기 식재료
--       (예: ["견과","유제품","계란","갑각류","콩","밀","돼지","소"])
--       해당 식재료를 포함한 메뉴/식당은 후보군에서 제외.
--   - disliked_categories TEXT[]   — 비선호 음식 카테고리
--       (예: ["한식","중식","일식","양식","분식","패스트푸드","카페","디저트"])
--       해당 카테고리는 추천 점수에서 감점(또는 제외).
--
--   ※ users.allergies (단수형) 컬럼은 이미 존재함 (자유 입력 키워드용)
--      하지만 추천 엔진은 정규화된 식재료 목록을 원하므로
--      allergens (복수, 표준화 라벨) 컬럼을 별도로 둠.
--
-- 안전성:
--   - IF NOT EXISTS — 재실행 안전 (멱등)
--   - DEFAULT '{}'  — 기존 사용자도 영향 없음 (빈 배열)
--   - TEXT[] 사용  — PostgreSQL 배열 (Supabase PostgREST 가 그대로 JSON 배열로 노출)
--
-- 코드 동기화:
--   backend/src/users/users.service.ts 의 updatePreferences() 와 1:1 일치.
--   GET /api/users/me 응답에서 tasteTags / allergens / dislikedCategories
--   (camelCase) 로 노출됨.
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → 전체 붙여넣기 → Run.
-- ══════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS taste_tags TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS allergens TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS disliked_categories TEXT[] DEFAULT '{}';

-- 컬럼 코멘트 (DB 자체 문서화)
COMMENT ON COLUMN users.taste_tags
  IS '좋아하는 맛 태그 (매콤/담백/짠/단/신/쓴 등). 추천 가중치 +α';
COMMENT ON COLUMN users.allergens
  IS '알레르기 식재료 (견과/유제품/계란/갑각류/콩/밀/돼지/소 등). 후보군 제외 기준';
COMMENT ON COLUMN users.disliked_categories
  IS '비선호 음식 카테고리 (한식/중식/일식 등). 추천 점수 감점/제외';

COMMIT;

-- ── 검증 ─────────────────────────────────────────────────
-- SELECT column_name, data_type, udt_name
--   FROM information_schema.columns
--   WHERE table_name='users'
--     AND column_name IN ('taste_tags','allergens','disliked_categories');
-- 기대: 3행 모두 ARRAY / _text
