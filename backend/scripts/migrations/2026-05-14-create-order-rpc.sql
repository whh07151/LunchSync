-- ══════════════════════════════════════════════════════════
-- 마이그레이션: 주문 생성 원자성 RPC (2026-05-14)
--
-- 목적:
--   주문 생성은 orders + order_items 두 테이블 INSERT 가 원자적으로 성공해야 함.
--   중간 실패 시 order 만 남고 items 미생성 → "장바구니 비었는데 결제 진행 중" 버그.
--
-- 입력:
--   p_session_id UUID
--   p_user_id UUID
--   p_total_price INT
--   p_payment_method TEXT (선택)
--   p_items JSON — [{ "menuItemId": "...", "quantity": 2, "price": 9000 }, ...]
--
-- 반환:
--   생성된 주문 행 (id, status, totalPrice, createdAt, items[])
--
-- 안전성:
--   - PostgreSQL 함수 = 단일 트랜잭션 — 중간 실패 시 전체 롤백
--   - CREATE OR REPLACE — 재실행 안전
-- ══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION create_order_with_items(
  p_session_id UUID,
  p_user_id UUID,
  p_total_price INT,
  p_payment_method TEXT DEFAULT NULL,
  p_items JSON DEFAULT '[]'::JSON
) RETURNS JSON AS $$
DECLARE
  v_order_id UUID;
  v_item JSON;
  v_items_result JSON;
BEGIN
  -- 1) orders INSERT
  INSERT INTO orders (
    session_id, user_id, total_price, payment_method, status
  )
  VALUES (
    p_session_id, p_user_id, p_total_price,
    COALESCE(p_payment_method, 'SIMULATE'),
    'PENDING'
  )
  RETURNING id INTO v_order_id;

  -- 2) order_items 일괄 INSERT (단일 트랜잭션 보장)
  FOR v_item IN SELECT * FROM json_array_elements(p_items)
  LOOP
    INSERT INTO order_items (
      order_id, menu_item_id, quantity, price
    )
    VALUES (
      v_order_id,
      (v_item->>'menuItemId')::UUID,
      (v_item->>'quantity')::INT,
      (v_item->>'price')::INT
    );
  END LOOP;

  -- 3) items 응답 조립 (메뉴 이름 조인)
  SELECT json_agg(
    json_build_object(
      'id', oi.id,
      'menuItemId', oi.menu_item_id,
      'menuName', mi.name,
      'quantity', oi.quantity,
      'price', oi.price
    )
  ) INTO v_items_result
  FROM order_items oi
  LEFT JOIN menu_items mi ON mi.id = oi.menu_item_id
  WHERE oi.order_id = v_order_id;

  -- 4) 응답 JSON
  RETURN json_build_object(
    'id', v_order_id,
    'sessionId', p_session_id,
    'userId', p_user_id,
    'totalPrice', p_total_price,
    'paymentMethod', COALESCE(p_payment_method, 'SIMULATE'),
    'status', 'PENDING',
    'createdAt', NOW(),
    'items', COALESCE(v_items_result, '[]'::JSON)
  );
END;
$$ LANGUAGE plpgsql;

-- 검증:
-- SELECT create_order_with_items(
--   '<session uuid>'::UUID,
--   '<user uuid>'::UUID,
--   18000,
--   'TOSS',
--   '[{"menuItemId":"<menu uuid>","quantity":2,"price":9000}]'::JSON
-- );
