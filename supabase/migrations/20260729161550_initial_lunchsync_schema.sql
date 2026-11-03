-- Remote migration version assigned by the project-scoped Supabase MCP.
SET check_function_bodies = false;
CREATE TYPE public.auth_provider_type AS ENUM ('KAKAO', 'EMAIL', 'PHONE');
GRANT ALL ON TYPE public.auth_provider_type TO service_role;
CREATE TYPE public.order_status AS ENUM ('PENDING', 'PAID', 'ACCEPTED', 'PREPARING', 'READY', 'DONE', 'COMPLETED', 'CANCELLED', 'REFUNDED');
GRANT ALL ON TYPE public.order_status TO service_role;
CREATE TYPE public.payment_method_type AS ENUM ('TOSS', 'CARD', 'CASH', 'SIMULATE', 'POS_TOSS', 'POS_CASH');
GRANT ALL ON TYPE public.payment_method_type TO service_role;
CREATE TYPE public.session_status AS ENUM ('WAITING', 'VOTING', 'ORDERED', 'DONE');
GRANT ALL ON TYPE public.session_status TO service_role;
CREATE TYPE public.user_role AS ENUM ('CUSTOMER', 'OWNER', 'POS');
GRANT ALL ON TYPE public.user_role TO service_role;
CREATE TYPE public.user_status AS ENUM ('PENDING', 'APPROVED', 'REJECTED');
GRANT ALL ON TYPE public.user_status TO service_role;
CREATE FUNCTION public.check_schema_resources()
 RETURNS json
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
$function$;
GRANT ALL ON FUNCTION public.check_schema_resources() TO service_role;
CREATE FUNCTION public.create_order_with_items(p_session_id uuid, p_user_id uuid, p_restaurant_id uuid, p_total_price integer, p_payment_method text DEFAULT NULL::text, p_items json DEFAULT '[]'::json)
 RETURNS json
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_order_id uuid;
  v_item json;
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
$function$;
GRANT ALL ON FUNCTION public.create_order_with_items(uuid, uuid, uuid, integer, text, json) TO service_role;
CREATE FUNCTION public.create_session_with_host_member(p_name text, p_created_by uuid, p_scheduled_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_radius integer DEFAULT NULL::integer, p_budget integer DEFAULT NULL::integer, p_return_minutes integer DEFAULT NULL::integer, p_memo text DEFAULT NULL::text, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric)
 RETURNS json
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
$function$;
GRANT ALL ON FUNCTION public.create_session_with_host_member(text, uuid, timestamp with time zone, integer, integer, integer, text, numeric, numeric) TO service_role;
CREATE FUNCTION public.delete_session_cascade(p_session_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
$function$;
GRANT ALL ON FUNCTION public.delete_session_cascade(uuid) TO service_role;
CREATE FUNCTION public.set_orders_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;
CREATE FUNCTION public.set_restaurants_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;
CREATE TABLE public.cart_items (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, session_id uuid NOT NULL, menu_item_id uuid NOT NULL, quantity integer DEFAULT 1 NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items ADD CONSTRAINT cart_items_pkey PRIMARY KEY (id);
ALTER TABLE public.cart_items ADD CONSTRAINT cart_items_quantity_positive CHECK (quantity > 0);
ALTER TABLE public.cart_items ADD CONSTRAINT cart_items_user_session_menu_key UNIQUE (user_id, session_id, menu_item_id);
GRANT ALL ON public.cart_items TO service_role;
CREATE INDEX cart_items_session_id_idx ON public.cart_items (session_id);
CREATE INDEX cart_items_menu_item_id_idx ON public.cart_items (menu_item_id);
CREATE TABLE public.friends (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, friend_user_id uuid NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.friends ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friends ADD CONSTRAINT friends_not_self CHECK (user_id <> friend_user_id);
ALTER TABLE public.friends ADD CONSTRAINT friends_pkey PRIMARY KEY (id);
ALTER TABLE public.friends ADD CONSTRAINT friends_user_friend_key UNIQUE (user_id, friend_user_id);
GRANT ALL ON public.friends TO service_role;
CREATE INDEX friends_user_created_at_idx ON public.friends (user_id, created_at DESC);
CREATE INDEX friends_friend_user_id_idx ON public.friends (friend_user_id);
CREATE TABLE public.invitations (id uuid DEFAULT gen_random_uuid() NOT NULL, session_id uuid NOT NULL, invite_code text NOT NULL, expires_at timestamp with time zone NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invitations ADD CONSTRAINT invitations_invite_code_key UNIQUE (invite_code);
ALTER TABLE public.invitations ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);
GRANT ALL ON public.invitations TO service_role;
CREATE INDEX invitations_session_id_idx ON public.invitations (session_id);
CREATE INDEX invitations_expires_at_idx ON public.invitations (expires_at);
CREATE TABLE public.menu_items (id uuid DEFAULT gen_random_uuid() NOT NULL, restaurant_id uuid NOT NULL, name text NOT NULL, price integer NOT NULL, category text, description text, image_url text, is_available boolean DEFAULT true NOT NULL, ingredients text[] DEFAULT '{}'::text[] NOT NULL, allergens text[] DEFAULT '{}'::text[] NOT NULL, source text DEFAULT 'MANUAL'::text NOT NULL, prep_time_minutes integer DEFAULT 15 NOT NULL);
ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menu_items ADD CONSTRAINT menu_items_pkey PRIMARY KEY (id);
ALTER TABLE public.cart_items ADD CONSTRAINT cart_items_menu_item_id_fkey FOREIGN KEY (menu_item_id) REFERENCES public.menu_items(id);
ALTER TABLE public.menu_items ADD CONSTRAINT menu_items_prep_time_range CHECK (prep_time_minutes >= 1 AND prep_time_minutes <= 120);
ALTER TABLE public.menu_items ADD CONSTRAINT menu_items_price_nonnegative CHECK (price >= 0);
ALTER TABLE public.menu_items ADD CONSTRAINT menu_items_source_allowed CHECK (source = ANY (ARRAY['CRAWL_NAVER'::text, 'AI_GEMINI'::text, 'MANUAL'::text]));
GRANT ALL ON public.menu_items TO service_role;
CREATE INDEX menu_items_allergens_idx ON public.menu_items USING gin (allergens);
CREATE INDEX menu_items_restaurant_available_idx ON public.menu_items (restaurant_id, is_available);
CREATE TABLE public.notifications (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, type text NOT NULL, title text, message text, is_read boolean DEFAULT false NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);
GRANT ALL ON public.notifications TO service_role;
CREATE INDEX notifications_user_unread_idx ON public.notifications (user_id, created_at DESC) WHERE NOT is_read;
CREATE INDEX notifications_user_created_at_idx ON public.notifications (user_id, created_at DESC);
CREATE TABLE public.order_items (id uuid DEFAULT gen_random_uuid() NOT NULL, order_id uuid NOT NULL, menu_item_id uuid NOT NULL, quantity integer NOT NULL, price integer NOT NULL);
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ADD CONSTRAINT order_items_menu_item_id_fkey FOREIGN KEY (menu_item_id) REFERENCES public.menu_items(id);
ALTER TABLE public.order_items ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);
ALTER TABLE public.order_items ADD CONSTRAINT order_items_price_nonnegative CHECK (price >= 0);
ALTER TABLE public.order_items ADD CONSTRAINT order_items_quantity_positive CHECK (quantity > 0);
GRANT ALL ON public.order_items TO service_role;
CREATE INDEX order_items_order_id_idx ON public.order_items (order_id);
CREATE INDEX order_items_menu_item_id_idx ON public.order_items (menu_item_id);
CREATE TABLE public.orders (id uuid DEFAULT gen_random_uuid() NOT NULL, session_id uuid NOT NULL, user_id uuid NOT NULL, restaurant_id uuid NOT NULL, status public.order_status DEFAULT 'PENDING'::public.order_status NOT NULL, total_price integer NOT NULL, payment_method public.payment_method_type, payment_key text, completion_photo_url text, review_score integer, review_text text, review_at timestamp with time zone, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ADD CONSTRAINT orders_pkey PRIMARY KEY (id);
ALTER TABLE public.order_items ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
ALTER TABLE public.orders ADD CONSTRAINT orders_review_score_range CHECK (review_score IS NULL OR review_score >= 1 AND review_score <= 5);
ALTER TABLE public.orders ADD CONSTRAINT orders_review_text_length CHECK (review_text IS NULL OR char_length(review_text) <= 500);
ALTER TABLE public.orders ADD CONSTRAINT orders_total_price_nonnegative CHECK (total_price >= 0);
GRANT ALL ON public.orders TO service_role;
CREATE INDEX orders_user_created_at_idx ON public.orders (user_id, created_at DESC);
CREATE INDEX orders_session_id_idx ON public.orders (session_id);
CREATE INDEX orders_restaurant_created_at_idx ON public.orders (restaurant_id, created_at DESC);
CREATE INDEX orders_restaurant_status_payment_idx ON public.orders (restaurant_id, status, payment_method);
CREATE INDEX orders_loyalty_ranking_idx ON public.orders (user_id, restaurant_id, status);
CREATE INDEX orders_restaurant_review_idx ON public.orders (restaurant_id, review_score) WHERE review_score IS NOT NULL;
CREATE TRIGGER orders_set_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.set_orders_updated_at();
CREATE TABLE public.pos_reservations (id uuid DEFAULT gen_random_uuid() NOT NULL, restaurant_id uuid NOT NULL, kind text NOT NULL, customer_name text NOT NULL, party_size integer NOT NULL, scheduled_at timestamp with time zone, note text, status text DEFAULT 'OPEN'::text NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.pos_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_reservations ADD CONSTRAINT pos_reservations_kind_allowed CHECK (kind = ANY (ARRAY['WAITING'::text, 'RESERVATION'::text]));
ALTER TABLE public.pos_reservations ADD CONSTRAINT pos_reservations_party_size_positive CHECK (party_size > 0);
ALTER TABLE public.pos_reservations ADD CONSTRAINT pos_reservations_pkey PRIMARY KEY (id);
ALTER TABLE public.pos_reservations ADD CONSTRAINT pos_reservations_schedule_consistent CHECK (kind = 'WAITING'::text AND scheduled_at IS NULL OR kind = 'RESERVATION'::text AND scheduled_at IS NOT NULL);
ALTER TABLE public.pos_reservations ADD CONSTRAINT pos_reservations_status_allowed CHECK (status = ANY (ARRAY['OPEN'::text, 'SEATED'::text, 'CANCELLED'::text]));
GRANT ALL ON public.pos_reservations TO service_role;
CREATE INDEX pos_reservations_open_idx ON public.pos_reservations (restaurant_id, status) WHERE status = 'OPEN'::text;
CREATE INDEX pos_reservations_restaurant_created_at_idx ON public.pos_reservations (restaurant_id, created_at DESC);
CREATE TABLE public.pos_seats (id uuid DEFAULT gen_random_uuid() NOT NULL, restaurant_id uuid NOT NULL, label text NOT NULL, status text DEFAULT 'empty'::text NOT NULL, started_at timestamp with time zone, items jsonb DEFAULT '[]'::jsonb NOT NULL, sort_order integer DEFAULT 0 NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.pos_seats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_seats ADD CONSTRAINT pos_seats_items_is_array CHECK (jsonb_typeof(items) = 'array'::text);
ALTER TABLE public.pos_seats ADD CONSTRAINT pos_seats_pkey PRIMARY KEY (id);
ALTER TABLE public.pos_seats ADD CONSTRAINT pos_seats_status_allowed CHECK (status = ANY (ARRAY['empty'::text, 'occupied'::text]));
GRANT ALL ON public.pos_seats TO service_role;
CREATE INDEX pos_seats_restaurant_sort_idx ON public.pos_seats (restaurant_id, sort_order);
CREATE TABLE public.restaurants (id uuid DEFAULT gen_random_uuid() NOT NULL, name text NOT NULL, lat numeric(10,8), lng numeric(11,8), category text, price_range integer, address text, image_url text, rating numeric(2,1), todays_note text, owner_user_id uuid, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants ADD CONSTRAINT restaurants_lat_range CHECK (lat IS NULL OR lat >= '-90'::integer::numeric AND lat <= 90::numeric);
ALTER TABLE public.restaurants ADD CONSTRAINT restaurants_lng_range CHECK (lng IS NULL OR lng >= '-180'::integer::numeric AND lng <= 180::numeric);
ALTER TABLE public.restaurants ADD CONSTRAINT restaurants_pkey PRIMARY KEY (id);
ALTER TABLE public.menu_items ADD CONSTRAINT menu_items_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;
ALTER TABLE public.orders ADD CONSTRAINT orders_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id);
ALTER TABLE public.pos_reservations ADD CONSTRAINT pos_reservations_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;
ALTER TABLE public.pos_seats ADD CONSTRAINT pos_seats_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;
ALTER TABLE public.restaurants ADD CONSTRAINT restaurants_price_range_nonnegative CHECK (price_range IS NULL OR price_range >= 0);
ALTER TABLE public.restaurants ADD CONSTRAINT restaurants_rating_range CHECK (rating IS NULL OR rating >= 0::numeric AND rating <= 5::numeric);
GRANT ALL ON public.restaurants TO service_role;
CREATE UNIQUE INDEX restaurants_owner_user_id_key ON public.restaurants (owner_user_id) WHERE owner_user_id IS NOT NULL;
CREATE INDEX restaurants_location_idx ON public.restaurants (lat, lng) WHERE lat IS NOT NULL AND lng IS NOT NULL;
CREATE TRIGGER restaurants_set_updated_at BEFORE UPDATE ON public.restaurants FOR EACH ROW EXECUTE FUNCTION public.set_restaurants_updated_at();
CREATE TABLE public.session_members (id uuid DEFAULT gen_random_uuid() NOT NULL, session_id uuid NOT NULL, user_id uuid NOT NULL, joined_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.session_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_members ADD CONSTRAINT session_members_pkey PRIMARY KEY (id);
ALTER TABLE public.session_members ADD CONSTRAINT session_members_session_user_key UNIQUE (session_id, user_id);
GRANT ALL ON public.session_members TO service_role;
CREATE INDEX session_members_user_id_idx ON public.session_members (user_id);
CREATE TABLE public.sessions (id uuid DEFAULT gen_random_uuid() NOT NULL, name text NOT NULL, status public.session_status DEFAULT 'WAITING'::public.session_status NOT NULL, created_by uuid NOT NULL, winner_restaurant_id uuid, scheduled_at timestamp with time zone, radius integer, budget integer, return_minutes integer, memo text, lat numeric(10,8), lng numeric(11,8), created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions ADD CONSTRAINT sessions_budget_nonnegative CHECK (budget IS NULL OR budget >= 0);
ALTER TABLE public.sessions ADD CONSTRAINT sessions_lat_range CHECK (lat IS NULL OR lat >= '-90'::integer::numeric AND lat <= 90::numeric);
ALTER TABLE public.sessions ADD CONSTRAINT sessions_lng_range CHECK (lng IS NULL OR lng >= '-180'::integer::numeric AND lng <= 180::numeric);
ALTER TABLE public.sessions ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);
ALTER TABLE public.cart_items ADD CONSTRAINT cart_items_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE CASCADE;
ALTER TABLE public.invitations ADD CONSTRAINT invitations_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE CASCADE;
ALTER TABLE public.orders ADD CONSTRAINT orders_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id);
ALTER TABLE public.session_members ADD CONSTRAINT session_members_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE CASCADE;
ALTER TABLE public.sessions ADD CONSTRAINT sessions_radius_positive CHECK (radius IS NULL OR radius > 0);
ALTER TABLE public.sessions ADD CONSTRAINT sessions_return_minutes_positive CHECK (return_minutes IS NULL OR return_minutes > 0);
ALTER TABLE public.sessions ADD CONSTRAINT sessions_winner_restaurant_id_fkey FOREIGN KEY (winner_restaurant_id) REFERENCES public.restaurants(id) ON DELETE SET NULL;
GRANT ALL ON public.sessions TO service_role;
CREATE INDEX sessions_winner_restaurant_id_idx ON public.sessions (winner_restaurant_id) WHERE winner_restaurant_id IS NOT NULL;
CREATE INDEX sessions_created_by_created_at_idx ON public.sessions (created_by, created_at DESC);
CREATE INDEX sessions_status_idx ON public.sessions (status);
CREATE TABLE public.tournament_results (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid, mode text NOT NULL, winner_restaurant_id uuid, winner_menu_id uuid, candidate_count integer, duration_ms integer, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.tournament_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tournament_results ADD CONSTRAINT tournament_results_candidate_count_valid CHECK (candidate_count IS NULL OR candidate_count >= 2);
ALTER TABLE public.tournament_results ADD CONSTRAINT tournament_results_duration_nonnegative CHECK (duration_ms IS NULL OR duration_ms >= 0);
ALTER TABLE public.tournament_results ADD CONSTRAINT tournament_results_mode_allowed CHECK (mode = ANY (ARRAY['restaurant'::text, 'menu'::text]));
ALTER TABLE public.tournament_results ADD CONSTRAINT tournament_results_pkey PRIMARY KEY (id);
ALTER TABLE public.tournament_results ADD CONSTRAINT tournament_results_winner_consistent CHECK (mode = 'restaurant'::text AND winner_restaurant_id IS NOT NULL OR mode = 'menu'::text AND winner_restaurant_id IS NOT NULL AND winner_menu_id IS NOT NULL);
ALTER TABLE public.tournament_results ADD CONSTRAINT tournament_results_winner_menu_id_fkey FOREIGN KEY (winner_menu_id) REFERENCES public.menu_items(id);
ALTER TABLE public.tournament_results ADD CONSTRAINT tournament_results_winner_restaurant_id_fkey FOREIGN KEY (winner_restaurant_id) REFERENCES public.restaurants(id);
GRANT ALL ON public.tournament_results TO service_role;
CREATE INDEX tournament_results_user_id_idx ON public.tournament_results (user_id);
CREATE INDEX tournament_results_winner_menu_id_idx ON public.tournament_results (winner_menu_id);
CREATE INDEX tournament_results_winner_restaurant_id_idx ON public.tournament_results (winner_restaurant_id);
CREATE INDEX tournament_results_created_at_idx ON public.tournament_results (created_at DESC);
CREATE TABLE public.users (id uuid DEFAULT gen_random_uuid() NOT NULL, kakao_id text, name text NOT NULL, org text, profile_image text, radius text DEFAULT '500m'::text, budget integer, speed text, role public.user_role DEFAULT 'CUSTOMER'::public.user_role NOT NULL, status public.user_status DEFAULT 'APPROVED'::public.user_status NOT NULL, auth_provider public.auth_provider_type DEFAULT 'KAKAO'::public.auth_provider_type NOT NULL, email text, password_hash text, phone_number text, email_verified_at timestamp with time zone, phone_verified_at timestamp with time zone, business_name text, business_number text, restaurant_id uuid, allergies text[] DEFAULT '{}'::text[] NOT NULL, dislikes text[] DEFAULT '{}'::text[] NOT NULL, taste_tags text[] DEFAULT '{}'::text[] NOT NULL, allergens text[] DEFAULT '{}'::text[] NOT NULL, disliked_categories text[] DEFAULT '{}'::text[] NOT NULL, fcm_token text, favorites jsonb DEFAULT '[]'::jsonb NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ADD CONSTRAINT users_budget_nonnegative CHECK (budget IS NULL OR budget >= 0);
ALTER TABLE public.users ADD CONSTRAINT users_favorites_is_array CHECK (jsonb_typeof(favorites) = 'array'::text);
ALTER TABLE public.users ADD CONSTRAINT users_pkey PRIMARY KEY (id);
ALTER TABLE public.cart_items ADD CONSTRAINT cart_items_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
ALTER TABLE public.friends ADD CONSTRAINT friends_friend_user_id_fkey FOREIGN KEY (friend_user_id) REFERENCES public.users(id) ON DELETE CASCADE;
ALTER TABLE public.friends ADD CONSTRAINT friends_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
ALTER TABLE public.orders ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);
ALTER TABLE public.restaurants ADD CONSTRAINT restaurants_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.session_members ADD CONSTRAINT session_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
ALTER TABLE public.sessions ADD CONSTRAINT sessions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);
ALTER TABLE public.tournament_results ADD CONSTRAINT tournament_results_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);
ALTER TABLE public.users ADD CONSTRAINT users_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE SET NULL;
GRANT ALL ON public.users TO service_role;
CREATE INDEX users_favorites_idx ON public.users USING gin (favorites);
CREATE INDEX users_restaurant_id_idx ON public.users (restaurant_id) WHERE restaurant_id IS NOT NULL;
CREATE UNIQUE INDEX users_phone_number_key ON public.users (phone_number) WHERE phone_number IS NOT NULL;
CREATE UNIQUE INDEX users_email_key ON public.users (lower(email)) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX users_business_number_key ON public.users (business_number) WHERE business_number IS NOT NULL;
CREATE INDEX users_role_status_idx ON public.users (role, status);
CREATE UNIQUE INDEX users_kakao_id_key ON public.users (kakao_id) WHERE kakao_id IS NOT NULL;
CREATE TABLE public.votes (id uuid DEFAULT gen_random_uuid() NOT NULL, session_id uuid NOT NULL, user_id uuid NOT NULL, restaurant_id uuid NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.votes ADD CONSTRAINT votes_pkey PRIMARY KEY (id);
ALTER TABLE public.votes ADD CONSTRAINT votes_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id);
ALTER TABLE public.votes ADD CONSTRAINT votes_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE CASCADE;
ALTER TABLE public.votes ADD CONSTRAINT votes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
ALTER TABLE public.votes ADD CONSTRAINT votes_user_session_key UNIQUE (user_id, session_id);
GRANT ALL ON public.votes TO service_role;
CREATE INDEX votes_restaurant_id_idx ON public.votes (restaurant_id);
CREATE INDEX votes_session_restaurant_idx ON public.votes (session_id, restaurant_id);
