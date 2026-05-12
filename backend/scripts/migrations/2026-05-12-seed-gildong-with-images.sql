-- ══════════════════════════════════════════════════════════
-- 길동 시드 데이터 (사용자 현재 위치 검증용, 2026-05-12 추가)
--
-- 배경:
--   사용자가 강동구 길동에서 앱 켰을 때:
--   1) 카카오 API 가 길동 식당 30+개 가져왔으나
--   2) 네이버 메뉴 API 실패 + Gemini AI 폴백 quota 초과로 메뉴 0개
--   3) 결과: 식당은 보이지만 클릭해도 메뉴/가격 없음 → 시연 임팩트 0
--
-- 처리:
--   강남역 시드(2026-05-12-seed-demo-data.sql)와 동일 패턴으로 길동에도
--   5개 식당 + 24개 메뉴 + 음식 사진 URL 미리 박아둠.
--
-- 사진 URL:
--   Unsplash Source API — `https://source.unsplash.com/?keyword` 형식.
--   메뉴 이름·카테고리에 맞는 키워드 매핑. CORS·인증 없이 즉시 사용.
--
-- 안전성:
--   - 식당 ID 는 'cccc...~gggg...' 패턴 (강남 시드의 11111~55555 와 분리)
--   - INSERT ... ON CONFLICT (id) DO UPDATE — 재실행 안전
--   - DELETE FROM order_items / orders 정리 후 menu_items DELETE
-- ══════════════════════════════════════════════════════════

-- ── 길동 식당 5개 (사용자 GPS 37.534, 127.144 근방) ───────
INSERT INTO restaurants (id, name, category, address, lat, lng, price_range)
VALUES
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '길동 김밥마을', '분식',
   '서울 강동구 길동 1234', 37.5340, 127.1440, 1),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '길동 청기와집', '한식',
   '서울 강동구 길동 2345', 37.5350, 127.1450, 2),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '길동 라멘야', '일식',
   '서울 강동구 길동 3456', 37.5330, 127.1430, 2),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', '길동 이탈리아 키친', '양식',
   '서울 강동구 길동 4567', 37.5345, 127.1455, 3),
  ('99999999-9999-9999-9999-999999999999', '길동 만리장성', '중식',
   '서울 강동구 길동 5678', 37.5335, 127.1445, 2)
ON CONFLICT (id) DO UPDATE
  SET name = EXCLUDED.name,
      category = EXCLUDED.category,
      address = EXCLUDED.address,
      lat = EXCLUDED.lat,
      lng = EXCLUDED.lng,
      price_range = EXCLUDED.price_range;

-- ── 재실행 안전 정리 (order_items → orders → menu_items) ──
DELETE FROM order_items
WHERE menu_item_id IN (
  SELECT id FROM menu_items
  WHERE restaurant_id IN (
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
    'ffffffff-ffff-ffff-ffff-ffffffffffff',
    '99999999-9999-9999-9999-999999999999'
  )
);

DELETE FROM orders
WHERE restaurant_id IN (
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
  'ffffffff-ffff-ffff-ffff-ffffffffffff',
  '99999999-9999-9999-9999-999999999999'
);

DELETE FROM menu_items
WHERE restaurant_id IN (
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
  'ffffffff-ffff-ffff-ffff-ffffffffffff',
  '99999999-9999-9999-9999-999999999999'
);

-- ── 길동 김밥마을 (분식) ─────────────────────────────────
INSERT INTO menu_items (restaurant_id, name, price, category, description,
                        image_url, ingredients, allergens, source, is_available)
