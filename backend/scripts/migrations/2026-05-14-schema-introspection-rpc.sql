-- ══════════════════════════════════════════════════════════
-- 마이그레이션: 스키마 introspection RPC (2026-05-14)
--
-- 목적:
--   NestJS 부트 시 information_schema 를 조회해 기대 자원
--   (컬럼/테이블/RPC 함수) 누락 여부를 확인하기 위한 RPC.
--
--   PostgREST 는 일반적으로 information_schema 직접 SELECT 를
--   허용하지 않으므로 service_role 키로도 안전하게 호출 가능한
--   래퍼 함수가 필요. 이 함수가 모든 검증을 JSON 으로 반환해
--   클라이언트 측 SQL 구성 부담을 0 으로.
--
-- 배경 (2026-05-14 image_url silent failure 사고):
--   PostgREST 는 select 에 누락된 컬럼이 있어도 에러를 내지 않고
--   조용히 무시 → 코드는 정상, DB 응답은 빈 칸. 빌드/analyze 로는
--   잡을 수 없어 부트 시 명시적 검증이 유일한 안전망.
--
-- 반환 JSON 스키마:
--   {
--     "columns":   [{ "table": "...", "column": "...", "present": true|false }, ...],
--     "tables":    [{ "table": "...", "present": true|false }, ...],
--     "functions": [{ "name": "...",  "present": true|false }, ...]
--   }
--
-- 호출 패턴 (NestJS):
--   const { data, error } = await this.supabase.client.rpc('check_schema_resources');
--
-- 안전성:
--   - CREATE OR REPLACE 멱등
--   - SECURITY DEFINER 사용 — anon/authenticated 가 호출해도 information_schema
--     스캔 권한이 보장됨 (백엔드는 service_role 사용이지만 일관성 차원)
--   - 읽기 전용 — 어떤 DML 도 수행하지 않음
-- ══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION check_schema_resources()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_columns   JSON;
  v_tables    JSON;
  v_functions JSON;
BEGIN
  -- ── 1) 기대 컬럼 7개 ─────────────────────────────────────
  --    (table_name, column_name) 쌍을 VALUES 로 정의 → LEFT JOIN
  --    information_schema.columns 로 존재 여부 확인.
  WITH expected(table_name, column_name) AS (
    VALUES
      ('restaurants', 'image_url'),
      ('restaurants', 'rating'),
      ('users',       'fcm_token'),
      ('sessions',    'radius'),
      ('sessions',    'budget'),
      ('sessions',    'return_minutes'),
      ('sessions',    'memo')
  )
  SELECT json_agg(
           json_build_object(
             'table',   e.table_name,
             'column',  e.column_name,
             'present', c.column_name IS NOT NULL
           )
           ORDER BY e.table_name, e.column_name
         )
    INTO v_columns
  FROM expected e
  LEFT JOIN information_schema.columns c
    ON c.table_schema = 'public'
   AND c.table_name   = e.table_name
   AND c.column_name  = e.column_name;

  -- ── 2) 기대 테이블 2개 ───────────────────────────────────
  WITH expected(table_name) AS (
    VALUES
      ('pos_seats'),
      ('pos_reservations')
  )
  SELECT json_agg(
           json_build_object(
             'table',   e.table_name,
             'present', t.table_name IS NOT NULL
           )
           ORDER BY e.table_name
         )
    INTO v_tables
  FROM expected e
  LEFT JOIN information_schema.tables t
    ON t.table_schema = 'public'
   AND t.table_name   = e.table_name;

  -- ── 3) 기대 RPC 함수 3개 ─────────────────────────────────
  WITH expected(routine_name) AS (
    VALUES
      ('delete_session_cascade'),
      ('create_order_with_items'),
      ('create_session_with_host_member')
  )
  SELECT json_agg(
           json_build_object(
             'name',    e.routine_name,
             'present', r.routine_name IS NOT NULL
           )
           ORDER BY e.routine_name
         )
    INTO v_functions
  FROM expected e
  LEFT JOIN information_schema.routines r
    ON r.routine_schema = 'public'
   AND r.routine_name   = e.routine_name;

  -- ── 4) 최종 응답 조립 ───────────────────────────────────
  RETURN json_build_object(
    'columns',   v_columns,
    'tables',    v_tables,
    'functions', v_functions
  );
END;
$$;

-- 검증:
-- SELECT check_schema_resources();
--   → JSON 객체 3개 키 (columns/tables/functions), present:false 인 자원이
--     하나라도 있으면 해당 마이그레이션 미적용.
