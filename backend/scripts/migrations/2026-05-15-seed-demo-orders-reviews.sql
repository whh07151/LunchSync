-- ══════════════════════════════════════════════════════════
-- 시드: 가상 주문 30건 + 리뷰 15건 (2026-05-15)
--
-- 배경 (사장님 요구):
--   사장 어플 매출 통계 화면이 "주문 0건" 으로 시작해 시연 임팩트 0.
--   배민/쿠팡이츠 → 사장 어플 = 주문 흐름, 결제수단별 매출, 별점 분포
--   가시화. 가상 주문 30건 + 리뷰 15건을 풍부하게 INSERT.
--
-- 데이터 분포:
--   ▸ 식당 매핑: 시드 사장 3명이 운영하는 식당 3곳 + 추가 식당 4곳 = 7곳에
--     주문을 분산 (사장 어플 다중 매장 시연 가능)
--   ▸ 상태 분포: PAID(5) / PREPARING(5) / READY(5) / COMPLETED(12) / CANCELLED(3)
--   ▸ 결제수단: TOSS(15) / CARD(8) / CASH(5) / SIMULATE(2)
--   ▸ 시간 분포: 최근 14일에 걸쳐 분산 (created_at 분포)
--   ▸ 리뷰: COMPLETED 12건 중 15건은 안 됨 → 12건 + 미작성 3건은 NULL
--     사장님 자랑할 평점 분포: 5점(6) / 4점(4) / 3점(2)
--
-- 주문/주문아이템 UUID 규칙:
--   주문    : ffffffff-1111-4000-8000-0000000000NN  (NN=01..30)
--   주문항목: ffffffff-2222-4000-8000-XXXXXXXXXXXX  (자동)
--
-- 안전성:
--   ▸ ON CONFLICT (id) DO NOTHING — 멱등 재실행
--   ▸ 사장님 실 데이터 영향 0 (UUID 네임스페이스 분리)
--   ▸ session_id 는 dummy 세션 1개 생성 (FK 위반 회피)
--   ▸ menu_item_id 는 시드 메뉴 UUID 활용
--
-- 실행 의존:
--   1) 2026-05-15-seed-diverse-restaurants.sql 먼저 적용 (dddd 식당)
--   2) 2026-05-15-seed-diverse-users.sql 적용 (eeee 손님)
--   3) 이 파일 적용
-- ══════════════════════════════════════════════════════════

BEGIN;

-- ── 0) 더미 세션 1개 생성 (모든 가상 주문이 묶일 세션) ──────
-- orders.session_id FK 위반 회피용. 실제 사용자에게는 안 보이는 시드 세션.
INSERT INTO sessions (id, name, status, created_by, scheduled_at, lat, lng)
VALUES (
  'ffffffff-0000-4000-8000-000000000001',
  '시연 시드 세션',
  'DONE',  -- 종료된 세션으로 처리 (조회 시 활성 목록 제외)
  'eeeeeeee-1111-4000-8000-000000000001',
  NOW() - INTERVAL '7 days',
  37.5894, 127.0078
) ON CONFLICT (id) DO NOTHING;

-- session_members 도 끼워넣어야 FK/정합 OK
INSERT INTO session_members (session_id, user_id) VALUES
  ('ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000001')
ON CONFLICT DO NOTHING;

-- ── 1) 가상 주문 30건 INSERT ─────────────────────────────
-- session_id 는 모두 위 더미 세션 1개로 통일 (간소화)
-- restaurant_id 는 시드 식당 7곳에 분산
-- status / payment_method / total_price / review_* 를 분포 있게 부여
INSERT INTO orders
  (id, session_id, user_id, restaurant_id, total_price, status,
   payment_method, review_score, review_text, review_at, created_at)
