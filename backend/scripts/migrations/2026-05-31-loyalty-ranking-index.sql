-- ══════════════════════════════════════════════════════════
-- WOW#5 단골 랭킹 — orders 합성 인덱스 (2026-05-31)
-- ══════════════════════════════════════════════════════════
--
-- 목적:
--   GET /api/restaurants/:id/loyalty?userId=:userId 가 사용하는 카운트 쿼리,
--   그리고 pos.service.updateOrderStatus 의 COMPLETED 마일스톤 카운트가
--   같은 (user_id, restaurant_id, status='COMPLETED') 패턴을 사용한다.
--   trafficked 사용자의 식당 상세 진입 시 1회 + 매 픽업 완료 시 1회 호출되므로
--   합성 인덱스로 미리 정렬해두면 O(log N) 카운트.
--
-- 멱등성:
--   IF NOT EXISTS — 이미 존재하면 No-op.
--   기존 user_id 단일 인덱스 / restaurant_id 단일 인덱스와 충돌 X.
--
-- 적용:
--   사장님이 Supabase Dashboard SQL Editor 에서 1회 실행.
--   verify: SELECT indexname FROM pg_indexes
--           WHERE tablename = 'orders'
--             AND indexname = 'idx_orders_loyalty_count';

CREATE INDEX IF NOT EXISTS idx_orders_loyalty_count
  ON public.orders (user_id, restaurant_id, status);

-- 검증 쿼리 (선택):
--   EXPLAIN ANALYZE
--   SELECT COUNT(*) FROM orders
--   WHERE user_id = '00000000-0000-0000-0000-000000000001'
--     AND restaurant_id = '11111111-1111-1111-1111-111111111111'
--     AND status = 'COMPLETED';
--   → Index Only Scan using idx_orders_loyalty_count 가 나오면 OK.
