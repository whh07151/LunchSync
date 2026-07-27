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
  v_items_result JSON;
BEGIN
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
    COALESCE(p_payment_method, 'SIMULATE')::payment_method_type,
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
  )
  INTO v_items_result
  FROM public.order_items oi
  LEFT JOIN public.menu_items mi ON mi.id = oi.menu_item_id
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
$$ LANGUAGE plpgsql;
