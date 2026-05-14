-- ══════════════════════════════════════════════════════════
-- 시드: 다양한 가상 사용자(손님 + 사장) 추가 (2026-05-15)
--
-- 배경 (사장님 요구):
--   시드 손님 1명(demo.customer)만 있어서 친구/주문/리뷰 다양성 부족.
--   배민 패턴 = "주변 사용자 N명이 이 식당을 좋아해요" 표시 가능하도록
--   org 다양한 가상 사용자 8명 + 사장 4명 추가.
--
-- 가상 손님 (5명, org 다양화):
--   demo.customer1@lunchsync.test → 한성대학교
--   demo.customer2@lunchsync.test → 서울대학교
--   demo.customer3@lunchsync.test → 네이버
--   demo.customer4@lunchsync.test → 카카오
--   demo.customer5@lunchsync.test → 스타트업
--
-- 가상 사장 (3명, 매장 운영):
--   demo.owner1@lunchsync.test → 한성대 분식왕 운영
--   demo.owner2@lunchsync.test → 강남 청국장 명가 운영
--   demo.owner3@lunchsync.test → 한성대 빈티지 카페 운영
--
-- UUID 규칙 (사용자 eeee 네임스페이스 — 충돌 회피):
--   손님: eeeeeeee-1111-4000-8000-0000000000NN
--   사장: eeeeeeee-2222-4000-8000-0000000000NN
--
-- password_hash:
--   bcrypt('Demo1234!') = $2b$10$... 고정값 사용 (모두 동일)
--   ※ Node bcrypt 10 라운드 결과, 실행 환경 무관 검증 가능
--
-- 안전성:
--   ▸ ON CONFLICT (id) DO NOTHING — 멱등 재실행
--   ▸ 사장님 실 데이터 영향 0 (이메일/UUID 네임스페이스 분리)
--   ▸ kakao_id NOT NULL 레거시 대비 더미값 부여
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → Run
-- ══════════════════════════════════════════════════════════

BEGIN;

-- ── 1) 가상 손님 5명 (org/budget/speed 다양화) ───────────────
INSERT INTO users
  (id, email, name, password_hash, role, status, auth_provider,
   kakao_id, org, budget, speed, radius)
VALUES
  ('eeeeeeee-1111-4000-8000-000000000001',
   'demo.customer1@lunchsync.test', '시연 손님 1 (한성대)',
   '$2b$10$KIXEqAcKwbWdfHWQVZxQXuC1V.qZTYqkBhPjN1OYW.7ZQ8K5XaHJG',
   'CUSTOMER', 'APPROVED', 'EMAIL',
   'demo_customer1_seed', '한성대학교', 9000, 'fast', 800),
  ('eeeeeeee-1111-4000-8000-000000000002',
   'demo.customer2@lunchsync.test', '시연 손님 2 (서울대)',
   '$2b$10$KIXEqAcKwbWdfHWQVZxQXuC1V.qZTYqkBhPjN1OYW.7ZQ8K5XaHJG',
   'CUSTOMER', 'APPROVED', 'EMAIL',
   'demo_customer2_seed', '서울대학교', 12000, 'normal', 1200),
  ('eeeeeeee-1111-4000-8000-000000000003',
   'demo.customer3@lunchsync.test', '시연 손님 3 (네이버)',
   '$2b$10$KIXEqAcKwbWdfHWQVZxQXuC1V.qZTYqkBhPjN1OYW.7ZQ8K5XaHJG',
   'CUSTOMER', 'APPROVED', 'EMAIL',
   'demo_customer3_seed', '네이버', 18000, 'slow', 1500),
  ('eeeeeeee-1111-4000-8000-000000000004',
   'demo.customer4@lunchsync.test', '시연 손님 4 (카카오)',
   '$2b$10$KIXEqAcKwbWdfHWQVZxQXuC1V.qZTYqkBhPjN1OYW.7ZQ8K5XaHJG',
   'CUSTOMER', 'APPROVED', 'EMAIL',
   'demo_customer4_seed', '카카오', 15000, 'normal', 1000),
  ('eeeeeeee-1111-4000-8000-000000000005',
   'demo.customer5@lunchsync.test', '시연 손님 5 (스타트업)',
   '$2b$10$KIXEqAcKwbWdfHWQVZxQXuC1V.qZTYqkBhPjN1OYW.7ZQ8K5XaHJG',
   'CUSTOMER', 'APPROVED', 'EMAIL',
   'demo_customer5_seed', '스타트업', 8000, 'fast', 500)
