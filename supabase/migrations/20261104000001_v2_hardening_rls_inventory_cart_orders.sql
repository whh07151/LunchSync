-- LunchSync v2 hardening migration (2026-11-04)
--
-- Scope:
--   1. Normalize and constrain v2 columns/tables (`restaurants`,
--      `pos_inventory_items`, `pos_inventory_deductions`,
--      `session_cart_items`, `orders`, `pos_reservations`).
--   2. Enable RLS and revoke direct table/function privileges from
--      PUBLIC, anon, and authenticated; grant least privilege to service_role.
--   3. Provide atomic transactional RPCs for:
--      - Full inventory replacement (`replace_pos_inventory_items`)
--      - Order status transition PAID -> PREPARING with row-locked BOM
--        deduction and per-order idempotency (`transition_order_to_preparing_with_bom`)
--      - Post-payment cart consumption scoped to the ordering user and
--        ordered item quantities (`consume_ordered_session_cart_items`)

-- 1. Restaurants store status columns & constraints
alter table public.restaurants
  add column if not exists business_status text not null default 'OPEN';

alter table public.restaurants
  add column if not exists operating_hours_note text not null
    default '영업 11:00~21:00 · 브레이크타임 15:00~17:00';

update public.restaurants
set business_status = case
  when upper(btrim(business_status)) in ('OPEN') then 'OPEN'
  when upper(btrim(business_status)) in ('BREAK_TIME', 'BREAKTIME') then 'BREAK_TIME'
  when upper(btrim(business_status)) in ('CLOSED') then 'CLOSED'
  else 'OPEN'
end
where business_status is null
   or business_status not in ('OPEN', 'BREAK_TIME', 'CLOSED');

update public.restaurants
set operating_hours_note = left(coalesce(operating_hours_note, ''), 200)
where char_length(operating_hours_note) > 200;

alter table public.restaurants
  drop constraint if exists restaurants_business_status_allowed;
alter table public.restaurants
  add constraint restaurants_business_status_allowed
    check (business_status in ('OPEN', 'BREAK_TIME', 'CLOSED'));

alter table public.restaurants
  drop constraint if exists restaurants_operating_hours_note_length;
alter table public.restaurants
  add constraint restaurants_operating_hours_note_length
    check (char_length(operating_hours_note) <= 200);

-- 2. Orders dining_type & customer_note columns and constraints
alter table public.orders
  add column if not exists dining_type text not null default 'DINE_IN';

alter table public.orders
  add column if not exists customer_note text;

update public.orders
set dining_type = 'DINE_IN'
where dining_type is null
   or dining_type not in ('DINE_IN', 'TAKEOUT');

update public.orders
set customer_note = left(customer_note, 300)
where customer_note is not null
  and char_length(customer_note) > 300;

alter table public.orders
  drop constraint if exists orders_dining_type_allowed;
alter table public.orders
  add constraint orders_dining_type_allowed
    check (dining_type in ('DINE_IN', 'TAKEOUT'));

alter table public.orders
  drop constraint if exists orders_customer_note_length;
alter table public.orders
  add constraint orders_customer_note_length
    check (customer_note is null or char_length(customer_note) <= 300);

-- 3. POS reservations order_id idempotency key
alter table public.pos_reservations
  add column if not exists order_id uuid
    references public.orders (id) on delete set null;

create unique index if not exists pos_reservations_order_id_key
  on public.pos_reservations (order_id)
  where order_id is not null;

-- 4. POS inventory items table & constraints
create table if not exists public.pos_inventory_items (
  id text not null,
  restaurant_id uuid not null
    references public.restaurants (id) on delete cascade,
  name text not null,
  category text not null default '기타',
  current_qty integer not null default 0,
  min_threshold integer not null default 5,
  unit text not null default '인분',
  linked_menu_names text[] not null default '{}',
  expiry_date text,
  recipe_unit_per_serving integer not null default 1,
  updated_at timestamptz not null default now(),
  primary key (restaurant_id, id)
);

