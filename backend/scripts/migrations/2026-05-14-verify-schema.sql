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
       -- 2026-05-31 WOW#1: 사장님 "오늘의 한 줄" 컬럼 검증 추가.
       --   todays_note 가 누락되면 손님 추천 카드의 노란 띠/점수 가중치가
       --   silent 하게 사라져 사장이 입력해도 "내 가게가 안 보이는" 회귀.
       (table_name = 'restaurants' AND column_name IN ('rating', 'image_url', 'todays_note'))
    OR (table_name = 'users'       AND column_name IN ('fcm_token'))
    OR (table_name = 'sessions'    AND column_name IN ('radius', 'budget', 'return_minutes', 'memo'))
    -- 2026-05-31 회귀 감사 4회차: 별점/리뷰 컬럼이 silent 누락되는 경우
    -- 주문 상세 화면의 별점 카드가 항상 null 로 반환되어 추적 어려움.
    OR (table_name = 'orders'      AND column_name IN ('review_score', 'review_text', 'review_at'))
  )
ORDER BY table_name, column_name;

-- ── 2) 핵심 테이블 존재 확인 ──────────────────────────────
-- 2026-05-31 WOW#9: tournament_results 추가.
--   누락 시 POST /api/tournaments 가 PostgREST 단에서 silent 실패하여
--   "주간 트렌딩 식당" 섹션이 영구히 0개 → 홈에서 섹션 자체가 안 보임.
SELECT
  table_name,
  'OK' AS status
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('pos_seats', 'pos_reservations', 'tournament_results')
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
-- 1) 컬럼 8개: restaurants.image_url / restaurants.rating /
--             restaurants.todays_note (2026-05-31 WOW#1) /
--             users.fcm_token / sessions.radius / sessions.budget /
--             sessions.return_minutes / sessions.memo
-- 2) 테이블 3개: pos_reservations / pos_seats / tournament_results (2026-05-31 WOW#9)
-- 3) 함수 4개: check_schema_resources / create_order_with_items /
--             create_session_with_host_member / delete_session_cascade
--
-- 누락된 행이 있으면 해당 마이그레이션 SQL 을 Dashboard 에서 실행:
--   - restaurants.rating → 2026-05-14-add-rating-column.sql
--   - restaurants.image_url → 2026-05-14-fill-empty-image-urls.sql (ALTER 포함)
--   - users.fcm_token → 2026-05-14-add-fcm-token.sql
--   - sessions.radius/budget/return_minutes/memo → 2026-05-14-ensure-sessions-columns.sql
--   - pos_seats → 2026-05-14-add-pos-tables.sql
--   - pos_reservations → 2026-05-14-add-pos-reservations.sql (이번 복원)
--   - tournament_results → 2026-05-31-create-tournament-results.sql (WOW#9 신규)
--   - RPC 함수 4종 → 같은 이름의 SQL 파일
--     (check_schema_resources → 2026-05-14-schema-introspection-rpc.sql)