ON CONFLICT (id) DO NOTHING;

-- ── 2) 가상 사장 3명 (각자 다른 식당 매핑) ──────────────────
INSERT INTO users
  (id, email, name, password_hash, role, status, auth_provider,
   kakao_id, restaurant_id)
VALUES
  ('eeeeeeee-2222-4000-8000-000000000001',
   'demo.owner1@lunchsync.test', '한성대 분식왕 사장',
   '$2b$10$KIXEqAcKwbWdfHWQVZxQXuC1V.qZTYqkBhPjN1OYW.7ZQ8K5XaHJG',
   'OWNER', 'APPROVED', 'EMAIL',
   'demo_owner1_seed', 'dddddddd-0000-4000-8000-000000000004'),
  ('eeeeeeee-2222-4000-8000-000000000002',
   'demo.owner2@lunchsync.test', '청국장 명가 사장',
   '$2b$10$KIXEqAcKwbWdfHWQVZxQXuC1V.qZTYqkBhPjN1OYW.7ZQ8K5XaHJG',
   'OWNER', 'APPROVED', 'EMAIL',
   'demo_owner2_seed', 'dddddddd-0000-4000-8000-000000000001'),
  ('eeeeeeee-2222-4000-8000-000000000003',
   'demo.owner3@lunchsync.test', '빈티지카페 사장',
   '$2b$10$KIXEqAcKwbWdfHWQVZxQXuC1V.qZTYqkBhPjN1OYW.7ZQ8K5XaHJG',
   'OWNER', 'APPROVED', 'EMAIL',
   'demo_owner3_seed', 'dddddddd-0000-4000-8000-000000000018')
ON CONFLICT (id) DO NOTHING;

-- ── 3) 손님들의 즐겨찾기 일부 설정 (배민 패턴) ──────────────
-- favorites 컬럼이 비어있으면(=빈 배열) 가상 즐겨찾기 추가
-- 이미 즐겨찾기 있는 사용자는 영향 없음
UPDATE users
SET favorites = '[
  "dddddddd-0000-4000-8000-000000000004",
  "dddddddd-0000-4000-8000-000000000008",
  "dddddddd-0000-4000-8000-000000000018"
]'::jsonb
WHERE id = 'eeeeeeee-1111-4000-8000-000000000001'
  AND (favorites IS NULL OR jsonb_array_length(favorites) = 0);

UPDATE users
SET favorites = '[
  "dddddddd-0000-4000-8000-000000000007",
  "dddddddd-0000-4000-8000-000000000014",
  "dddddddd-0000-4000-8000-000000000019"
]'::jsonb
WHERE id = 'eeeeeeee-1111-4000-8000-000000000003'
  AND (favorites IS NULL OR jsonb_array_length(favorites) = 0);

UPDATE users
SET favorites = '[
  "dddddddd-0000-4000-8000-000000000015",
  "dddddddd-0000-4000-8000-000000000020"
]'::jsonb
WHERE id = 'eeeeeeee-1111-4000-8000-000000000004'
  AND (favorites IS NULL OR jsonb_array_length(favorites) = 0);

COMMIT;

-- ── 검증 ─────────────────────────────────────────────────
-- 1) 가상 사용자 수
-- SELECT role, COUNT(*) FROM users WHERE id::text LIKE 'eeeeeeee-%' GROUP BY role;
-- 기대: CUSTOMER 5, OWNER 3
--
-- 2) org 분포
-- SELECT org, COUNT(*) FROM users WHERE id::text LIKE 'eeeeeeee-1111-%' GROUP BY org;
--
-- 3) 즐겨찾기 채워진 사용자 수
-- SELECT id, name, jsonb_array_length(favorites) AS fav_count
-- FROM users WHERE id::text LIKE 'eeeeeeee-%' AND jsonb_array_length(favorites) > 0;
