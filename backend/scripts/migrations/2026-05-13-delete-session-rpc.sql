-- ══════════════════════════════════════════════════════════
-- 마이그레이션: 세션 삭제 원자성 RPC (2026-05-13)
--
-- 목적:
--   사장님 시연 피드백 "만든 세션 삭제도 가능하게 만들고싶고" 반영.
--   세션 삭제는 votes / order_items / orders / session_members / sessions
--   다섯 테이블에 걸쳐 진행되므로 단일 트랜잭션이 필수.
--   Supabase JS 클라이언트는 트랜잭션을 직접 지원하지 않아 PostgreSQL 함수로 묶음.
--
-- 권한 정책:
--   - 호스트 검증 + 상태 검증은 NestJS 서비스(assertHost + status 화이트리스트)에서 선행.
--   - 본 함수는 "이미 검증 통과한 요청" 만 받는 안전 영역으로 가정.
--   - 그래도 함수 내부에서 status 재검증 (race condition 방지: 검증 후 트랜잭션 진입까지
--     사이에 누가 VOTING 으로 바꿔놓으면 안 되므로 함수 안에서 다시 확인).
--
-- 삭제 순서 (FK 제약 위반 방지):
--   1) order_items  ← orders.session_id 기준 (children-of-children)
--   2) orders       ← session_id 기준
--   3) votes        ← session_id 기준
--   4) session_members ← session_id 기준
--   5) sessions     ← id 기준 (최종)
--
-- 호출 패턴 (NestJS):
--   const { data, error } = await this.supabase.client
--     .rpc('delete_session_cascade', { p_session_id });
--
-- 반환:
--   { deletedSessionId, deletedAt } JSON. 행이 없으면 NotFound 처리는 호출부 책임.
--
-- 안전성:
--   - CREATE OR REPLACE — 재실행 안전
--   - 함수 내부 트랜잭션은 PostgreSQL 함수 단위로 자동 보장 (전체 성공 or 전체 롤백)
-- ══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION delete_session_cascade(
  p_session_id UUID
) RETURNS JSON AS $$
DECLARE
  v_status TEXT;
  v_deleted_at TIMESTAMPTZ;
BEGIN
  -- 0단계: 현재 status 재확인 (race condition 안전망).
  --   서비스 계층 검증과 함수 호출 사이에 다른 요청이 상태를 바꾸면
  --   "VOTING 중인데 삭제" 같은 정합성 깨짐이 발생할 수 있어 내부에서 다시 확인.
  SELECT status INTO v_status FROM sessions WHERE id = p_session_id;

  IF v_status IS NULL THEN
    -- 세션이 이미 사라진 경우 (다른 요청이 먼저 삭제) — NULL 응답으로 시그널
    RETURN NULL;
  END IF;

  IF v_status NOT IN ('WAITING', 'DONE') THEN
    -- VOTING / ORDERED 상태에서는 멤버 영향이 커서 차단.
    -- 서비스 계층에서도 같은 검증을 하지만 race condition 최후 방어선.
    RAISE EXCEPTION 'SESSION_NOT_DELETABLE: 현재 상태(%)에서는 세션을 삭제할 수 없어요.', v_status
      USING ERRCODE = 'P0001';
  END IF;

  -- 1단계: order_items 삭제 (orders 의 자식)
  --   서브쿼리로 해당 세션에 속한 모든 주문의 item 일괄 정리.
  DELETE FROM order_items
  WHERE order_id IN (
    SELECT id FROM orders WHERE session_id = p_session_id
  );

  -- 2단계: orders 삭제
  DELETE FROM orders WHERE session_id = p_session_id;

  -- 3단계: votes 삭제 (1인 1투표 UNIQUE 제약 + session_id FK)
  DELETE FROM votes WHERE session_id = p_session_id;

  -- 4단계: session_members 삭제 (호스트 포함 전원)
  DELETE FROM session_members WHERE session_id = p_session_id;

  -- 5단계: sessions 삭제 — 본체
  DELETE FROM sessions WHERE id = p_session_id;

  v_deleted_at := NOW();

  RETURN json_build_object(
    'deletedSessionId', p_session_id,
    'deletedAt', v_deleted_at
  );
END;
$$ LANGUAGE plpgsql;

-- 검증:
-- SELECT delete_session_cascade('00000000-0000-0000-0000-000000000001'::UUID);
