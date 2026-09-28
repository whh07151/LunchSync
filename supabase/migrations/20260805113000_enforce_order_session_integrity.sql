-- Enforce that service-role order creation uses the caller's active session
-- membership and the restaurant selected by the completed vote. The locks keep
-- those decisions stable until the order header and line items commit.

drop function if exists public.create_order_with_items(
  uuid,
  uuid,
  integer,
  text,
  json
);

create or replace function public.create_order_with_items(
  p_session_id uuid,
  p_user_id uuid,
  p_restaurant_id uuid,
  p_total_price integer,
  p_payment_method text default null,
  p_items json default '[]'::json
)
returns json
language plpgsql
security invoker
set search_path = pg_catalog, pg_temp
as $$
declare
  v_order_id uuid;
  v_item json;
  v_session_status public.session_status;
  v_winner_restaurant_id uuid;
  v_menu_price integer;
  v_menu_restaurant_id uuid;
  v_quantity integer;
  v_item_price integer;
  v_calculated_total integer := 0;
  v_items_result json;
begin
  if p_total_price < 0 then
    raise exception 'ORDER_TOTAL_INVALID' using errcode = '22023';
  end if;

  if p_items is null
     or json_typeof(p_items) <> 'array'
     or json_array_length(p_items) = 0 then
    raise exception 'ORDER_ITEMS_REQUIRED' using errcode = '22023';
  end if;

  select status, winner_restaurant_id
  into v_session_status, v_winner_restaurant_id
  from public.sessions
  where id = p_session_id
  for share;

  if not found then
    raise exception 'ORDER_SESSION_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform 1
  from public.session_members
  where session_id = p_session_id
    and user_id = p_user_id
  for key share;

  if not found then
    raise exception 'ORDER_SESSION_MEMBER_REQUIRED' using errcode = '42501';
  end if;

  if v_session_status <> 'ORDERED'
     or v_winner_restaurant_id is null then
    raise exception 'ORDER_SESSION_NOT_READY' using errcode = 'P0001';
  end if;

  if v_winner_restaurant_id <> p_restaurant_id then
    raise exception 'ORDER_SESSION_RESTAURANT_MISMATCH'
      using errcode = 'P0001';
  end if;

  -- Acquire every requested menu lock in a canonical order so concurrent
  -- multi-row menu writers cannot observe caller-controlled lock ordering.
  perform 1
  from public.menu_items
  where id in (
    select (value ->> 'menuItemId')::uuid
    from json_array_elements(p_items)
  )
  order by id
  for share;

  for v_item in select value from json_array_elements(p_items)
  loop
    v_quantity := (v_item ->> 'quantity')::integer;
    v_item_price := (v_item ->> 'price')::integer;

    if v_quantity <= 0 or v_item_price < 0 then
      raise exception 'ORDER_ITEM_INVALID' using errcode = '22023';
    end if;

    select price, restaurant_id
    into v_menu_price, v_menu_restaurant_id
    from public.menu_items
    where id = (v_item ->> 'menuItemId')::uuid
      and is_available
    for share;

    if not found then
      raise exception 'ORDER_MENU_ITEM_NOT_FOUND' using errcode = 'P0002';
    end if;

    if v_menu_restaurant_id <> p_restaurant_id then
      raise exception 'ORDER_RESTAURANT_MISMATCH' using errcode = '22023';
    end if;

    if v_menu_price <> v_item_price then
      raise exception 'ORDER_MENU_PRICE_CHANGED' using errcode = '22023';
    end if;

    v_calculated_total := v_calculated_total + (v_quantity * v_item_price);
  end loop;

  if v_calculated_total <> p_total_price then
    raise exception 'ORDER_TOTAL_MISMATCH' using errcode = '22023';
  end if;

  insert into public.orders (
    session_id,
    user_id,
    restaurant_id,
    total_price,
    payment_method,
    status
  )
  values (
    p_session_id,
    p_user_id,
    p_restaurant_id,
    p_total_price,
    coalesce(p_payment_method, 'SIMULATE')::public.payment_method_type,
    'PENDING'
  )
  returning id into v_order_id;

  for v_item in select value from json_array_elements(p_items)
  loop
    insert into public.order_items (
      order_id,
      menu_item_id,
      quantity,
      price
    )
    values (
      v_order_id,
      (v_item ->> 'menuItemId')::uuid,
      (v_item ->> 'quantity')::integer,
      (v_item ->> 'price')::integer
    );
  end loop;

  select json_agg(
    json_build_object(
      'id', oi.id,
      'menuItemId', oi.menu_item_id,
      'menuName', mi.name,
      'quantity', oi.quantity,
      'price', oi.price
    )
    order by oi.id
  )
  into v_items_result
  from public.order_items oi
  join public.menu_items mi on mi.id = oi.menu_item_id
  where oi.order_id = v_order_id;

  return json_build_object(
    'id', v_order_id,
    'sessionId', p_session_id,
    'userId', p_user_id,
    'restaurantId', p_restaurant_id,
    'totalPrice', p_total_price,
    'paymentMethod', coalesce(p_payment_method, 'SIMULATE'),
    'status', 'PENDING',
    'createdAt', now(),
    'items', coalesce(v_items_result, '[]'::json)
  );
end;
$$;

revoke all on function public.create_order_with_items(
  uuid,
  uuid,
  uuid,
  integer,
  text,
  json
) from public, anon, authenticated;

grant execute on function public.create_order_with_items(
  uuid,
  uuid,
  uuid,
  integer,
  text,
  json
) to service_role;