update public.pos_inventory_items
set current_qty = greatest(0, least(100000, current_qty)),
    min_threshold = greatest(0, least(100000, min_threshold)),
    recipe_unit_per_serving = greatest(1, least(10000, recipe_unit_per_serving)),
    expiry_date = case
      when expiry_date is not null and btrim(expiry_date) ~ '^\d{4}-\d{2}-\d{2}$'
        then btrim(expiry_date)
      else null
    end;

alter table public.pos_inventory_items
  drop constraint if exists pos_inventory_items_id_length,
  drop constraint if exists pos_inventory_items_name_length,
  drop constraint if exists pos_inventory_items_category_length,
  drop constraint if exists pos_inventory_items_current_qty_range,
  drop constraint if exists pos_inventory_items_min_threshold_range,
  drop constraint if exists pos_inventory_items_unit_length,
  drop constraint if exists pos_inventory_items_linked_menus_max,
  drop constraint if exists pos_inventory_items_expiry_date_format,
  drop constraint if exists pos_inventory_items_recipe_unit_range;

alter table public.pos_inventory_items
  add constraint pos_inventory_items_id_length
    check (char_length(btrim(id)) between 1 and 64),
  add constraint pos_inventory_items_name_length
    check (char_length(btrim(name)) between 1 and 100),
  add constraint pos_inventory_items_category_length
    check (char_length(btrim(category)) between 1 and 50),
  add constraint pos_inventory_items_current_qty_range
    check (current_qty between 0 and 100000),
  add constraint pos_inventory_items_min_threshold_range
    check (min_threshold between 0 and 100000),
  add constraint pos_inventory_items_unit_length
    check (char_length(btrim(unit)) between 1 and 20),
  add constraint pos_inventory_items_linked_menus_max
    check (coalesce(array_length(linked_menu_names, 1), 0) <= 50),
  add constraint pos_inventory_items_expiry_date_format
    check (expiry_date is null or expiry_date ~ '^\d{4}-\d{2}-\d{2}$'),
  add constraint pos_inventory_items_recipe_unit_range
    check (recipe_unit_per_serving between 1 and 10000);

-- 5. Per-order inventory deduction ledger (idempotency & audit trail)
create table if not exists public.pos_inventory_deductions (
  order_id uuid primary key
    references public.orders (id) on delete cascade,
  restaurant_id uuid not null
    references public.restaurants (id) on delete cascade,
  deducted_items jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  constraint pos_inventory_deductions_items_is_array
    check (jsonb_typeof(deducted_items) = 'array')
);

create index if not exists pos_inventory_deductions_restaurant_id_idx
  on public.pos_inventory_deductions (restaurant_id, created_at desc);

-- 6. Shared session cart items table & constraints
create table if not exists public.session_cart_items (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null
    references public.sessions (id) on delete cascade,
  user_id uuid not null
    references public.users (id) on delete cascade,
  user_name text not null default '동료',
  menu_item_id uuid not null
    references public.menu_items (id) on delete cascade,
  menu_name text not null,
  price integer not null default 0,
  quantity integer not null default 1,
  updated_at timestamptz not null default now(),
  unique (session_id, user_id, menu_item_id)
);

delete from public.session_cart_items
where quantity <= 0;

update public.session_cart_items
set quantity = least(99, greatest(1, quantity)),
    price = greatest(0, price),
    user_name = case
      when char_length(btrim(coalesce(user_name, ''))) = 0 then '동료'
      else left(btrim(user_name), 80)
    end,
    menu_name = case
      when char_length(btrim(coalesce(menu_name, ''))) = 0 then '메뉴'
      else left(btrim(menu_name), 120)
    end;

alter table public.session_cart_items
  drop constraint if exists session_cart_items_user_name_length,
  drop constraint if exists session_cart_items_menu_name_length,
  drop constraint if exists session_cart_items_price_nonnegative,
  drop constraint if exists session_cart_items_quantity_range;

alter table public.session_cart_items
  add constraint session_cart_items_user_name_length
    check (char_length(btrim(user_name)) between 1 and 80),
  add constraint session_cart_items_menu_name_length
    check (char_length(btrim(menu_name)) between 1 and 120),
  add constraint session_cart_items_price_nonnegative
    check (price >= 0),
  add constraint session_cart_items_quantity_range
    check (quantity between 1 and 99);

