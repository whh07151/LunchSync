-- ══════════════════════════════════════════════════════════
-- 마이그레이션: restaurants 테이블의 빈 image_url 일괄 폴백 매핑
--
-- 작성일: 2026-05-14
-- 배경:
--   사장님 피드백 — "메뉴넣으면서 이미지도 넣어달라니까"
--   d379484 (restaurants.service.ts) 에서 image_url 컬럼 select 는 살렸지만
--   기존 DB 에는 image_url IS NULL 인 식당이 다수 (시드 18곳 + 크롤 결과들).
--   결과: 카드/지도/상세에 회색 박스만 → 시연 임팩트 0.
--
-- 처리:
--   카테고리별로 Unsplash Source API URL 매핑 후 IS NULL 또는 '' 인
--   레코드만 UPDATE. 사장님이 이미 진짜 사진 URL 박은 식당은 건드리지 않음.
--
-- 패턴:
--   https://source.unsplash.com/400x300/?<카테고리 키워드>
--     - 한식 → korean,food
--     - 일식 → japanese,sushi
--     - 중식 → chinese,noodle
--     - 양식 → western,pasta
--     - 분식 → street-food,tteokbokki
--     - 카페 → cafe,coffee
--     - 패스트푸드 → burger,fastfood
--     - 아시안 → asian,food
--     - 기타/NULL → korean,food (안전 기본값)
--
-- 코드와의 동기화:
--   백엔드 src/restaurants/restaurant-image-fallback.ts 의 CATEGORY_KEYWORDS
--   매핑과 1:1 일치. 둘 중 하나만 바뀌면 색이 어긋날 수 있으므로 함께 갱신할 것.
--   ※ 코드 헬퍼는 식당명 슬러그도 부가 키워드로 붙이지만 SQL 은 일괄
--      처리이므로 카테고리 키워드만 사용 (단순화). Unsplash 가 키워드만으로도
--      충분히 일관된 사진을 돌려준다.
--
-- 안전성:
--   - WHERE 절로 빈 값만 대상 — 사장님이 박은 진짜 URL 절대 안 건드림
--   - 트랜잭션 처리: 카테고리별 분기 UPDATE 가 모두 성공해야 commit
--   - 멱등성: 여러 번 실행해도 결과 동일 (빈 값이 없으면 UPDATE 0건)
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → Run
-- ══════════════════════════════════════════════════════════

BEGIN;

-- ── 0. image_url 컬럼이 없으면 먼저 생성 ───────────────────
-- d379484 에서 백엔드 select 는 컬럼 사용을 시작했으나, DB 스키마에는
-- 컬럼 자체가 추가된 적이 없어 ERROR 42703 발생 가능.
-- 안전하게 IF NOT EXISTS 로 멱등성 보장.
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS image_url TEXT;

-- ── 한식 ────────────────────────────────────────────────
UPDATE restaurants
SET image_url = 'https://source.unsplash.com/400x300/?korean,food'
WHERE category = '한식'
  AND (image_url IS NULL OR image_url = '');

-- ── 일식 ────────────────────────────────────────────────
UPDATE restaurants
SET image_url = 'https://source.unsplash.com/400x300/?japanese,sushi'
WHERE category = '일식'
  AND (image_url IS NULL OR image_url = '');

-- ── 중식 ────────────────────────────────────────────────
UPDATE restaurants
SET image_url = 'https://source.unsplash.com/400x300/?chinese,noodle'
WHERE category = '중식'
  AND (image_url IS NULL OR image_url = '');

-- ── 양식 ────────────────────────────────────────────────
UPDATE restaurants
SET image_url = 'https://source.unsplash.com/400x300/?western,pasta'
WHERE category = '양식'
  AND (image_url IS NULL OR image_url = '');

-- ── 분식 ────────────────────────────────────────────────
UPDATE restaurants
SET image_url = 'https://source.unsplash.com/400x300/?street-food,tteokbokki'
WHERE category = '분식'
  AND (image_url IS NULL OR image_url = '');

-- ── 카페 ────────────────────────────────────────────────
UPDATE restaurants
SET image_url = 'https://source.unsplash.com/400x300/?cafe,coffee'
WHERE category = '카페'
  AND (image_url IS NULL OR image_url = '');

-- ── 패스트푸드 ───────────────────────────────────────────
UPDATE restaurants
SET image_url = 'https://source.unsplash.com/400x300/?burger,fastfood'
WHERE category = '패스트푸드'
  AND (image_url IS NULL OR image_url = '');

-- ── 아시안 ──────────────────────────────────────────────
UPDATE restaurants
SET image_url = 'https://source.unsplash.com/400x300/?asian,food'
WHERE category = '아시안'
  AND (image_url IS NULL OR image_url = '');

-- ── 그 외 카테고리 또는 NULL 카테고리 (한식 기본값으로 폴백) ──
-- 위 카테고리들에 매칭되지 않은 잔여 레코드 모두 처리.
-- '기타' 같은 비표준 값이나 category 가 NULL 인 옛 레코드도 커버.
UPDATE restaurants
SET image_url = 'https://source.unsplash.com/400x300/?korean,food'
WHERE (image_url IS NULL OR image_url = '');

COMMIT;

-- ── 검증 쿼리 (선택, 실행 후 확인용) ──────────────────────
-- SELECT category, COUNT(*) FILTER (WHERE image_url IS NULL OR image_url = '') AS empty_count,
--        COUNT(*) AS total
-- FROM restaurants
-- GROUP BY category
-- ORDER BY category;
