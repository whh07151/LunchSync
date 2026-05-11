-- ══════════════════════════════════════════════════════════
-- 마이그레이션: 세션 생성 원자성 RPC (2026-05-14)
--
-- 목적:
--   Supabase JS 클라이언트는 트랜잭션을 직접 지원하지 않음.
--   세션 생성은 sessions + session_members 두 테이블 INSERT 가 함께 성공해야 정합성 유지.
--   기존 흐름: 두 번 INSERT — 중간에 실패하면 세션만 남고 호스트 미멤버 상태.
--   개선: PostgreSQL 함수로 묶어 단일 트랜잭션 보장 (PostgreSQL 함수는 기본적으로 ACID).
--
-- 호출 패턴 (NestJS):
--   const { data, error } = await this.supabase.client
--     .rpc('create_session_with_host_member', { p_name, p_created_by, ... });
--
-- 반환:
--   생성된 세션 행 + memberCount=1 + createdBy 객체 (camelCase)
--
-- 안전성:
--   - CREATE OR REPLACE — 재실행 안전
--   - SECURITY DEFINER 미사용 — service_role 키로만 호출되므로 일반 INVOKER 권한 충분
-- ══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION create_session_with_host_member(
  p_name TEXT,
  p_created_by UUID,
  p_scheduled_at TIMESTAMPTZ DEFAULT NULL,
  p_radius INT DEFAULT NULL,
  p_budget INT DEFAULT NULL,
  p_return_minutes INT DEFAULT NULL,
  p_memo TEXT DEFAULT NULL,
  p_lat NUMERIC DEFAULT NULL,
  p_lng NUMERIC DEFAULT NULL
) RETURNS JSON AS $$
DECLARE
  v_session_id UUID;
  v_creator_name TEXT;
  v_result JSON;
BEGIN
  -- 1) sessions INSERT
  INSERT INTO sessions (
    name, created_by, scheduled_at,
    radius, budget, return_minutes, memo, lat, lng
  )
  VALUES (
    p_name, p_created_by, p_scheduled_at,
    p_radius, p_budget, p_return_minutes, p_memo, p_lat, p_lng
  )
  RETURNING id INTO v_session_id;

  -- 2) session_members INSERT (호스트 자동 등록)
  --    실패 시 PostgreSQL 함수 단위 트랜잭션이 전체 롤백
  INSERT INTO session_members (session_id, user_id)
  VALUES (v_session_id, p_created_by);

  -- 3) creator 이름 조회 (응답 보강용)
  SELECT name INTO v_creator_name FROM users WHERE id = p_created_by;

  -- 4) 응답 JSON 조립 (camelCase — NestJS 응답 포맷과 호환)
  SELECT json_build_object(
    'id', s.id,
    'name', s.name,
    'status', s.status,
    'scheduledAt', s.scheduled_at,
    'radius', s.radius,
    'budget', s.budget,
    'returnMinutes', s.return_minutes,
    'memo', s.memo,
    'lat', s.lat,
    'lng', s.lng,
    'memberCount', 1,
    'createdBy', json_build_object(
      'id', p_created_by,
      'name', v_creator_name
    )
  ) INTO v_result
  FROM sessions s
  WHERE s.id = v_session_id;

  RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- 검증:
-- SELECT create_session_with_host_member(
--   '테스트 세션',
--   '00000000-0000-0000-0000-000000000001'::UUID,
--   NULL, 500, 12000, 30, '메모', 37.5, 127.0
-- );