create index if not exists session_cart_items_session_updated_idx
  on public.session_cart_items (session_id, updated_at asc);


-- 7. Atomic RPC: replace_pos_inventory_items
drop function if exists public.replace_pos_inventory_items(uuid,jsonb);
create or replace function public.replace_pos_inventory_items(
  p_restaurant_id uuid,
  p_items jsonb,
  p_expected_items jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, pg_temp
as $$
declare
  v_elem jsonb;
  v_id text;
  v_name text;
  v_category text;
  v_current_qty integer;
  v_min_threshold integer;
  v_unit text;
  v_expiry_date text;
  v_parsed_expiry date;
  v_recipe_unit integer;
  v_linked text[];
  v_seen_ids text[] := '{}'::text[];
  v_result jsonb;
begin
  if p_restaurant_id is null then
    raise exception 'POS_INVENTORY_RESTAURANT_REQUIRED' using errcode = '22023';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'POS_INVENTORY_ITEMS_ARRAY_REQUIRED' using errcode = '22023';
  end if;

  if jsonb_array_length(p_items) > 200 then
    raise exception 'POS_INVENTORY_TOO_MANY_ITEMS' using errcode = '22023';
  end if;

  -- Serialize against concurrent inventory replacements and order BOM deductions
  -- for the same restaurant.
  perform 1
  from public.restaurants
  where id = p_restaurant_id
  for update;

  if not found then
    raise exception 'POS_RESTAURANT_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform 1
  from public.pos_inventory_items
  where restaurant_id = p_restaurant_id
  order by id
  for update;

  if p_expected_items is null or jsonb_typeof(p_expected_items) <> 'array' then
    raise exception 'POS_INVENTORY_SNAPSHOT_REQUIRED' using errcode='22023';
  end if;
  if exists (
    select 1 from public.pos_inventory_items i
    full join jsonb_to_recordset(p_expected_items) as e(id text, "updatedAt" timestamptz)
      on i.restaurant_id=p_restaurant_id and i.id=e.id
    where (i.restaurant_id=p_restaurant_id or i.id is null)
      and (i.id is null or e.id is null or i.updated_at is distinct from e."updatedAt")
  ) or jsonb_array_length(p_expected_items) <> (
    select count(*) from public.pos_inventory_items where restaurant_id=p_restaurant_id
  ) then
    raise exception 'POS_INVENTORY_CHANGED' using errcode='40001';
  end if;

  for v_elem in select value from jsonb_array_elements(p_items)
  loop
    if v_elem is null or jsonb_typeof(v_elem) <> 'object' then
      raise exception 'POS_INVENTORY_ITEM_INVALID' using errcode = '22023';
    end if;

    v_id := btrim(coalesce(v_elem ->> 'id', ''));
    v_name := btrim(coalesce(v_elem ->> 'name', ''));
    v_category := btrim(coalesce(v_elem ->> 'category', '기타'));
    v_unit := btrim(coalesce(v_elem ->> 'unit', '인분'));

    if char_length(v_id) < 1 or char_length(v_id) > 64 then
      raise exception 'POS_INVENTORY_ID_INVALID' using errcode = '22023';
    end if;

    if v_id = any(v_seen_ids) then
      raise exception 'POS_INVENTORY_DUPLICATE_ID' using errcode = '23505';
    end if;
    v_seen_ids := array_append(v_seen_ids, v_id);

    if exists (
      select 1 from public.pos_inventory_items i
      where i.restaurant_id = p_restaurant_id and i.id = v_id
        and (nullif(v_elem ->> 'expectedUpdatedAt', '') is null
          or i.updated_at is distinct from (v_elem ->> 'expectedUpdatedAt')::timestamptz)
    ) then
      raise exception 'POS_INVENTORY_CHANGED' using errcode = '40001';
    end if;


    if char_length(v_name) < 1 or char_length(v_name) > 100 then
      raise exception 'POS_INVENTORY_NAME_INVALID' using errcode = '22023';
    end if;

    if char_length(v_category) < 1 or char_length(v_category) > 50 then
      raise exception 'POS_INVENTORY_CATEGORY_INVALID' using errcode = '22023';
    end if;

    if char_length(v_unit) < 1 or char_length(v_unit) > 20 then
      raise exception 'POS_INVENTORY_UNIT_INVALID' using errcode = '22023';
    end if;

    if jsonb_typeof(v_elem -> 'currentQty') is distinct from 'number'
       or (v_elem ->> 'currentQty') !~ '^\d+$' then
      raise exception 'POS_INVENTORY_QTY_INVALID' using errcode = '22023';
    end if;
    v_current_qty := (v_elem ->> 'currentQty')::integer;
    if v_current_qty < 0 or v_current_qty > 100000 then
      raise exception 'POS_INVENTORY_QTY_OUT_OF_RANGE' using errcode = '22023';
    end if;

    if jsonb_typeof(v_elem -> 'minThreshold') is distinct from 'number'
       or (v_elem ->> 'minThreshold') !~ '^\d+$' then
      raise exception 'POS_INVENTORY_THRESHOLD_INVALID' using errcode = '22023';
    end if;
    v_min_threshold := (v_elem ->> 'minThreshold')::integer;
    if v_min_threshold < 0 or v_min_threshold > 100000 then
      raise exception 'POS_INVENTORY_THRESHOLD_OUT_OF_RANGE' using errcode = '22023';
    end if;

    if v_elem ? 'recipeUnitPerServing' and jsonb_typeof(v_elem -> 'recipeUnitPerServing') <> 'null' then
      if jsonb_typeof(v_elem -> 'recipeUnitPerServing') <> 'number'
         or (v_elem ->> 'recipeUnitPerServing') !~ '^\d+$' then
        raise exception 'POS_INVENTORY_RECIPE_UNIT_INVALID' using errcode = '22023';
      end if;
      v_recipe_unit := (v_elem ->> 'recipeUnitPerServing')::integer;
    else
      v_recipe_unit := 1;
    end if;
    if v_recipe_unit < 1 or v_recipe_unit > 10000 then
      raise exception 'POS_INVENTORY_RECIPE_UNIT_OUT_OF_RANGE' using errcode = '22023';
    end if;

    v_expiry_date := nullif(btrim(coalesce(v_elem ->> 'expiryDate', '')), '');
    if v_expiry_date is not null then
      if v_expiry_date !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'POS_INVENTORY_EXPIRY_INVALID' using errcode = '22023';
      end if;
      begin
        v_parsed_expiry := to_date(v_expiry_date, 'YYYY-MM-DD');
        if to_char(v_parsed_expiry, 'YYYY-MM-DD') <> v_expiry_date then
          raise exception 'POS_INVENTORY_EXPIRY_INVALID' using errcode = '22023';
        end if;
      exception
        when others then
          raise exception 'POS_INVENTORY_EXPIRY_INVALID' using errcode = '22023';
      end;
    end if;
  end loop;

  delete from public.pos_inventory_items
  where restaurant_id = p_restaurant_id;

  for v_elem in select value from jsonb_array_elements(p_items)
  loop
    v_id := btrim(v_elem ->> 'id');
    v_name := btrim(v_elem ->> 'name');
    v_category := btrim(coalesce(v_elem ->> 'category', '기타'));
    v_current_qty := (v_elem ->> 'currentQty')::integer;
    v_min_threshold := (v_elem ->> 'minThreshold')::integer;
    v_unit := btrim(coalesce(v_elem ->> 'unit', '인분'));
    v_expiry_date := nullif(btrim(coalesce(v_elem ->> 'expiryDate', '')), '');
    v_recipe_unit := coalesce((v_elem ->> 'recipeUnitPerServing')::integer, 1);

    if v_elem ? 'linkedMenuNames' and jsonb_typeof(v_elem -> 'linkedMenuNames') = 'array' then
      select coalesce(array_agg(btrim(x)) filter (where char_length(btrim(x)) > 0), '{}'::text[])
      into v_linked
      from jsonb_array_elements_text(v_elem -> 'linkedMenuNames') as t(x);
    else
      v_linked := '{}'::text[];
    end if;

    insert into public.pos_inventory_items (
      id,
      restaurant_id,
      name,
      category,
      current_qty,
      min_threshold,
      unit,
      linked_menu_names,
      expiry_date,
      recipe_unit_per_serving,
      updated_at
    )
    values (
      v_id,
      p_restaurant_id,
      v_name,
      v_category,
      v_current_qty,
      v_min_threshold,
      v_unit,
      v_linked,
      v_expiry_date,
      v_recipe_unit,
      now()
    );
  end loop;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', i.id,
        'name', i.name,
        'category', i.category,
        'currentQty', i.current_qty,
        'minThreshold', i.min_threshold,
        'unit', i.unit,
        'linkedMenuNames', to_jsonb(i.linked_menu_names),
        'expiryDate', i.expiry_date,
        'recipeUnitPerServing', i.recipe_unit_per_serving,
        'updatedAt', i.updated_at
      )
      order by i.id
    ),
    '[]'::jsonb
  )
  into v_result
  from public.pos_inventory_items i
  where i.restaurant_id = p_restaurant_id;

  return v_result;
