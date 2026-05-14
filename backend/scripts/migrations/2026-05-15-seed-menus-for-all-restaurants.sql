-- ══════════════════════════════════════════════════════════
-- 시드: 모든 식당에 가상 메뉴 5개씩 자동 추가
--
-- 작성일: 2026-05-15
-- 배경:
--   사장님 시연 발견 — 카카오 검색 결과 식당들에 menu_items 가 없어서
--   주문 화면에서 "메뉴 정보가 DB에 없어요" 에러로 결제 흐름 진행 불가.
--   시연용 가상 메뉴 5개를 모든 식당에 일괄 INSERT.
--
-- 정책:
--   - 식당 카테고리와 무관하게 한식 베이스 메뉴 5종 일괄 적용 (단순화)
--     김치찌개 / 된장찌개 / 비빔밥 / 제육볶음 / 순두부찌개
--   - 가격대 8500~10000원 — 1만원대 추천 점수 적합도 자연
--   - source='MANUAL' 로 표시 (시드 출처 추적용)
--   - is_available=true 로 즉시 주문 가능
--
-- 안전성:
--   - WHERE NOT EXISTS — 이미 메뉴 있는 식당은 건드리지 않음
--     (5/12 seed-gildong-with-images 에서 박은 길동 김밥마을 메뉴 등 보존)
--   - 재실행 안전 (중복 추가 안 됨)
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → Run
-- ══════════════════════════════════════════════════════════

BEGIN;

INSERT INTO menu_items
  (restaurant_id, name, price, category, description, image_url, source, is_available)
SELECT r.id, m.name, m.price, m.category, m.description, m.image_url, 'MANUAL', true
FROM restaurants r
CROSS JOIN (VALUES
  ('김치찌개',   9000,  'soup', '돼지고기 듬뿍 김치찌개',
   'https://source.unsplash.com/400x300/?kimchi-stew,korean'),
  ('된장찌개',   8500,  'soup', '구수한 된장찌개',
   'https://source.unsplash.com/400x300/?doenjang,korean'),
  ('비빔밥',     9500,  'rice', '나물과 고추장의 조화',
   'https://source.unsplash.com/400x300/?bibimbap,korean'),
  ('제육볶음',  10000,  'rice', '매콤한 제육 정식',
   'https://source.unsplash.com/400x300/?pork,korean'),
  ('순두부찌개', 9000,  'soup', '부드러운 순두부와 매콤한 국물',
   'https://source.unsplash.com/400x300/?sundubu,korean')
) AS m(name, price, category, description, image_url)
WHERE NOT EXISTS (
  -- 이미 같은 식당에 같은 메뉴가 있으면 추가하지 않음 (재실행 안전)
  SELECT 1 FROM menu_items mi
  WHERE mi.restaurant_id = r.id AND mi.name = m.name
);

COMMIT;

-- ── 검증 (실행 후 확인용) ──────────────────────────────────
-- SELECT r.name AS restaurant, COUNT(mi.id) AS menu_count
-- FROM restaurants r
-- LEFT JOIN menu_items mi ON mi.restaurant_id = r.id
-- GROUP BY r.id, r.name
-- HAVING COUNT(mi.id) > 0
-- ORDER BY menu_count DESC;
--
-- 기대: 거의 모든 식당이 5개 이상의 메뉴를 가짐.
