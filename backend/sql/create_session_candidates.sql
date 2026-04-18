-- ══════════════════════════════════════════════════════════
-- session_candidates: 투표 후보 식당 관리 테이블
--
-- AI 추천 식당 + 멤버가 직접 추가한 식당을 투표 후보로 관리
-- Supabase 대시보드 SQL Editor에서 실행
-- ══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS session_candidates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  restaurant_id UUID NOT NULL REFERENCES restaurants(id),
  added_by UUID NOT NULL REFERENCES users(id),
  source VARCHAR(20) NOT NULL DEFAULT 'MANUAL',
  -- source: 'AI' (AI 추천으로 추가) | 'MANUAL' (멤버가 직접 추가)
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(session_id, restaurant_id) -- 같은 세션에 같은 식당 중복 추가 방지
);

-- 인덱스: 세션별 후보 조회 빠르게
CREATE INDEX IF NOT EXISTS idx_session_candidates_session_id
  ON session_candidates(session_id);
