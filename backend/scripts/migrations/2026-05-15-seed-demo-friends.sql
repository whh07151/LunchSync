-- ══════════════════════════════════════════════════════════
-- 시드: 시연용 가상 친구 5명 + 사장님(우현호)과 자동 친구 매칭
--
-- 작성일: 2026-05-15
-- 배경:
--   사장님 시연 피드백 — bd18a19 에서 mock 친구 8명 제거 후 어색.
--   진짜 친구 시스템(2026-05-14-add-friends-table)은 이미 구축됐지만
--   친구가 0명이라 시연 어색함. 시연용 가상 친구 5명을 DB 에 INSERT 하고
--   사장님(이름=우현호) 와 양방향 friends 매칭.
--
-- 안전성:
--   - ON CONFLICT DO NOTHING — 재실행 안전 (이미 있으면 건너뜀)
--   - 양방향 INSERT (호스트→친구 / 친구→호스트)
--   - 사장님 매칭은 name='우현호' 의 가장 최근 사용자 (LIMIT 1) — 동명이인 방어
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → Run
-- ══════════════════════════════════════════════════════════

BEGIN;

-- ── 1. 가상 친구 5명 INSERT ────────────────────────────────
-- 한성대학교 점심 동료 컨셉. CUSTOMER 역할 / APPROVED 상태.
-- kakao_id 는 NOT NULL 제약(레거시) 우회용 더미값.
INSERT INTO users (id, email, name, role, status, kakao_id, created_at)
VALUES
  ('11111111-aaaa-aaaa-aaaa-111111111111', 'demo.minjun@lunchsync.test',  '김민준', 'CUSTOMER', 'APPROVED', 'demo_minjun_seed',  NOW()),
  ('22222222-aaaa-aaaa-aaaa-222222222222', 'demo.jihyo@lunchsync.test',   '박지효', 'CUSTOMER', 'APPROVED', 'demo_jihyo_seed',   NOW()),
  ('33333333-aaaa-aaaa-aaaa-333333333333', 'demo.dayeon@lunchsync.test',  '이다연', 'CUSTOMER', 'APPROVED', 'demo_dayeon_seed',  NOW()),
  ('44444444-aaaa-aaaa-aaaa-444444444444', 'demo.taehwan@lunchsync.test', '안태환', 'CUSTOMER', 'APPROVED', 'demo_taehwan_seed', NOW()),
  ('55555555-aaaa-aaaa-aaaa-555555555555', 'demo.seoyeon@lunchsync.test', '최서연', 'CUSTOMER', 'APPROVED', 'demo_seoyeon_seed', NOW())
ON CONFLICT (id) DO NOTHING;

-- ── 2. 사장님(우현호) 과 친구 매칭 — 호스트→친구 방향 ─────
-- 동명이인 방어: 가장 최근 생성 사용자 1명만 선택.
WITH host AS (
  SELECT id FROM users WHERE name = '우현호' ORDER BY created_at DESC LIMIT 1
)
INSERT INTO friends (user_id, friend_user_id)
SELECT host.id, f.id
FROM host, users f
WHERE f.id IN (
  '11111111-aaaa-aaaa-aaaa-111111111111',
  '22222222-aaaa-aaaa-aaaa-222222222222',
  '33333333-aaaa-aaaa-aaaa-333333333333',
  '44444444-aaaa-aaaa-aaaa-444444444444',
  '55555555-aaaa-aaaa-aaaa-555555555555'
)
ON CONFLICT (user_id, friend_user_id) DO NOTHING;

-- ── 3. 사장님(우현호) 과 친구 매칭 — 친구→호스트 방향 ────
WITH host AS (
  SELECT id FROM users WHERE name = '우현호' ORDER BY created_at DESC LIMIT 1
)
INSERT INTO friends (user_id, friend_user_id)
SELECT f.id, host.id
FROM host, users f
WHERE f.id IN (
  '11111111-aaaa-aaaa-aaaa-111111111111',
  '22222222-aaaa-aaaa-aaaa-222222222222',
  '33333333-aaaa-aaaa-aaaa-333333333333',
  '44444444-aaaa-aaaa-aaaa-444444444444',
  '55555555-aaaa-aaaa-aaaa-555555555555'
)
ON CONFLICT (user_id, friend_user_id) DO NOTHING;

COMMIT;

-- ── 검증 (실행 후 결과 확인용) ──────────────────────────────
-- SELECT u.name, COUNT(f.id) AS friend_count
-- FROM users u
-- LEFT JOIN friends f ON f.user_id = u.id
-- WHERE u.name = '우현호' OR u.email LIKE 'demo%@lunchsync.test'
-- GROUP BY u.name;
--
-- 기대: 우현호=5명, 김민준=1명, 박지효=1명, ...
