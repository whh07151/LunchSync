-- LunchSync database source of truth for a fresh Supabase project.
--
-- This schema intentionally contains no user or demonstration data. The
-- NestJS backend is the only application component that talks to Supabase and
-- does so with a service-role client. Consequently, every application table
-- has RLS enabled, Data API access is denied to browser roles, and only the
-- service role receives the table and RPC privileges it needs.

create type public.user_role as enum (
  'CUSTOMER',
  'OWNER',
  'POS'
);

create type public.user_status as enum (
  'PENDING',
  'APPROVED',
  'REJECTED'
);

create type public.auth_provider_type as enum (
  'KAKAO',
  'EMAIL',
  'PHONE'
);

create type public.session_status as enum (
  'WAITING',
  'VOTING',
  'ORDERED',
  'DONE'
);

create type public.order_status as enum (
  'PENDING',
  'PAID',
  'ACCEPTED',
  'PREPARING',
  'READY',
  'DONE',
  'COMPLETED',
  'CANCELLED',
  'REFUNDED'
);

create type public.payment_method_type as enum (
  'TOSS',
  'CARD',
  'CASH',
  'SIMULATE',
  'POS_TOSS',
  'POS_CASH'
);

create table public.users (
  id uuid primary key default gen_random_uuid(),
  kakao_id text,
  name text not null,
  org text,
  profile_image text,
  radius text default '500m',
  budget integer,
  speed text,
  role public.user_role not null default 'CUSTOMER',
  status public.user_status not null default 'APPROVED',
  auth_provider public.auth_provider_type not null default 'KAKAO',
  email text,
  password_hash text,
  phone_number text,
  email_verified_at timestamptz,
  phone_verified_at timestamptz,
  business_name text,
  business_number text,
  restaurant_id uuid,
  allergies text[] not null default '{}',
  dislikes text[] not null default '{}',
  taste_tags text[] not null default '{}',
  allergens text[] not null default '{}',
  disliked_categories text[] not null default '{}',
  fcm_token text,
  favorites jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint users_budget_nonnegative check (budget is null or budget >= 0),
  constraint users_favorites_is_array check (jsonb_typeof(favorites) = 'array')
);

create unique index users_kakao_id_key
  on public.users (kakao_id)
  where kakao_id is not null;

create unique index users_email_key
  on public.users (lower(email))
  where email is not null;

create unique index users_phone_number_key
  on public.users (phone_number)
  where phone_number is not null;

create unique index users_business_number_key
  on public.users (business_number)
  where business_number is not null;

create index users_role_status_idx
  on public.users (role, status);

create index users_favorites_idx
  on public.users using gin (favorites);

create table public.restaurants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  lat numeric(10, 8),
  lng numeric(11, 8),
  category text,
  price_range integer,
  address text,
  image_url text,
  rating numeric(2, 1),
  todays_note text,
  business_status text not null default 'OPEN',
  operating_hours_note text not null
    default '영업 11:00~21:00 · 브레이크타임 15:00~17:00',
  owner_user_id uuid references public.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint restaurants_lat_range check (lat is null or lat between -90 and 90),
  constraint restaurants_lng_range check (lng is null or lng between -180 and 180),
  constraint restaurants_price_range_nonnegative
    check (price_range is null or price_range >= 0),
  constraint restaurants_rating_range
    check (rating is null or rating between 0 and 5),
  constraint restaurants_business_status_allowed
    check (business_status in ('OPEN', 'BREAK_TIME', 'CLOSED')),
  constraint restaurants_operating_hours_note_length
    check (char_length(operating_hours_note) <= 200)
);

create unique index restaurants_owner_user_id_key
  on public.restaurants (owner_user_id)
  where owner_user_id is not null;

create index restaurants_location_idx
  on public.restaurants (lat, lng)
  where lat is not null and lng is not null;

alter table public.users
  add constraint users_restaurant_id_fkey
  foreign key (restaurant_id)
  references public.restaurants (id)
  on delete set null;

