-- ══════════════════════════════════════════════════════════
-- 파일 역할: menu_items 완전중복 행 정리 (데이터 정합성 복구)
--
-- 배경 (2026-05-31 자율 점검):
--   일부 식당의 메뉴가 동일 항목으로 대량 중복돼 있다. 손님 앱
--   "결정된 식당" 메뉴 화면에서 "음료수 3,000원" 이 420개 반복 표시되는
--   사고가 확인됐다.
--
-- 원인 분석 (실제 코드 근거):
--   - 정상 크롤 경로(crawl.service.ts persistRestaurant:457-460,
--     fallbackGenerateVirtualRestaurants:634-637)는 둘 다
--     `menu_items.delete().eq('restaurant_id', id)` 후 INSERT 하므로
--     중복이 쌓이지 않는다. → 정상 경로는 무죄.
--   - 손님 menu_screen.dart 도 widget.restaurantId 로만 조회(하드코딩 제거됨).
--   - 따라서 중복은 과거 잔재(초기 시드 반복 실행 / 정상 경로 밖 수동 INSERT)로
--     특정 식당에 동일 (restaurant_id, name, price) 행이 누적된 것.
--
-- 이 마이그레이션이 하는 일:
--   같은 (restaurant_id, name, price) 를 가진 행 중 가장 먼저 생성된 1행만
--   남기고 나머지를 삭제한다. → 음료수 420개 → 1개로 정리되고, 다른 식당의
--   누적 중복도 함께 정합화된다.
--
-- 안전성:
--   - 완전 동일(식당+이름+가격)한 행만 대상 → 의미 있는 서로 다른 메뉴는 보존.
--   - created_at 이 가장 빠른 행(동률이면 id 작은 행)을 유지 → 원본 메뉴 보존.
--   - 멱등: 여러 번 실행해도 추가 변화 없음(이미 1개면 삭제 대상 없음).
--   - 트랜잭션 단위로 안전하게 실행 가능.
--
-- 실행 방법:
--   1) 먼저 아래 "사전 점검" 쿼리로 중복 규모를 확인(삭제 전 백업 판단).
--   2) DELETE 실행.
--   3) "사후 검증" 쿼리로 중복 0건 확인.
-- ══════════════════════════════════════════════════════════

-- ── 사전 점검: 중복이 가장 심한 식당 TOP 20 ──────────────────
--   (삭제 전에 규모를 눈으로 확인. 결과가 비어있으면 정리할 중복 없음)
-- SELECT restaurant_id, name, price, COUNT(*) AS dup_count
-- FROM menu_items
-- GROUP BY restaurant_id, name, price
-- HAVING COUNT(*) > 1
-- ORDER BY dup_count DESC
-- LIMIT 20;

-- ── 정리: 완전중복 행 삭제 (가장 오래된 1행만 유지) ──────────
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY restaurant_id, name, price
      ORDER BY created_at ASC, id ASC
    ) AS rn
  FROM menu_items
)
DELETE FROM menu_items
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

-- ── 사후 검증: 남은 완전중복 0건이어야 정상 ──────────────────
-- SELECT COUNT(*) AS remaining_dup_groups FROM (
--   SELECT 1 FROM menu_items
--   GROUP BY restaurant_id, name, price
--   HAVING COUNT(*) > 1
-- ) t;