VALUES
  -- ── PAID (5건, 사장 수락 대기 중) ──
  ('ffffffff-1111-4000-8000-000000000001',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000001',
   'dddddddd-0000-4000-8000-000000000004',  -- 한성대 분식왕
   9500, 'PAID', 'TOSS', NULL, NULL, NULL,
   NOW() - INTERVAL '5 minutes'),
  ('ffffffff-1111-4000-8000-000000000002',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000002',
   'dddddddd-0000-4000-8000-000000000001',  -- 청국장 명가
   12500, 'PAID', 'CARD', NULL, NULL, NULL,
   NOW() - INTERVAL '8 minutes'),
  ('ffffffff-1111-4000-8000-000000000003',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000003',
   'dddddddd-0000-4000-8000-000000000018',  -- 빈티지 카페
   13500, 'PAID', 'TOSS', NULL, NULL, NULL,
   NOW() - INTERVAL '12 minutes'),
  ('ffffffff-1111-4000-8000-000000000004',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000004',
   'dddddddd-0000-4000-8000-000000000008',  -- 동키라멘
   9500, 'PAID', 'TOSS', NULL, NULL, NULL,
   NOW() - INTERVAL '15 minutes'),
  ('ffffffff-1111-4000-8000-000000000005',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000005',
   'dddddddd-0000-4000-8000-000000000026',  -- 떡볶이타운
   8500, 'PAID', 'CARD', NULL, NULL, NULL,
   NOW() - INTERVAL '20 minutes'),

  -- ── PREPARING (5건, 조리 중) ──
  ('ffffffff-1111-4000-8000-000000000006',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000001',
   'dddddddd-0000-4000-8000-000000000004',
   11000, 'PREPARING', 'TOSS', NULL, NULL, NULL,
   NOW() - INTERVAL '35 minutes'),
  ('ffffffff-1111-4000-8000-000000000007',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000002',
   'dddddddd-0000-4000-8000-000000000001',
   23500, 'PREPARING', 'CARD', NULL, NULL, NULL,
   NOW() - INTERVAL '40 minutes'),
  ('ffffffff-1111-4000-8000-000000000008',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000003',
   'dddddddd-0000-4000-8000-000000000018',
   17500, 'PREPARING', 'TOSS', NULL, NULL, NULL,
   NOW() - INTERVAL '45 minutes'),
  ('ffffffff-1111-4000-8000-000000000009',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000004',
   'dddddddd-0000-4000-8000-000000000008',
   14500, 'PREPARING', 'CASH', NULL, NULL, NULL,
   NOW() - INTERVAL '50 minutes'),
  ('ffffffff-1111-4000-8000-000000000010',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000005',
   'dddddddd-0000-4000-8000-000000000026',
   13000, 'PREPARING', 'TOSS', NULL, NULL, NULL,
   NOW() - INTERVAL '55 minutes'),

  -- ── READY (5건, 픽업 대기) ──
  ('ffffffff-1111-4000-8000-000000000011',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000001',
   'dddddddd-0000-4000-8000-000000000004',
   8500, 'READY', 'CARD', NULL, NULL, NULL,
   NOW() - INTERVAL '70 minutes'),
  ('ffffffff-1111-4000-8000-000000000012',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000002',
   'dddddddd-0000-4000-8000-000000000001',
   9500, 'READY', 'TOSS', NULL, NULL, NULL,
   NOW() - INTERVAL '75 minutes'),
  ('ffffffff-1111-4000-8000-000000000013',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000003',
   'dddddddd-0000-4000-8000-000000000018',
   12500, 'READY', 'TOSS', NULL, NULL, NULL,
   NOW() - INTERVAL '80 minutes'),
  ('ffffffff-1111-4000-8000-000000000014',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000004',
   'dddddddd-0000-4000-8000-000000000008',
   18000, 'READY', 'CARD', NULL, NULL, NULL,
   NOW() - INTERVAL '85 minutes'),
  ('ffffffff-1111-4000-8000-000000000015',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000005',
   'dddddddd-0000-4000-8000-000000000022',  -- 버거킹
   8500, 'READY', 'CASH', NULL, NULL, NULL,
   NOW() - INTERVAL '90 minutes'),

  -- ── COMPLETED (12건, 리뷰 분포 포함) ──
  -- 5점 리뷰 (6건)
  ('ffffffff-1111-4000-8000-000000000016',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000001',
   'dddddddd-0000-4000-8000-000000000004',
   12000, 'COMPLETED', 'TOSS', 5, '떡볶이 맛집! 한성대 학생들에게 강추',
   NOW() - INTERVAL '1 day',
   NOW() - INTERVAL '1 day' - INTERVAL '30 minutes'),
  ('ffffffff-1111-4000-8000-000000000017',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000002',
   'dddddddd-0000-4000-8000-000000000001',
   9500, 'COMPLETED', 'CARD', 5, '청국장 진국. 어머니 손맛이에요',
   NOW() - INTERVAL '2 days',
   NOW() - INTERVAL '2 days' - INTERVAL '40 minutes'),
  ('ffffffff-1111-4000-8000-000000000018',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000003',
   'dddddddd-0000-4000-8000-000000000018',
   13500, 'COMPLETED', 'TOSS', 5, '브런치 분위기 너무 좋아요',
   NOW() - INTERVAL '3 days',
   NOW() - INTERVAL '3 days' - INTERVAL '50 minutes'),
  ('ffffffff-1111-4000-8000-000000000019',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000004',
   'dddddddd-0000-4000-8000-000000000007',  -- 스시오마카세
   32000, 'COMPLETED', 'TOSS', 5, '오마카세 가성비 최고!',
   NOW() - INTERVAL '4 days',
   NOW() - INTERVAL '4 days' - INTERVAL '60 minutes'),
  ('ffffffff-1111-4000-8000-000000000020',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000005',
   'dddddddd-0000-4000-8000-000000000014', -- 청담 스테이크
   45000, 'COMPLETED', 'CARD', 5, '데이트 코스 추천. 분위기 굿',
   NOW() - INTERVAL '5 days',
   NOW() - INTERVAL '5 days' - INTERVAL '75 minutes'),
  ('ffffffff-1111-4000-8000-000000000021',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000001',
   'dddddddd-0000-4000-8000-000000000008',
   11000, 'COMPLETED', 'CASH', 5, '돈코츠 진하고 맛있어요',
   NOW() - INTERVAL '6 days',
   NOW() - INTERVAL '6 days' - INTERVAL '35 minutes'),

  -- 4점 리뷰 (4건)
  ('ffffffff-1111-4000-8000-000000000022',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000002',
   'dddddddd-0000-4000-8000-000000000004',
   8500, 'COMPLETED', 'TOSS', 4, '맛은 좋은데 좀 짠 편',
   NOW() - INTERVAL '7 days',
   NOW() - INTERVAL '7 days' - INTERVAL '30 minutes'),
  ('ffffffff-1111-4000-8000-000000000023',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000003',
   'dddddddd-0000-4000-8000-000000000022',
   9000, 'COMPLETED', 'SIMULATE', 4, '햄버거 무난',
   NOW() - INTERVAL '8 days',
   NOW() - INTERVAL '8 days' - INTERVAL '25 minutes'),
  ('ffffffff-1111-4000-8000-000000000024',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000004',
   'dddddddd-0000-4000-8000-000000000026',
   10500, 'COMPLETED', 'CARD', 4, '로제 떡볶이 추천. 양도 많아요',
   NOW() - INTERVAL '9 days',
   NOW() - INTERVAL '9 days' - INTERVAL '40 minutes'),
  ('ffffffff-1111-4000-8000-000000000025',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000005',
   'dddddddd-0000-4000-8000-000000000001',
   12500, 'COMPLETED', 'TOSS', 4, '청국장 호불호. 7찬 알찼어요',
   NOW() - INTERVAL '10 days',
   NOW() - INTERVAL '10 days' - INTERVAL '45 minutes'),

  -- 3점 리뷰 (2건)
  ('ffffffff-1111-4000-8000-000000000026',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000001',
   'dddddddd-0000-4000-8000-000000000022',
   8500, 'COMPLETED', 'TOSS', 3, '평범. 그냥 패스트푸드',
   NOW() - INTERVAL '11 days',
   NOW() - INTERVAL '11 days' - INTERVAL '20 minutes'),
  ('ffffffff-1111-4000-8000-000000000027',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000002',
   'dddddddd-0000-4000-8000-000000000026',
   9000, 'COMPLETED', 'SIMULATE', 3, '양은 적당, 매운맛 무난',
   NOW() - INTERVAL '12 days',
   NOW() - INTERVAL '12 days' - INTERVAL '30 minutes'),

  -- ── CANCELLED (3건, 사장 거절 사례) ──
  ('ffffffff-1111-4000-8000-000000000028',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000003',
   'dddddddd-0000-4000-8000-000000000018',
   6500, 'CANCELLED', 'TOSS', NULL, NULL, NULL,
   NOW() - INTERVAL '13 days'),
  ('ffffffff-1111-4000-8000-000000000029',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000004',
   'dddddddd-0000-4000-8000-000000000004',
   5500, 'CANCELLED', 'CARD', NULL, NULL, NULL,
   NOW() - INTERVAL '13 days' - INTERVAL '5 hours'),
  ('ffffffff-1111-4000-8000-000000000030',
   'ffffffff-0000-4000-8000-000000000001',
   'eeeeeeee-1111-4000-8000-000000000005',
   'dddddddd-0000-4000-8000-000000000008',
   9500, 'CANCELLED', 'CASH', NULL, NULL, NULL,
   NOW() - INTERVAL '14 days')