create index users_restaurant_id_idx
  on public.users (restaurant_id)
  where restaurant_id is not null;

create table public.menu_items (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null
    references public.restaurants (id) on delete cascade,
  name text not null,
  price integer not null,
  category text,
  description text,
  image_url text,
  is_available boolean not null default true,
  ingredients text[] not null default '{}',
  allergens text[] not null default '{}',
  source text not null default 'MANUAL',
  prep_time_minutes integer not null default 15,
  constraint menu_items_price_nonnegative check (price >= 0),
  constraint menu_items_source_allowed
    check (source in ('CRAWL_NAVER', 'AI_GEMINI', 'MANUAL')),
  constraint menu_items_prep_time_range
    check (prep_time_minutes between 1 and 120)
);

create index menu_items_restaurant_available_idx
  on public.menu_items (restaurant_id, is_available);

create index menu_items_allergens_idx
  on public.menu_items using gin (allergens);

create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  status public.session_status not null default 'WAITING',
  created_by uuid not null references public.users (id),
  winner_restaurant_id uuid
    references public.restaurants (id) on delete set null,
  scheduled_at timestamptz,
  radius integer,
  budget integer,
  return_minutes integer,
  memo text,
  lat numeric(10, 8),
  lng numeric(11, 8),
  created_at timestamptz not null default now(),
  constraint sessions_radius_positive check (radius is null or radius > 0),
  constraint sessions_budget_nonnegative check (budget is null or budget >= 0),
  constraint sessions_return_minutes_positive
    check (return_minutes is null or return_minutes > 0),
  constraint sessions_lat_range check (lat is null or lat between -90 and 90),
  constraint sessions_lng_range check (lng is null or lng between -180 and 180)
);

create index sessions_created_by_created_at_idx
  on public.sessions (created_by, created_at desc);

create index sessions_winner_restaurant_id_idx
  on public.sessions (winner_restaurant_id)
  where winner_restaurant_id is not null;

create index sessions_status_idx
  on public.sessions (status);

create table public.session_members (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null
    references public.sessions (id) on delete cascade,
  user_id uuid not null
    references public.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  constraint session_members_session_user_key unique (session_id, user_id)
);

create index session_members_user_id_idx
  on public.session_members (user_id);

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null
    references public.sessions (id) on delete cascade,
  invite_code text not null unique,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index invitations_session_id_idx
  on public.invitations (session_id);

create index invitations_expires_at_idx
  on public.invitations (expires_at);

create table public.votes (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null
    references public.sessions (id) on delete cascade,
  user_id uuid not null
    references public.users (id) on delete cascade,
  restaurant_id uuid not null
    references public.restaurants (id),
  created_at timestamptz not null default now(),
  constraint votes_user_session_key unique (user_id, session_id)
);

create index votes_session_restaurant_idx
  on public.votes (session_id, restaurant_id);

create index votes_restaurant_id_idx
  on public.votes (restaurant_id);

create table public.cart_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    references public.users (id) on delete cascade,
  session_id uuid not null
    references public.sessions (id) on delete cascade,
  menu_item_id uuid not null
    references public.menu_items (id),
  quantity integer not null default 1,
  updated_at timestamptz not null default now(),
  constraint cart_items_quantity_positive check (quantity > 0),
  constraint cart_items_user_session_menu_key
    unique (user_id, session_id, menu_item_id)
);

create index cart_items_session_id_idx
  on public.cart_items (session_id);

create index cart_items_menu_item_id_idx
  on public.cart_items (menu_item_id);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id),
  user_id uuid not null references public.users (id),
  restaurant_id uuid not null references public.restaurants (id),
  status public.order_status not null default 'PENDING',
  total_price integer not null,
  payment_method public.payment_method_type,
  payment_key text,
  dining_type text not null default 'DINE_IN',
  customer_note text,
  completion_photo_url text,
  review_score integer,
  review_text text,
  review_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint orders_total_price_nonnegative check (total_price >= 0),
  constraint orders_dining_type_allowed
    check (dining_type in ('DINE_IN', 'TAKEOUT')),
  constraint orders_customer_note_length
    check (customer_note is null or char_length(customer_note) <= 300),
  constraint orders_review_score_range
    check (review_score is null or review_score between 1 and 5),
  constraint orders_review_text_length
    check (review_text is null or char_length(review_text) <= 500)
);