end;
$$;

-- 8. Atomic RPC: transition_order_to_preparing_with_bom
create or replace function public.transition_order_to_preparing_with_bom(
  p_order_id uuid,
  p_restaurant_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, pg_temp
as $$
declare
  v_order_status text;
  v_order_restaurant_id uuid;
  v_order_updated_at timestamptz;
  v_existing_deduction jsonb;
  v_inv record;
  v_oi record;
  v_deduct_total integer;
  v_linked_name text;
  v_is_matched boolean;
  v_deducted_list jsonb := '[]'::jsonb;
begin
  if p_order_id is null or p_restaurant_id is null then
    raise exception 'POS_ORDER_INVALID_ARGUMENTS' using errcode = '22023';
  end if;

  -- Serialize with inventory replacements and concurrent order transitions
  -- on the same restaurant.
  perform 1
  from public.restaurants
  where id = p_restaurant_id
  for update;

  if not found then
    raise exception 'POS_RESTAURANT_NOT_FOUND' using errcode = 'P0002';
  end if;

  select status::text, restaurant_id, updated_at
  into v_order_status, v_order_restaurant_id, v_order_updated_at
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'POS_ORDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_order_restaurant_id <> p_restaurant_id then
    raise exception 'POS_ORDER_RESTAURANT_MISMATCH' using errcode = '42501';
  end if;

  -- Idempotent retry: already transitioned to PREPARING
  if v_order_status = 'PREPARING' then
    select deducted_items
    into v_existing_deduction
    from public.pos_inventory_deductions
    where order_id = p_order_id;

    return jsonb_build_object(
      'id', p_order_id,
      'status', v_order_status,
      'updatedAt', v_order_updated_at,
      'alreadyApplied', true,
      'deductedItems', coalesce(v_existing_deduction, '[]'::jsonb)
    );
  end if;

  if v_order_status <> 'PAID' then
    raise exception 'INVALID_ORDER_STATUS_TRANSITION:%', v_order_status
      using errcode = 'P0001';
  end if;

  -- Check if deduction record already exists for this order_id (extra guard)
  select deducted_items
  into v_existing_deduction
  from public.pos_inventory_deductions
  where order_id = p_order_id
  for update;

  if not found then
    for v_inv in
      select
        id,
        name,
        current_qty,
        unit,
        linked_menu_names,
        recipe_unit_per_serving
      from public.pos_inventory_items
      where restaurant_id = p_restaurant_id
      order by id
      for update
    loop
      v_deduct_total := 0;

      for v_oi in
        select
          oi.quantity,
          coalesce(mi.name, '') as menu_name
        from public.order_items oi
        join public.menu_items mi on mi.id = oi.menu_item_id
        where oi.order_id = p_order_id
      loop
        v_is_matched := false;

        if lower(v_oi.menu_name) <> '' and lower(btrim(v_inv.name)) <> ''
           and strpos(lower(v_oi.menu_name), lower(btrim(v_inv.name))) > 0 then
          v_is_matched := true;
        end if;

        if not v_is_matched and coalesce(array_length(v_inv.linked_menu_names, 1), 0) > 0 then
          foreach v_linked_name in array v_inv.linked_menu_names
          loop
            if char_length(btrim(v_linked_name)) > 0 and (
              strpos(lower(v_oi.menu_name), lower(btrim(v_linked_name))) > 0
              or strpos(lower(btrim(v_linked_name)), lower(v_oi.menu_name)) > 0
            ) then
              v_is_matched := true;
              exit;
            end if;
          end loop;
        end if;

        if v_is_matched then
          v_deduct_total := v_deduct_total + (v_inv.recipe_unit_per_serving * v_oi.quantity);
        end if;
      end loop;

      if v_deduct_total > 0 then
        if v_inv.current_qty < v_deduct_total then
          raise exception 'POS_INVENTORY_INSUFFICIENT:%:need=%:have=%',
            v_inv.name,
            v_deduct_total,
            v_inv.current_qty
            using errcode = 'P0001';
        end if;

        update public.pos_inventory_items
        set current_qty = current_qty - v_deduct_total,
            updated_at = now()
        where restaurant_id = p_restaurant_id
          and id = v_inv.id;

        v_deducted_list := v_deducted_list || jsonb_build_array(
          jsonb_build_object(
            'inventoryId', v_inv.id,
            'name', v_inv.name,
            'deductedQty', v_deduct_total,
            'remainingQty', v_inv.current_qty - v_deduct_total,
            'unit', v_inv.unit
          )
        );
      end if;
    end loop;

    insert into public.pos_inventory_deductions (
      order_id,
      restaurant_id,
      deducted_items,
      created_at
    )
    values (
      p_order_id,
      p_restaurant_id,
      v_deducted_list,
      now()
    );
  else
    v_deducted_list := v_existing_deduction;
  end if;

  update public.orders
  set status = 'PREPARING',
      updated_at = now()
  where id = p_order_id
    and status::text = 'PAID'
  returning updated_at into v_order_updated_at;

  if not found then
    raise exception 'ORDER_STATUS_CHANGED' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'id', p_order_id,
    'status', 'PREPARING',
    'updatedAt', v_order_updated_at,
    'alreadyApplied', false,
    'deductedItems', v_deducted_list
  );