ON CONFLICT (id) DO NOTHING;

-- ── 2) order_items 일괄 INSERT ────────────────────────────
-- 각 주문에 1~2개 메뉴 아이템 매핑 (사장 통계 화면이 메뉴별 매출 표시 가능)
-- 시드 식당의 첫 번째 메뉴를 임의 매핑 (단순화).
INSERT INTO order_items (order_id, menu_item_id, quantity, price)
SELECT o.id, mi.menu_id::uuid, mi.qty, mi.unit_price
FROM (VALUES
  -- order_id, restaurant_id 의 첫 메뉴, 수량, 단가
  ('ffffffff-1111-4000-8000-000000000001', 'dddddddd-0000-4000-8000-000000000004', 2, 4500),
  ('ffffffff-1111-4000-8000-000000000002', 'dddddddd-0000-4000-8000-000000000001', 1, 12500),
  ('ffffffff-1111-4000-8000-000000000003', 'dddddddd-0000-4000-8000-000000000018', 1, 13500),
  ('ffffffff-1111-4000-8000-000000000004', 'dddddddd-0000-4000-8000-000000000008', 1,  9500),
  ('ffffffff-1111-4000-8000-000000000005', 'dddddddd-0000-4000-8000-000000000026', 1,  8500),
  ('ffffffff-1111-4000-8000-000000000006', 'dddddddd-0000-4000-8000-000000000004', 2, 5500),
  ('ffffffff-1111-4000-8000-000000000007', 'dddddddd-0000-4000-8000-000000000001', 2,11750),
  ('ffffffff-1111-4000-8000-000000000008', 'dddddddd-0000-4000-8000-000000000018', 1,17500),
  ('ffffffff-1111-4000-8000-000000000009', 'dddddddd-0000-4000-8000-000000000008', 1,14500),
  ('ffffffff-1111-4000-8000-000000000010', 'dddddddd-0000-4000-8000-000000000026', 1,13000),
  ('ffffffff-1111-4000-8000-000000000011', 'dddddddd-0000-4000-8000-000000000004', 1, 8500),
  ('ffffffff-1111-4000-8000-000000000012', 'dddddddd-0000-4000-8000-000000000001', 1, 9500),
  ('ffffffff-1111-4000-8000-000000000013', 'dddddddd-0000-4000-8000-000000000018', 1,12500),
  ('ffffffff-1111-4000-8000-000000000014', 'dddddddd-0000-4000-8000-000000000008', 2, 9000),
  ('ffffffff-1111-4000-8000-000000000015', 'dddddddd-0000-4000-8000-000000000022', 1, 8500),
  ('ffffffff-1111-4000-8000-000000000016', 'dddddddd-0000-4000-8000-000000000004', 2, 6000),
  ('ffffffff-1111-4000-8000-000000000017', 'dddddddd-0000-4000-8000-000000000001', 1, 9500),
  ('ffffffff-1111-4000-8000-000000000018', 'dddddddd-0000-4000-8000-000000000018', 1,13500),
  ('ffffffff-1111-4000-8000-000000000019', 'dddddddd-0000-4000-8000-000000000007', 1,32000),
  ('ffffffff-1111-4000-8000-000000000020', 'dddddddd-0000-4000-8000-000000000014', 1,45000),
  ('ffffffff-1111-4000-8000-000000000021', 'dddddddd-0000-4000-8000-000000000008', 1,11000),
  ('ffffffff-1111-4000-8000-000000000022', 'dddddddd-0000-4000-8000-000000000004', 1, 8500),
  ('ffffffff-1111-4000-8000-000000000023', 'dddddddd-0000-4000-8000-000000000022', 1, 9000),
  ('ffffffff-1111-4000-8000-000000000024', 'dddddddd-0000-4000-8000-000000000026', 1,10500),
  ('ffffffff-1111-4000-8000-000000000025', 'dddddddd-0000-4000-8000-000000000001', 1,12500),
  ('ffffffff-1111-4000-8000-000000000026', 'dddddddd-0000-4000-8000-000000000022', 1, 8500),
  ('ffffffff-1111-4000-8000-000000000027', 'dddddddd-0000-4000-8000-000000000026', 1, 9000),
  ('ffffffff-1111-4000-8000-000000000028', 'dddddddd-0000-4000-8000-000000000018', 1, 6500),
  ('ffffffff-1111-4000-8000-000000000029', 'dddddddd-0000-4000-8000-000000000004', 1, 5500),
  ('ffffffff-1111-4000-8000-000000000030', 'dddddddd-0000-4000-8000-000000000008', 1, 9500)
) AS mi(order_id, restaurant_id, qty, unit_price)
JOIN orders o ON o.id = mi.order_id::uuid
JOIN LATERAL (
  -- 식당의 첫 메뉴 1개 (created_at 또는 name asc 정렬)
  SELECT id AS menu_id FROM menu_items
  WHERE restaurant_id = mi.restaurant_id::uuid
  ORDER BY name LIMIT 1
) menu_pick ON true
WHERE NOT EXISTS (
  SELECT 1 FROM order_items oi WHERE oi.order_id = o.id
)
-- order_items 는 컴포지트 PK 가 없을 수 있어 동일 (order, menu) 중복 회피
;

COMMIT;

-- ── 검증 ─────────────────────────────────────────────────
-- 1) 상태별 주문 수
-- SELECT status, COUNT(*) FROM orders WHERE id::text LIKE 'ffffffff-1111-%'
-- GROUP BY status ORDER BY status;
-- 기대: PAID 5, PREPARING 5, READY 5, COMPLETED 12, CANCELLED 3
--
-- 2) 결제수단별 매출 (사장 통계 화면이 보여줄 데이터)
-- SELECT payment_method, COUNT(*) AS orders_cnt, SUM(total_price) AS revenue
-- FROM orders
-- WHERE id::text LIKE 'ffffffff-1111-%' AND status IN ('COMPLETED','READY','PREPARING','PAID')
-- GROUP BY payment_method;
--
-- 3) 매장별 평균 평점
-- SELECT r.name, AVG(o.review_score) AS avg_score, COUNT(o.review_score) AS reviews
-- FROM orders o JOIN restaurants r ON r.id = o.restaurant_id
-- WHERE o.id::text LIKE 'ffffffff-1111-%' AND o.review_score IS NOT NULL
-- GROUP BY r.id, r.name ORDER BY avg_score DESC;