VALUES
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '참치 김밥', 4500, 'rice',
   '신선한 참치와 야채를 듬뿍',
   'https://source.unsplash.com/400x300/?kimbap',
   ARRAY['참치', '쌀', '단무지', '계란'], ARRAY['생선', '계란'], 'MANUAL', true),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '치즈 라볶이', 6500, 'snack',
   '쫄깃한 떡과 진한 치즈',
   'https://source.unsplash.com/400x300/?tteokbokki',
   ARRAY['떡', '어묵', '치즈', '고추장'], ARRAY['유제품', '대두', '밀'], 'MANUAL', true),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '왕돈가스', 8500, 'rice',
   '바삭한 왕돈가스 정식',
   'https://source.unsplash.com/400x300/?donkatsu',
   ARRAY['돼지고기', '빵가루', '계란'], ARRAY['밀', '계란', '대두'], 'MANUAL', true),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '얼큰 라면', 4000, 'noodle',
   '진한 국물 라면',
   'https://source.unsplash.com/400x300/?ramen+korean',
   ARRAY['면', '계란', '파'], ARRAY['밀', '계란', '대두'], 'MANUAL', true),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '오므라이스', 7500, 'rice',
   '폭신한 계란 위에 토마토 케첩',
   'https://source.unsplash.com/400x300/?omurice',
   ARRAY['쌀', '계란', '햄', '양파'], ARRAY['계란', '대두'], 'MANUAL', true);

-- ── 길동 청기와집 (한식) ─────────────────────────────────
INSERT INTO menu_items (restaurant_id, name, price, category, description,
                        image_url, ingredients, allergens, source, is_available)
VALUES
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '김치찌개', 9000, 'soup',
   '집밥 같은 진한 김치찌개',
   'https://source.unsplash.com/400x300/?kimchi+jjigae',
   ARRAY['김치', '돼지고기', '두부', '파'], ARRAY['대두'], 'MANUAL', true),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '된장찌개', 9000, 'soup',
   '구수한 된장찌개',
   'https://source.unsplash.com/400x300/?doenjang+jjigae',
   ARRAY['된장', '두부', '애호박', '감자'], ARRAY['대두'], 'MANUAL', true),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '제육볶음 정식', 11000, 'rice',
   '매콤한 제육과 흰밥',
   'https://source.unsplash.com/400x300/?jeyuk+bokkeum',
   ARRAY['돼지고기', '양파', '고추장', '쌀'], ARRAY['대두'], 'MANUAL', true),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '비빔밥', 10000, 'rice',
   '나물 듬뿍 비빔밥',
   'https://source.unsplash.com/400x300/?bibimbap',
   ARRAY['쌀', '나물', '계란', '고추장'], ARRAY['계란', '대두'], 'MANUAL', true),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '소고기 미역국', 12000, 'soup',
   '엄마표 미역국',
   'https://source.unsplash.com/400x300/?miyeok+guk',
   ARRAY['소고기', '미역', '마늘'], ARRAY[]::TEXT[], 'MANUAL', true);

-- ── 길동 라멘야 (일식) ───────────────────────────────────
INSERT INTO menu_items (restaurant_id, name, price, category, description,
                        image_url, ingredients, allergens, source, is_available)
VALUES
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '돈코츠 라멘', 12000, 'noodle',
   '진한 돼지뼈 육수',
   'https://source.unsplash.com/400x300/?tonkotsu+ramen',
   ARRAY['면', '돼지고기', '파', '계란'], ARRAY['밀', '계란', '대두'], 'MANUAL', true),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '쇼유 라멘', 11000, 'noodle',
   '깔끔한 간장 베이스',
   'https://source.unsplash.com/400x300/?shoyu+ramen',
   ARRAY['면', '닭고기', '간장', '파'], ARRAY['밀', '대두'], 'MANUAL', true),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '연어 사시미', 18000, 'rice',
   '신선한 연어회',
   'https://source.unsplash.com/400x300/?salmon+sashimi',
   ARRAY['연어', '간장', '와사비'], ARRAY['생선', '대두'], 'MANUAL', true),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '치킨 가라아게', 9000, 'snack',
   '바삭한 일본식 닭튀김',
   'https://source.unsplash.com/400x300/?karaage',
   ARRAY['닭고기', '간장', '생강', '밀가루'], ARRAY['밀', '대두'], 'MANUAL', true),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '교자', 7500, 'snack',
   '쫄깃한 일본식 만두',
   'https://source.unsplash.com/400x300/?gyoza',
   ARRAY['돼지고기', '부추', '밀가루'], ARRAY['밀', '대두'], 'MANUAL', true);

