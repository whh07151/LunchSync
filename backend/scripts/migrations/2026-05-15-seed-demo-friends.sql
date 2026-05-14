-- ══════════════════════════════════════════════════════════
-- 시드: 가상 친구 관계 양방향 매칭 (2026-05-15)
--
-- 배경:
--   2026-05-15-seed-diverse-users.sql 로 가상 손님 5명이 생기면
--   친구 시스템(member_select 화면)에서 친구 0명 상태로 노출됨.
--   배민/쿠팡이츠는 친구가 아니지만 캐치테이블/테이블링은 친구 단위로
--   예약을 묶음 → LunchSync 도 친구 4~6명 정도가 자연스러운 노출 단위.
--
-- 정책 (friends.service.ts 와 1:1 일치):
--   친구 한 명 추가 = (A→B) + (B→A) 두 row INSERT (양방향)
--   ON CONFLICT (user_id, friend_user_id) DO NOTHING — UNIQUE 위반 회피
--
-- 친구 관계 (가상 — 같은 org 위주 + 약간의 cross-org):
--   ── 한성대 trio (1↔2 캡스톤동료, 1↔5 startup협업)
--   ── 네이버↔카카오 (2개 회사 친구)
--   ── demo.customer (기존)도 1번 한성대생과 친구로 묶음
--
-- 안전성:
--   ▸ ON CONFLICT DO NOTHING — 재실행 안전
--   ▸ users 시드가 먼저 실행되어야 FK 위반 없음 (실행 순서: users → friends)
-- ══════════════════════════════════════════════════════════

BEGIN;

-- ── 친구쌍 정의 (단방향 5쌍 = 양방향 10 row, 명시 INSERT) ─────
-- 가독성/안전성 위해 양방향을 명시적으로 펼친 10 row INSERT.
-- ON CONFLICT 로 재실행 안전.
INSERT INTO friends (user_id, friend_user_id) VALUES
  -- 1 ↔ 2
  ('eeeeeeee-1111-4000-8000-000000000001'::uuid,
   'eeeeeeee-1111-4000-8000-000000000002'::uuid),
  ('eeeeeeee-1111-4000-8000-000000000002'::uuid,
   'eeeeeeee-1111-4000-8000-000000000001'::uuid),
  -- 1 ↔ 5
  ('eeeeeeee-1111-4000-8000-000000000001'::uuid,
   'eeeeeeee-1111-4000-8000-000000000005'::uuid),
  ('eeeeeeee-1111-4000-8000-000000000005'::uuid,
   'eeeeeeee-1111-4000-8000-000000000001'::uuid),
  -- 3 ↔ 4
  ('eeeeeeee-1111-4000-8000-000000000003'::uuid,
   'eeeeeeee-1111-4000-8000-000000000004'::uuid),
  ('eeeeeeee-1111-4000-8000-000000000004'::uuid,
   'eeeeeeee-1111-4000-8000-000000000003'::uuid),
  -- 2 ↔ 3
  ('eeeeeeee-1111-4000-8000-000000000002'::uuid,
   'eeeeeeee-1111-4000-8000-000000000003'::uuid),
  ('eeeeeeee-1111-4000-8000-000000000003'::uuid,
   'eeeeeeee-1111-4000-8000-000000000002'::uuid),
  -- 4 ↔ 5
  ('eeeeeeee-1111-4000-8000-000000000004'::uuid,
   'eeeeeeee-1111-4000-8000-000000000005'::uuid),
  ('eeeeeeee-1111-4000-8000-000000000005'::uuid,
   'eeeeeeee-1111-4000-8000-000000000004'::uuid)
ON CONFLICT (user_id, friend_user_id) DO NOTHING;

-- ── 기존 demo.customer 와 손님1 친구 매칭 (선택 — 존재 시) ───
-- demo.customer 가 이메일로 시드된 경우 친구 1쌍 추가
DO $$
DECLARE
  v_demo_id UUID;
BEGIN
  SELECT id INTO v_demo_id FROM users
    WHERE email = 'demo.customer@lunchsync.test' LIMIT 1;

  IF v_demo_id IS NOT NULL THEN
    INSERT INTO friends (user_id, friend_user_id) VALUES
      (v_demo_id, 'eeeeeeee-1111-4000-8000-000000000001'::uuid),
      ('eeeeeeee-1111-4000-8000-000000000001'::uuid, v_demo_id)
    ON CONFLICT (user_id, friend_user_id) DO NOTHING;
  END IF;
END $$;

COMMIT;

-- ── 검증 ─────────────────────────────────────────────────
-- 1) 친구 row 총 개수 (10 또는 12 — demo.customer 매칭 시)
-- SELECT COUNT(*) FROM friends
-- WHERE user_id::text LIKE 'eeeeeeee-%' OR friend_user_id::text LIKE 'eeeeeeee-%';
--
-- 2) 사용자별 친구 수 (양방향이므로 user_id 기준 GROUP BY)
-- SELECT u.name, COUNT(f.id) AS friend_count
-- FROM users u LEFT JOIN friends f ON f.user_id = u.id
-- WHERE u.id::text LIKE 'eeeeeeee-1111-%'
-- GROUP BY u.id, u.name ORDER BY friend_count DESC;