create index orders_session_id_idx
  on public.orders (session_id);

create index orders_user_created_at_idx
  on public.orders (user_id, created_at desc);

create index orders_restaurant_created_at_idx
  on public.orders (restaurant_id, created_at desc);

create index orders_restaurant_status_payment_idx
  on public.orders (restaurant_id, status, payment_method);

create index orders_loyalty_ranking_idx
  on public.orders (user_id, restaurant_id, status);

create index orders_restaurant_review_idx
  on public.orders (restaurant_id, review_score)
  where review_score is not null;

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  menu_item_id uuid not null references public.menu_items (id),
  quantity integer not null,
  price integer not null,
  constraint order_items_quantity_positive check (quantity > 0),
  constraint order_items_price_nonnegative check (price >= 0)
);

create index order_items_order_id_idx
  on public.order_items (order_id);

create index order_items_menu_item_id_idx
  on public.order_items (menu_item_id);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users (id) on delete cascade,
  type text not null,
  title text,
  message text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index notifications_user_created_at_idx
  on public.notifications (user_id, created_at desc);

create index notifications_user_unread_idx
  on public.notifications (user_id, created_at desc)
  where not is_read;

create table public.friends (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users (id) on delete cascade,
  friend_user_id uuid not null
    references public.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint friends_user_friend_key unique (user_id, friend_user_id),
  constraint friends_not_self check (user_id <> friend_user_id)
);

create index friends_user_created_at_idx
  on public.friends (user_id, created_at desc);

create index friends_friend_user_id_idx
  on public.friends (friend_user_id);

create table public.pos_seats (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null
    references public.restaurants (id) on delete cascade,
  label text not null,
  status text not null default 'empty',
  started_at timestamptz,
  items jsonb not null default '[]'::jsonb,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pos_seats_status_allowed
    check (status in ('empty', 'occupied')),
  constraint pos_seats_items_is_array check (jsonb_typeof(items) = 'array')
);

create index pos_seats_restaurant_sort_idx
  on public.pos_seats (restaurant_id, sort_order);

create table public.pos_reservations (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null
    references public.restaurants (id) on delete cascade,
  order_id uuid references public.orders (id) on delete set null,
  kind text not null,
  customer_name text not null,
  party_size integer not null,
  scheduled_at timestamptz,
  note text,
  status text not null default 'OPEN',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pos_reservations_kind_allowed
    check (kind in ('WAITING', 'RESERVATION')),
  constraint pos_reservations_party_size_positive check (party_size > 0),
  constraint pos_reservations_status_allowed
    check (status in ('OPEN', 'SEATED', 'CANCELLED')),
  constraint pos_reservations_schedule_consistent
    check (
      (kind = 'WAITING' and scheduled_at is null)
      or (kind = 'RESERVATION' and scheduled_at is not null)
    )
);

create unique index pos_reservations_order_id_key
  on public.pos_reservations (order_id)
  where order_id is not null;

create index pos_reservations_restaurant_created_at_idx
  on public.pos_reservations (restaurant_id, created_at desc);

create index pos_reservations_open_idx
  on public.pos_reservations (restaurant_id, status)
  where status = 'OPEN';

create table public.tournament_results (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users (id),
  mode text not null,
  winner_restaurant_id uuid references public.restaurants (id),
  winner_menu_id uuid references public.menu_items (id),
  candidate_count integer,
  duration_ms integer,
  created_at timestamptz not null default now(),
  constraint tournament_results_mode_allowed
    check (mode in ('restaurant', 'menu')),
  constraint tournament_results_candidate_count_valid
    check (candidate_count is null or candidate_count >= 2),
  constraint tournament_results_duration_nonnegative
    check (duration_ms is null or duration_ms >= 0),
  constraint tournament_results_winner_consistent
    check (
      (mode = 'restaurant' and winner_restaurant_id is not null)
      or
      (mode = 'menu' and winner_restaurant_id is not null
       and winner_menu_id is not null)
    )
);

