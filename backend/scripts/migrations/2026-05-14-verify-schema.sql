-- ══════════════════════════════════════════════════════════
-- 스키마 검증 쿼리 (2026-05-14)
--
-- 목적:
--   백엔드 코드가 사용하는 컬럼/테이블/RPC 함수가 실제로 DB 에 존재하는지
--   한 번에 확인. silent failure (PostgREST 가 누락 컬럼을 조용히 무시) 차단.
--
-- 사용법:
--   Supabase Dashboard → SQL Editor → 전체 붙여넣기 → Run.
--   세 결과 셋이 출력됨. 누락된 자원이 있으면 해당 마이그레이션 실행 필요.
--
-- 검증 대상:
--   1) 컬럼: restaurants(rating, image_url), users(fcm_token),
--            sessions(radius, budget, return_minutes, memo)
--   2) 테이블: pos_seats, pos_reservations
--   3) RPC 함수: delete_session_cascade, create_order_with_items,
--                create_session_with_host_member
-- ══════════════════════════════════════════════════════════

-- ── 1) 핵심 컬럼 존재 확인 ────────────────────────────────
SELECT
  table_name,
  column_name,
  data_type,
  'OK' AS status
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
       (table_name = 'restaurants' AND column_name IN ('rating', 'image_url'))
    OR (table_name = 'users'       AND column_name IN ('fcm_token'))
    OR (table_name = 'sessions'    AND column_name IN ('radius', 'budget', 'return_minutes', 'memo'))
  )
ORDER BY table_name, column_name;

-- ── 2) 핵심 테이블 존재 확인 ──────────────────────────────
SELECT
  table_name,
  'OK' AS status
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('pos_seats', 'pos_reservations')
ORDER BY table_name;

-- ── 3) 핵심 RPC 함수 존재 확인 ────────────────────────────
SELECT
  routine_name,
  routine_type,
  'OK' AS status
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'delete_session_cascade',
    'create_order_with_items',
    'create_session_with_host_member',
    'check_schema_resources'
  )
ORDER BY routine_name;

-- ── 4) order_status ENUM 값 확인 (2026-05-15 단계 2) ──────
-- 확장 후 8개 값 모두 존재해야 함.
-- 누락된 값 있으면 2026-05-15-add-order-status-enum.sql 실행 필요.
SELECT enumlabel AS enum_value
FROM pg_enum
WHERE enumtypid = (SELECT oid FROM pg_type WHERE typname = 'order_status')
ORDER BY enumsortorder;

-- ── 4) 기대값 ────────────────────────────────────────────
-- 1) 컬럼 7개: restaurants.image_url / restaurants.rating /
--             users.fcm_token / sessions.radius / sessions.budget /
--             sessions.return_minutes / sessions.memo
-- 2) 테이블 2개: pos_reservations / pos_seats
-- 3) 함수 4개: check_schema_resources / create_order_with_items /
--             create_session_with_host_member / delete_session_cascade
--
-- 누락된 행이 있으면 해당 마이그레이션 SQL 을 Dashboard 에서 실행:
--   - restaurants.rating → 2026-05-14-add-rating-column.sql
--   - restaurants.image_url → 2026-05-14-fill-empty-image-urls.sql (ALTER 포함)
--   - users.fcm_token → 2026-05-14-add-fcm-token.sql
--   - sessions.radius/budget/return_minutes/memo → ※ 마이그레이션 부재! 사장님 확인 필요
--   - pos_seats → 2026-05-14-add-pos-tables.sql
--   - pos_reservations → 2026-05-14-add-pos-reservations.sql (이번 복원)
--   - RPC 함수 4종 → 같은 이름의 SQL 파일
--     (check_schema_resources → 2026-05-14-schema-introspection-rpc.sql)