end;
$$;

-- 10. Row Level Security & explicit privilege lockdown
alter table public.pos_inventory_items enable row level security;
alter table public.pos_inventory_deductions enable row level security;
alter table public.session_cart_items enable row level security;

revoke all on table
  public.pos_inventory_items,
  public.pos_inventory_deductions,
  public.session_cart_items
from public, anon, authenticated, service_role;

grant select, insert, update, delete on table
  public.pos_inventory_items,
  public.pos_inventory_deductions,
  public.session_cart_items
to service_role;

revoke all on function public.replace_pos_inventory_items(uuid, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.replace_pos_inventory_items(uuid, jsonb, jsonb)
  to service_role;

revoke all on function public.transition_order_to_preparing_with_bom(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.transition_order_to_preparing_with_bom(uuid, uuid)
  to service_role;


-- Immutable order cart snapshot and durable post-payment consumption marker.
alter table public.orders add column if not exists cart_snapshot jsonb not null default '[]'::jsonb;
alter table public.orders add column if not exists cart_consumed_at timestamptz;
alter table public.orders add constraint orders_cart_snapshot_array check (jsonb_typeof(cart_snapshot) = 'array');

create or replace function public.set_session_cart_updated_at()
returns trigger language plpgsql security invoker
set search_path = pg_catalog, pg_temp as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;
drop trigger if exists session_cart_set_updated_at on public.session_cart_items;
create trigger session_cart_set_updated_at before insert or update on public.session_cart_items
for each row execute function public.set_session_cart_updated_at();

-- Keep the six-argument legacy RPC intact; all v2 callers use this transaction.
create or replace function public.create_order_with_options(
  p_session_id uuid, p_user_id uuid, p_restaurant_id uuid,
  p_total_price integer, p_payment_method text, p_items json,
  p_dining_type text default 'DINE_IN', p_customer_note text default null
)
returns json language plpgsql security invoker
set search_path = pg_catalog, pg_temp as $$
declare
  v_result json;
  v_order_id uuid;
  v_snapshot jsonb;
begin
  if p_dining_type is null or p_dining_type not in ('DINE_IN', 'TAKEOUT') then
    raise exception 'ORDER_DINING_TYPE_INVALID' using errcode = '22023';
  end if;
  if p_customer_note is not null and char_length(p_customer_note) > 300 then
    raise exception 'ORDER_CUSTOMER_NOTE_INVALID' using errcode = '22023';
  end if;
  -- Lock cart rows before creating the order; concurrent edits receive a fresh
  -- DB timestamp and never masquerade as the captured generation.
  perform 1 from public.session_cart_items
  where session_id = p_session_id and user_id = p_user_id
  order by menu_item_id for update;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id, 'menuItemId', c.menu_item_id,
    'quantity', least(c.quantity, q.quantity), 'updatedAt', c.updated_at
  )), '[]'::jsonb) into v_snapshot
  from public.session_cart_items c
  join (
    select (value ->> 'menuItemId')::uuid menu_id,
      sum((value ->> 'quantity')::integer)::integer quantity
    from json_array_elements(p_items) group by 1
  ) q on q.menu_id = c.menu_item_id
  where c.session_id = p_session_id and c.user_id = p_user_id;
  v_result := public.create_order_with_items(
    p_session_id,p_user_id,p_restaurant_id,p_total_price,p_payment_method,p_items);
  v_order_id := (v_result ->> 'id')::uuid;
  update public.orders set dining_type=p_dining_type,
    customer_note=nullif(btrim(p_customer_note),''), cart_snapshot=v_snapshot
  where id=v_order_id;
  return (v_result::jsonb || jsonb_build_object(
    'diningType',p_dining_type,'customerNote',nullif(btrim(p_customer_note),'')))::json;