create index tournament_results_user_id_idx
  on public.tournament_results (user_id);

create index tournament_results_created_at_idx
  on public.tournament_results (created_at desc);

create index tournament_results_winner_restaurant_id_idx
  on public.tournament_results (winner_restaurant_id);

create index tournament_results_winner_menu_id_idx
  on public.tournament_results (winner_menu_id);

create table public.pos_inventory_items (
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
  primary key (restaurant_id, id),
  constraint pos_inventory_items_id_length
    check (char_length(btrim(id)) between 1 and 64),
  constraint pos_inventory_items_name_length
    check (char_length(btrim(name)) between 1 and 100),
  constraint pos_inventory_items_category_length
    check (char_length(btrim(category)) between 1 and 50),
  constraint pos_inventory_items_current_qty_range
    check (current_qty between 0 and 100000),
  constraint pos_inventory_items_min_threshold_range
    check (min_threshold between 0 and 100000),
  constraint pos_inventory_items_unit_length
    check (char_length(btrim(unit)) between 1 and 20),
  constraint pos_inventory_items_linked_menus_max
    check (coalesce(array_length(linked_menu_names, 1), 0) <= 50),
  constraint pos_inventory_items_expiry_date_format
    check (expiry_date is null or expiry_date ~ '^\d{4}-\d{2}-\d{2}$'),
  constraint pos_inventory_items_recipe_unit_range
    check (recipe_unit_per_serving between 1 and 10000)
);

create table public.pos_inventory_deductions (
  order_id uuid primary key
    references public.orders (id) on delete cascade,
  restaurant_id uuid not null
    references public.restaurants (id) on delete cascade,
  deducted_items jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  constraint pos_inventory_deductions_items_is_array
    check (jsonb_typeof(deducted_items) = 'array')
);

create index pos_inventory_deductions_restaurant_id_idx
  on public.pos_inventory_deductions (restaurant_id, created_at desc);

create table public.session_cart_items (
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
  unique (session_id, user_id, menu_item_id),
  constraint session_cart_items_user_name_length
    check (char_length(btrim(user_name)) between 1 and 80),
  constraint session_cart_items_menu_name_length
    check (char_length(btrim(menu_name)) between 1 and 120),
  constraint session_cart_items_price_nonnegative
    check (price >= 0),
  constraint session_cart_items_quantity_range
    check (quantity between 1 and 99)
);

create index session_cart_items_session_updated_idx
  on public.session_cart_items (session_id, updated_at asc);

create function public.set_restaurants_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger restaurants_set_updated_at
before update on public.restaurants
for each row execute function public.set_restaurants_updated_at();

create function public.set_orders_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger orders_set_updated_at
before update on public.orders
for each row execute function public.set_orders_updated_at();

create function public.create_session_with_host_member(
  p_name text,
  p_created_by uuid,
  p_scheduled_at timestamptz default null,
  p_radius integer default null,
  p_budget integer default null,
  p_return_minutes integer default null,
  p_memo text default null,
  p_lat numeric default null,
  p_lng numeric default null
)
returns json
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_session_id uuid;
  v_creator_name text;
  v_result json;
begin
  insert into public.sessions (
    name,
    created_by,
    scheduled_at,
    radius,
    budget,
    return_minutes,
    memo,
    lat,
    lng
  )
  values (
    p_name,
    p_created_by,
    p_scheduled_at,
    p_radius,
    p_budget,
    p_return_minutes,
    p_memo,
    p_lat,
    p_lng
  )
  returning id into v_session_id;

  insert into public.session_members (session_id, user_id)
  values (v_session_id, p_created_by);

  select name
  into v_creator_name
  from public.users
  where id = p_created_by;

  select json_build_object(
    'id', s.id,
    'name', s.name,
    'status', s.status,
    'scheduledAt', s.scheduled_at,
    'radius', s.radius,
    'budget', s.budget,
    'returnMinutes', s.return_minutes,
    'memo', s.memo,
    'lat', s.lat,
    'lng', s.lng,
    'memberCount', 1,
    'createdBy', json_build_object(
      'id', p_created_by,
      'name', v_creator_name
    )
  )
  into v_result
  from public.sessions s
  where s.id = v_session_id;

  return v_result;
