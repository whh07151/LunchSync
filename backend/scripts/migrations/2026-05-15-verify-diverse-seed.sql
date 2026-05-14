-- ══════════════════════════════════════════════════════════
-- 시드 검증 쿼리 (2026-05-15)
--
-- 목적:
--   2026-05-15-seed-diverse-restaurants.sql, seed-diverse-users.sql,
--   seed-demo-friends.sql, seed-demo-orders-reviews.sql 4 개 시드가
--   정상 적용됐는지 한 번에 확인.
--
-- 실행 순서:
--   1) 2026-05-15-seed-diverse-restaurants.sql
--   2) 2026-05-15-seed-diverse-users.sql
--   3) 2026-05-15-seed-demo-friends.sql
--   4) 2026-05-15-seed-demo-orders-reviews.sql
--   5) (본 파일) — 검증 SELECT 만 모음
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → 한 번에 Run
-- ══════════════════════════════════════════════════════════

-- ── 1) 식당 수 + 카테고리 분포 ────────────────────────────
SELECT '식당 카테고리 분포' AS check_name;
SELECT category, COUNT(*) AS cnt
FROM restaurants
WHERE id::text LIKE 'dddddddd-%'
GROUP BY category
ORDER BY cnt DESC;
-- 기대: 한식 8, 양식 6, 일식 4, 카페 4, 분식 3, 중식 3, 패스트푸드 2

-- ── 2) 가격대 분포 ────────────────────────────────────────
SELECT '가격대 분포' AS check_name;
SELECT
  CASE
    WHEN price_range < 7000 THEN '01_저가 (~6천)'
    WHEN price_range < 13000 THEN '02_중가 (7~12천)'
    WHEN price_range < 20000 THEN '03_준프리미엄 (13~19천)'
    ELSE '04_프리미엄 (20천~)'
  END AS tier,
  COUNT(*) AS cnt
FROM restaurants
WHERE id::text LIKE 'dddddddd-%'
GROUP BY tier
ORDER BY tier;

-- ── 3) 평점 분포 ──────────────────────────────────────────
SELECT '평점 분포' AS check_name;
SELECT
  CASE
    WHEN rating < 4.0 THEN '01_3점대'
    WHEN rating < 4.5 THEN '02_4.0~4.4'
    WHEN rating < 4.8 THEN '03_4.5~4.7'
    ELSE '04_4.8+'
  END AS rating_tier,
  COUNT(*) AS cnt
FROM restaurants
WHERE id::text LIKE 'dddddddd-%' AND rating IS NOT NULL
GROUP BY rating_tier
ORDER BY rating_tier;

-- ── 4) 식당별 메뉴 수 ─────────────────────────────────────
SELECT '식당별 메뉴 수 (상위 10개)' AS check_name;
SELECT r.name, COUNT(mi.id) AS menu_count
FROM restaurants r
LEFT JOIN menu_items mi ON mi.restaurant_id = r.id
WHERE r.id::text LIKE 'dddddddd-%'
GROUP BY r.id, r.name
ORDER BY menu_count DESC
LIMIT 10;
-- 기대: 모든 식당이 4~6개 메뉴 보유

-- ── 5) 메뉴 카테고리 분포 ─────────────────────────────────
SELECT '메뉴 카테고리 분포 (dddd 식당)' AS check_name;
SELECT mi.category, COUNT(*) AS cnt
FROM menu_items mi
JOIN restaurants r ON r.id = mi.restaurant_id
WHERE r.id::text LIKE 'dddddddd-%'
GROUP BY mi.category
ORDER BY cnt DESC;

-- ── 6) 사용자 시드 (role 별) ──────────────────────────────
SELECT '시드 사용자 (role 별)' AS check_name;
SELECT role, status, COUNT(*) AS cnt
FROM users
WHERE id::text LIKE 'eeeeeeee-%'
GROUP BY role, status
ORDER BY role, status;
-- 기대: CUSTOMER/APPROVED 5, OWNER/APPROVED 3

-- ── 7) 손님 org 분포 ──────────────────────────────────────
SELECT '시드 손님 org' AS check_name;
SELECT org, name, budget, speed
FROM users
WHERE id::text LIKE 'eeeeeeee-1111-%'
ORDER BY id;

-- ── 8) 사장-식당 매핑 ─────────────────────────────────────
SELECT '시드 사장 ↔ 운영 식당' AS check_name;
SELECT u.name AS owner_name, u.email, r.name AS restaurant_name
FROM users u
LEFT JOIN restaurants r ON r.id = u.restaurant_id
WHERE u.id::text LIKE 'eeeeeeee-2222-%'
ORDER BY u.id;

-- ── 9) 친구 관계 ──────────────────────────────────────────
SELECT '시드 친구 관계 (사용자별 친구 수)' AS check_name;
SELECT u.name, COUNT(f.id) AS friend_count
FROM users u
LEFT JOIN friends f ON f.user_id = u.id
WHERE u.id::text LIKE 'eeeeeeee-1111-%'
GROUP BY u.id, u.name
ORDER BY friend_count DESC;
-- 기대: 각 손님 2~4명의 친구 보유

-- ── 10) 주문 상태 분포 ───────────────────────────────────
SELECT '주문 상태 분포' AS check_name;
SELECT status, COUNT(*) AS cnt, SUM(total_price) AS revenue
FROM orders
WHERE id::text LIKE 'ffffffff-1111-%'
GROUP BY status
ORDER BY status;
-- 기대: PAID 5, PREPARING 5, READY 5, COMPLETED 12, CANCELLED 3

-- ── 11) 결제수단별 매출 ──────────────────────────────────
SELECT '결제수단별 매출 (사장 통계 화면 핵심)' AS check_name;
SELECT
  payment_method,
  COUNT(*) AS orders_cnt,
  SUM(total_price) AS revenue
FROM orders
WHERE id::text LIKE 'ffffffff-1111-%'
  AND status NOT IN ('CANCELLED')
GROUP BY payment_method
ORDER BY revenue DESC;

-- ── 12) 매장별 평균 평점 ─────────────────────────────────
SELECT '매장별 평균 평점 (리뷰 시드)' AS check_name;
SELECT
  r.name AS restaurant,
  ROUND(AVG(o.review_score)::numeric, 2) AS avg_score,
  COUNT(o.review_score) AS reviews
FROM orders o
JOIN restaurants r ON r.id = o.restaurant_id
WHERE o.id::text LIKE 'ffffffff-1111-%'
  AND o.review_score IS NOT NULL
GROUP BY r.id, r.name
ORDER BY avg_score DESC;

-- ── 13) order_items 정합성 (모든 주문에 아이템이 1개 이상) ──
SELECT 'order_items 정합성 체크' AS check_name;
SELECT
  COUNT(DISTINCT o.id) AS orders_total,
  COUNT(DISTINCT oi.order_id) AS orders_with_items
FROM orders o
LEFT JOIN order_items oi ON oi.order_id = o.id
WHERE o.id::text LIKE 'ffffffff-1111-%';
-- 기대: orders_total = orders_with_items = 30