-- ── 길동 이탈리아 키친 (양식) ────────────────────────────
INSERT INTO menu_items (restaurant_id, name, price, category, description,
                        image_url, ingredients, allergens, source, is_available)
VALUES
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', '까르보나라', 15000, 'noodle',
   '진한 크림 까르보나라',
   'https://source.unsplash.com/400x300/?carbonara+pasta',
   ARRAY['파스타', '베이컨', '계란', '크림'], ARRAY['밀', '계란', '유제품'], 'MANUAL', true),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', '토마토 파스타', 13000, 'noodle',
   '신선한 토마토 소스',
   'https://source.unsplash.com/400x300/?tomato+pasta',
   ARRAY['파스타', '토마토', '바질', '마늘'], ARRAY['밀'], 'MANUAL', true),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', '마르게리타 피자', 16000, 'snack',
   '나폴리 스타일',
   'https://source.unsplash.com/400x300/?margherita+pizza',
   ARRAY['밀가루', '토마토', '모짜렐라', '바질'], ARRAY['밀', '유제품'], 'MANUAL', true),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', '시저 샐러드', 11000, 'rice',
   '신선한 로메인 + 그라나파다노',
   'https://source.unsplash.com/400x300/?caesar+salad',
   ARRAY['로메인', '닭가슴살', '치즈', '크루통'],
   ARRAY['밀', '유제품', '계란'], 'MANUAL', true),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', '봉골레 파스타', 16000, 'noodle',
   '바지락 듬뿍',
   'https://source.unsplash.com/400x300/?vongole+pasta',
   ARRAY['파스타', '바지락', '마늘', '올리브유'], ARRAY['밀', '조개류'], 'MANUAL', true);

-- ── 길동 만리장성 (중식) ─────────────────────────────────
INSERT INTO menu_items (restaurant_id, name, price, category, description,
                        image_url, ingredients, allergens, source, is_available)
VALUES
  ('99999999-9999-9999-9999-999999999999', '짜장면', 7000, 'noodle',
   '진한 춘장 베이스',
   'https://source.unsplash.com/400x300/?jjajangmyeon',
   ARRAY['면', '춘장', '양파', '돼지고기'], ARRAY['밀', '대두'], 'MANUAL', true),
  ('99999999-9999-9999-9999-999999999999', '짬뽕', 8500, 'noodle',
   '얼큰한 해물 짬뽕',
   'https://source.unsplash.com/400x300/?jjamppong',
   ARRAY['면', '오징어', '홍합', '청경채'],
   ARRAY['밀', '조개류', '갑각류'], 'MANUAL', true),
  ('99999999-9999-9999-9999-999999999999', '탕수육 (소)', 18000, 'snack',
   '바삭한 옛날 스타일',
   'https://source.unsplash.com/400x300/?tangsuyuk',
   ARRAY['돼지고기', '튀김옷', '식초', '설탕'], ARRAY['밀', '대두'], 'MANUAL', true),
  ('99999999-9999-9999-9999-999999999999', '마파두부덮밥', 10000, 'rice',
   '매콤한 두반장 소스',
   'https://source.unsplash.com/400x300/?mapo+tofu',
   ARRAY['두부', '돼지고기', '두반장', '쌀'], ARRAY['대두'], 'MANUAL', true);

-- 검증:
-- SELECT r.name, r.lat, r.lng, COUNT(mi.id) AS menu_count,
--        COUNT(mi.image_url) AS image_count
-- FROM restaurants r
-- LEFT JOIN menu_items mi ON mi.restaurant_id = r.id
-- WHERE r.id::text IN (
--   'cccccccc-cccc-cccc-cccc-cccccccccccc',
--   'dddddddd-dddd-dddd-dddd-dddddddddddd',
--   'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
--   'ffffffff-ffff-ffff-ffff-ffffffffffff',
--   '99999999-9999-9999-9999-999999999999'
-- )
-- GROUP BY r.name, r.lat, r.lng
-- ORDER BY r.name;