end;
$$;

create function public.delete_session_cascade(p_session_id uuid)
returns json
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_status public.session_status;
  v_deleted_at timestamptz;
begin
  select status
  into v_status
  from public.sessions
  where id = p_session_id
  for update;

  if not found then
    return null;
  end if;

  if v_status not in ('WAITING', 'DONE') then
    raise exception
      'SESSION_NOT_DELETABLE: session % is in state %',
      p_session_id,
      v_status
      using errcode = 'P0001';
  end if;

  delete from public.orders where session_id = p_session_id;
  delete from public.votes where session_id = p_session_id;
  delete from public.session_members where session_id = p_session_id;
  delete from public.sessions where id = p_session_id;

  v_deleted_at := now();

  return json_build_object(
    'deletedSessionId', p_session_id,
    'deletedAt', v_deleted_at
  );
end;
$$;

create function public.create_order_with_items(
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

drop function if exists public.replace_pos_inventory_items(uuid,jsonb);
create function public.replace_pos_inventory_items(
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

create function public.transition_order_to_preparing_with_bom(
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



create function public.check_schema_resources()
returns json
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_columns json;
  v_tables json;
  v_functions json;
begin
  with expected(table_name, column_name) as (
    values
      ('restaurants', 'image_url'),
      ('restaurants', 'rating'),
      ('users', 'fcm_token'),
      ('sessions', 'radius'),
      ('sessions', 'budget'),
      ('sessions', 'return_minutes'),
      ('sessions', 'memo')
  )
  select json_agg(
    json_build_object(
      'table', e.table_name,
      'column', e.column_name,
      'present', c.column_name is not null
    )
    order by e.table_name, e.column_name
  )
  into v_columns
  from expected e
  left join information_schema.columns c
    on c.table_schema = 'public'
   and c.table_name = e.table_name
   and c.column_name = e.column_name;

  with expected(table_name) as (
    values ('pos_seats'), ('pos_reservations')
  )
  select json_agg(
    json_build_object(
      'table', e.table_name,
      'present', t.table_name is not null
    )
    order by e.table_name
  )
  into v_tables
  from expected e
  left join information_schema.tables t
    on t.table_schema = 'public'
   and t.table_name = e.table_name;

  with expected(
    routine_name,
    required_argument_names,
    required_argument_types,
    required_return_type
  ) as (
    values
      (
        'delete_session_cascade',
        null::text[],
        null::text[],
        null::text
      ),
      (
        'create_order_with_items',
        array[
          'p_session_id',
          'p_user_id',
          'p_restaurant_id',
          'p_total_price',
          'p_payment_method',
          'p_items'
        ]::text[],
        array[
          'uuid',
          'uuid',
          'uuid',
          'integer',
          'text',
          'json'
        ]::text[],
        'json'
      ),
      (
        'create_session_with_host_member',
        null::text[],
        null::text[],
        null::text
      )
  )
  select json_agg(
    json_build_object(
      'name', e.routine_name,
      'signature',
        case
          when candidate.oid is null then null
          else
            'public.' || e.routine_name || '('
            || replace(oidvectortypes(candidate.proargtypes), ', ', ',')
            || ')'
        end,
      'parameters',
        case
          when candidate.oid is null then null
          else (
            select json_agg(
              json_build_object(
                'name', candidate.proargnames[arg.position::integer],
                'type', format_type(arg.type_oid, null)
              )
              order by arg.position
            )
            from unnest(candidate.proargtypes)
              with ordinality as arg(type_oid, position)
          )
        end,
      'returnType',
        case
          when candidate.oid is null then null
          else format_type(candidate.prorettype, null)
        end,
      'contract',
        case
          when e.required_argument_types is null then null
          else json_build_object(
            'parameters', (
              select json_agg(
                json_build_object(
                  'name', e.required_argument_names[position],
                  'type', e.required_argument_types[position]
                )
                order by position
              )
              from generate_subscripts(
                e.required_argument_types,
                1
              ) as position
            ),
            'returnType', e.required_return_type
          )
        end,
      'present',
        candidate.oid is not null
        and (
          e.required_argument_types is null
          or (
            candidate.proargnames = e.required_argument_names
            and array(
              select format_type(type_oid, null)
              from unnest(candidate.proargtypes) as type_oid
            ) = e.required_argument_types
            and format_type(candidate.prorettype, null)
              = e.required_return_type
          )
        )
    )
    order by e.routine_name
  )
  into v_functions
  from expected e
  left join lateral (
    select p.oid, p.proargnames, p.proargtypes, p.prorettype
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = e.routine_name
    order by (
      e.required_argument_types is null
      or (
        p.proargnames = e.required_argument_names
        and array(
          select format_type(type_oid, null)
          from unnest(p.proargtypes) as type_oid
        ) = e.required_argument_types
        and format_type(p.prorettype, null) = e.required_return_type
      )
    ) desc, p.oid
    limit 1
  ) candidate on true;

  return json_build_object(
    'columns', v_columns,
    'tables', v_tables,
    'functions', v_functions
  );
end;
$$;

alter table public.users enable row level security;
alter table public.restaurants enable row level security;
alter table public.menu_items enable row level security;
alter table public.sessions enable row level security;
alter table public.session_members enable row level security;
alter table public.invitations enable row level security;
alter table public.votes enable row level security;
alter table public.cart_items enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.notifications enable row level security;
alter table public.friends enable row level security;
alter table public.pos_seats enable row level security;
alter table public.pos_reservations enable row level security;
alter table public.tournament_results enable row level security;
alter table public.pos_inventory_items enable row level security;
alter table public.pos_inventory_deductions enable row level security;
alter table public.session_cart_items enable row level security;

revoke all on all tables in schema public
  from public, anon, authenticated, service_role;
grant select, insert, update, delete
  on table
    public.users,
    public.restaurants,
    public.menu_items,
    public.sessions,
    public.session_members,
    public.invitations,
    public.votes,
    public.cart_items,
    public.orders,
    public.order_items,
    public.notifications,
    public.friends,
    public.pos_seats,
    public.pos_reservations,
    public.tournament_results,
    public.pos_inventory_items,
    public.pos_inventory_deductions,
    public.session_cart_items
  to service_role;

grant usage
  on type
    public.user_role,
    public.user_status,
    public.auth_provider_type,
    public.session_status,
    public.order_status,
    public.payment_method_type
  to service_role;

revoke all on function public.set_restaurants_updated_at()
  from public, anon, authenticated;
revoke all on function public.set_orders_updated_at()
  from public, anon, authenticated;

revoke all on function public.create_session_with_host_member(
  text,
  uuid,
  timestamptz,
  integer,
  integer,
  integer,
  text,
  numeric,
  numeric
) from public, anon, authenticated;

revoke all on function public.delete_session_cascade(uuid)
  from public, anon, authenticated;

revoke all on function public.create_order_with_items(
  uuid,
  uuid,
  uuid,
  integer,
  text,
  json
) from public, anon, authenticated;

revoke all on function public.check_schema_resources()
  from public, anon, authenticated;

grant execute on function public.create_session_with_host_member(
  text,
  uuid,
  timestamptz,
  integer,
  integer,
  integer,
  text,
  numeric,
  numeric
) to service_role;

grant execute on function public.delete_session_cascade(uuid)
  to service_role;

grant execute on function public.create_order_with_items(
  uuid,
  uuid,
  uuid,
  integer,
  text,
  json
) to service_role;

grant execute on function public.check_schema_resources()
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
