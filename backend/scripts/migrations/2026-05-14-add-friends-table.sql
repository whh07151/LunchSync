-- ══════════════════════════════════════════════════════════
-- 마이그레이션: friends 테이블 추가 (2026-05-14)
--
-- 목적:
--   사장님 시연 피드백 "친구 목록이 사라져있고" — bd18a19 에서
--   mock 친구 8명을 제거했지만 진짜 친구 시스템이 미구현이었음.
--   초대 코드 흐름만으론 사전 멤버 선택이 불가능 → MVP 친구 시스템 도입.
--
-- 모델 (단순화 — PENDING/ACCEPTED 2단계 미적용, 즉시 양방향 매칭):
--   - user_id        주인 (CASCADE)
--   - friend_user_id 친구 (CASCADE)
--   - created_at     맺은 시각
--   - UNIQUE(user_id, friend_user_id) — 중복 방지
--   - CHECK user_id <> friend_user_id — 자기 자신 친구 금지
--
-- 양방향 INSERT 정책:
--   서비스 단(friends.service.ts addFriendByEmail)에서 친구 한 명을 추가하면
--   (user_id=A, friend_user_id=B) 와 (user_id=B, friend_user_id=A) 두 row 를
--   동시 INSERT — 양쪽 모두 친구 목록에서 상대방이 보이도록.
--
-- 안전성:
--   - IF NOT EXISTS — 재실행 안전
--   - FK CASCADE — 사용자 탈퇴 시 자동 정리
--   - UNIQUE + CHECK 제약 — 데이터 정합
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → Run
-- ══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS friends (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  friend_user_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, friend_user_id),
  CHECK (user_id <> friend_user_id)
);

-- 친구 목록 조회를 빠르게 (member_select 화면 진입 시 GET /friends 호출)
CREATE INDEX IF NOT EXISTS idx_friends_user_id_created
  ON friends (user_id, created_at DESC);

-- 검증:
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name='friends' ORDER BY ordinal_position;
