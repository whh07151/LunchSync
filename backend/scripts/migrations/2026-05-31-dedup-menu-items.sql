-- ══════════════════════════════════════════════════════════
-- 파일 역할: menu_items 완전중복 행 정리 (데이터 정합성 복구)
--
-- 배경 (2026-05-31 자율 점검 + 라이브 실행):
--   일부 식당의 메뉴가 동일 항목으로 대량 중복돼 있었다. 손님 앱
--   "결정된 식당" 메뉴 화면에서 "음료수 3,000원" 이 420개 반복 표시되는
--   사고가 확인됐다. 라이브 점검 결과 완전중복 그룹 46개 존재.
--
-- 원인 분석 (실제 코드 근거):
--   - 정상 크롤 경로(crawl.service.ts persistRestaurant:457-460,
--     fallbackGenerateVirtualRestaurants:634-637)는 둘 다
--     menu_items.delete().eq('restaurant_id', id) 후 INSERT 하므로
--     중복이 쌓이지 않는다. → 정상 경로 무죄.
--   - 손님 menu_screen.dart 도 widget.restaurantId 로만 조회(하드코딩 제거됨).
--   - 따라서 중복은 과거 잔재(초기 시드 반복 실행 / 정상 경로 밖 수동 INSERT).
--
-- ⚠️ 중요 제약 (라이브 실행으로 발견):
--   1) menu_items 에는 created_at 컬럼이 없다 → 정렬은 시스템 컬럼 ctid 사용.
--   2) menu_items.id 를 참조하는 FK 가 3개 있다:
--        cart_items.menu_item_id / order_items.menu_item_id /
--        tournament_results.winner_menu_id
--      → 중복 행을 그냥 DELETE 하면 FK(23503) 위반. 삭제 전에 참조를
--        "유지할 행(keeper)" 으로 재지정(UPDATE) 한 뒤 삭제해야 한다.
--
-- 동작:
--   각 (restaurant_id, name, price) 그룹에서 ctid 가 가장 앞선 1행(keeper)만
--   남기고, 나머지 중복 행을 참조하는 3개 FK 를 keeper 로 재지정 후 삭제한다.
--
-- 안전성:
--   - 완전 동일(식당+이름+가격) 행만 대상 → 서로 다른 메뉴는 보존.
--   - 재지정은 "같은 메뉴" 로 옮기는 것이라 주문/카트/토너먼트 의미 보존.
--   - 전체를 단일 트랜잭션(BEGIN/COMMIT)으로 — 중간 실패 시 자동 롤백.
--   - 멱등: 재실행해도 이미 1개면 추가 변화 없음.
--
-- 실행: Supabase Dashboard → SQL Editor 에 아래 전체를 붙여 실행.
-- 검증: 맨 아래 사후검증 쿼리가 0 이면 정리 완료.
-- ══════════════════════════════════════════════════════════

-- ── 사전 점검(선택): 중복이 심한 식당 TOP 20 ─────────────────
-- SELECT restaurant_id, name, price, COUNT(*) AS dup_count
-- FROM menu_items
-- GROUP BY restaurant_id, name, price
-- HAVING COUNT(*) > 1
-- ORDER BY dup_count DESC
-- LIMIT 20;

-- ── 정리: FK 재지정 후 완전중복 삭제 (단일 트랜잭션) ──────────
BEGIN;

-- ① cart_items 재지정 (삭제될 중복 → keeper)
WITH ranked AS (
  SELECT id,
    FIRST_VALUE(id) OVER (PARTITION BY restaurant_id, name, price ORDER BY ctid) AS keeper_id,
    ROW_NUMBER()    OVER (PARTITION BY restaurant_id, name, price ORDER BY ctid) AS rn
  FROM menu_items
)
UPDATE cart_items c
SET menu_item_id = r.keeper_id
FROM ranked r
WHERE c.menu_item_id = r.id AND r.rn > 1;

-- ② order_items 재지정
WITH ranked AS (
  SELECT id,
    FIRST_VALUE(id) OVER (PARTITION BY restaurant_id, name, price ORDER BY ctid) AS keeper_id,
    ROW_NUMBER()    OVER (PARTITION BY restaurant_id, name, price ORDER BY ctid) AS rn
  FROM menu_items
)
UPDATE order_items o
SET menu_item_id = r.keeper_id
FROM ranked r
WHERE o.menu_item_id = r.id AND r.rn > 1;

-- ③ tournament_results 재지정
WITH ranked AS (
  SELECT id,
    FIRST_VALUE(id) OVER (PARTITION BY restaurant_id, name, price ORDER BY ctid) AS keeper_id,
    ROW_NUMBER()    OVER (PARTITION BY restaurant_id, name, price ORDER BY ctid) AS rn
  FROM menu_items
)
UPDATE tournament_results t
SET winner_menu_id = r.keeper_id
FROM ranked r
WHERE t.winner_menu_id = r.id AND r.rn > 1;

-- ④ 참조가 사라진 중복 행 삭제 (그룹당 ctid 첫 행만 유지)
WITH ranked AS (
  SELECT ctid,
    ROW_NUMBER() OVER (PARTITION BY restaurant_id, name, price ORDER BY ctid) AS rn
  FROM menu_items
)
DELETE FROM menu_items
WHERE ctid IN (SELECT ctid FROM ranked WHERE rn > 1);

COMMIT;

-- ── 사후 검증: 남은 완전중복 그룹 수 — 0 이어야 정상 ──────────
-- SELECT COUNT(*) FROM (
--   SELECT 1 FROM menu_items
--   GROUP BY restaurant_id, name, price
--   HAVING COUNT(*) > 1
-- ) t;