end;
$$;

-- Remove unsafe legacy API: replaying caller-supplied quantities could erase
-- new cart items on a repeated payment confirmation.
drop function if exists public.consume_ordered_session_cart_items(uuid,uuid,jsonb);
create or replace function public.consume_ordered_session_cart_items(p_order_id uuid)
returns void language plpgsql security invoker
set search_path = pg_catalog, pg_temp as $$
declare
  v_order public.orders%rowtype;
  v_item jsonb;
  v_row public.session_cart_items%rowtype;
  v_qty integer;
begin
  select * into v_order from public.orders where id=p_order_id for update;
  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode='P0002';
  end if;
  if v_order.cart_consumed_at is not null then return; end if;
  if v_order.status::text not in ('PAID','ACCEPTED','PREPARING','READY','DONE','COMPLETED') then
    raise exception 'ORDER_NOT_PAID' using errcode='P0001';
  end if;
  for v_item in select value from jsonb_array_elements(v_order.cart_snapshot)
    order by value ->> 'menuItemId'
  loop
    select * into v_row from public.session_cart_items
    where id=(v_item ->> 'id')::uuid and session_id=v_order.session_id
      and user_id=v_order.user_id and menu_item_id=(v_item ->> 'menuItemId')::uuid
    for update;
    -- Deliberately preserve the entire row if edited after order creation.
    if found and v_row.updated_at=(v_item ->> 'updatedAt')::timestamptz then
      v_qty := (v_item ->> 'quantity')::integer;
      if v_row.quantity <= v_qty then
        delete from public.session_cart_items where id=v_row.id;
      else
        update public.session_cart_items set quantity=quantity-v_qty where id=v_row.id;
      end if;
    end if;
  end loop;
  update public.orders set cart_consumed_at=clock_timestamp() where id=p_order_id;
end;
$$;
revoke all on function public.set_session_cart_updated_at() from public,anon,authenticated;
revoke all on function public.create_order_with_options(uuid,uuid,uuid,integer,text,json,text,text) from public,anon,authenticated;
grant execute on function public.create_order_with_options(uuid,uuid,uuid,integer,text,json,text,text) to service_role;
revoke all on function public.consume_ordered_session_cart_items(uuid) from public,anon,authenticated;
grant execute on function public.consume_ordered_session_cart_items(uuid) to service_role;
