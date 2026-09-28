-- Make order header and line-item creation atomic.
--
-- The first version of create_order_with_items did not include restaurant_id,
-- which is now required by orders. Replace that signature so callers cannot
-- accidentally use the obsolete contract.

DROP FUNCTION IF EXISTS public.create_order_with_items(
  UUID,
  UUID,
  INT,
  TEXT,
  JSON
);

CREATE OR REPLACE FUNCTION public.create_order_with_items(
  p_session_id UUID,
  p_user_id UUID,
  p_restaurant_id UUID,
  p_total_price INT,
  p_payment_method TEXT DEFAULT NULL,
  p_items JSON DEFAULT '[]'::JSON
) RETURNS JSON AS $$
DECLARE
  v_order_id UUID;
  v_item JSON;
  v_session_status public.session_status;
  v_winner_restaurant_id UUID;
  v_menu_price INT;
  v_menu_restaurant_id UUID;
  v_quantity INT;
  v_item_price INT;
  v_calculated_total INT := 0;
  v_items_result JSON;
BEGIN
  IF p_total_price < 0 THEN
    RAISE EXCEPTION 'ORDER_TOTAL_INVALID' USING ERRCODE = '22023';
  END IF;

  IF p_items IS NULL
     OR json_typeof(p_items) <> 'array'
     OR json_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'ORDER_ITEMS_REQUIRED' USING ERRCODE = '22023';
  END IF;

  SELECT status, winner_restaurant_id
  INTO v_session_status, v_winner_restaurant_id
  FROM public.sessions
  WHERE id = p_session_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_SESSION_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  PERFORM 1
  FROM public.session_members
  WHERE session_id = p_session_id
    AND user_id = p_user_id
  FOR KEY SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_SESSION_MEMBER_REQUIRED' USING ERRCODE = '42501';
  END IF;

  IF v_session_status <> 'ORDERED'
     OR v_winner_restaurant_id IS NULL THEN
    RAISE EXCEPTION 'ORDER_SESSION_NOT_READY' USING ERRCODE = 'P0001';
  END IF;

  IF v_winner_restaurant_id <> p_restaurant_id THEN
    RAISE EXCEPTION 'ORDER_SESSION_RESTAURANT_MISMATCH'
      USING ERRCODE = 'P0001';
  END IF;

  -- Acquire every requested menu lock in a canonical order so concurrent
  -- multi-row menu writers cannot observe caller-controlled lock ordering.
  PERFORM 1
  FROM public.menu_items
  WHERE id IN (
    SELECT (value ->> 'menuItemId')::UUID
    FROM json_array_elements(p_items)
  )
  ORDER BY id
  FOR SHARE;

  FOR v_item IN SELECT value FROM json_array_elements(p_items)
  LOOP
    v_quantity := (v_item ->> 'quantity')::INT;
    v_item_price := (v_item ->> 'price')::INT;

    IF v_quantity <= 0 OR v_item_price < 0 THEN
      RAISE EXCEPTION 'ORDER_ITEM_INVALID' USING ERRCODE = '22023';
    END IF;

    SELECT price, restaurant_id
    INTO v_menu_price, v_menu_restaurant_id
    FROM public.menu_items
    WHERE id = (v_item ->> 'menuItemId')::UUID
      AND is_available
    FOR SHARE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'ORDER_MENU_ITEM_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;

    IF v_menu_restaurant_id <> p_restaurant_id THEN
      RAISE EXCEPTION 'ORDER_RESTAURANT_MISMATCH'
        USING ERRCODE = '22023';
    END IF;

    IF v_menu_price <> v_item_price THEN
      RAISE EXCEPTION 'ORDER_MENU_PRICE_CHANGED' USING ERRCODE = '22023';
    END IF;

    v_calculated_total := v_calculated_total + (v_quantity * v_item_price);
  END LOOP;

  IF v_calculated_total <> p_total_price THEN
    RAISE EXCEPTION 'ORDER_TOTAL_MISMATCH' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.orders (
    session_id,
    user_id,
    restaurant_id,
    total_price,
    payment_method,
    status
  )
  VALUES (
    p_session_id,
    p_user_id,
    p_restaurant_id,
    p_total_price,
    COALESCE(p_payment_method, 'SIMULATE')::public.payment_method_type,
    'PENDING'
  )
  RETURNING id INTO v_order_id;

  FOR v_item IN SELECT * FROM json_array_elements(p_items)
  LOOP
    INSERT INTO public.order_items (
      order_id,
      menu_item_id,
      quantity,
      price
    )
    VALUES (
      v_order_id,
      (v_item->>'menuItemId')::UUID,
      (v_item->>'quantity')::INT,
      (v_item->>'price')::INT
    );
  END LOOP;

  SELECT json_agg(
    json_build_object(
      'id', oi.id,
      'menuItemId', oi.menu_item_id,
      'menuName', mi.name,
      'quantity', oi.quantity,
      'price', oi.price
    )
    ORDER BY oi.id
  )
  INTO v_items_result
  FROM public.order_items oi
  JOIN public.menu_items mi ON mi.id = oi.menu_item_id
  WHERE oi.order_id = v_order_id;

  RETURN json_build_object(
    'id', v_order_id,
    'sessionId', p_session_id,
    'userId', p_user_id,
    'restaurantId', p_restaurant_id,
    'totalPrice', p_total_price,
    'paymentMethod', COALESCE(p_payment_method, 'SIMULATE'),
    'status', 'PENDING',
    'createdAt', NOW(),
    'items', COALESCE(v_items_result, '[]'::JSON)
  );
END;
$$
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp;

-- PostgreSQL grants EXECUTE on new functions to PUBLIC by default. This RPC
-- accepts server-derived identity, restaurant, total, and item prices, so only
-- the NestJS service-role client may cross this database boundary.
REVOKE ALL ON FUNCTION public.create_order_with_items(
  UUID,
  UUID,
  UUID,
  INT,
  TEXT,
  JSON
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_order_with_items(
  UUID,
  UUID,
  UUID,
  INT,
  TEXT,
  JSON
) TO service_role;
