begin;

select plan(25);

select ok(
  (
    select count(*) = 15
    from information_schema.tables
    where table_schema = 'public'
      and table_type = 'BASE TABLE'
      and table_name = any (array[
        'users',
        'restaurants',
        'menu_items',
        'sessions',
        'session_members',
        'invitations',
        'votes',
        'cart_items',
        'orders',
        'order_items',
        'notifications',
        'friends',
        'pos_seats',
        'pos_reservations',
        'tournament_results'
      ])
  ),
  'all 15 LunchSync tables exist'
);

select ok(
  (select count(*) = 0 from public.users)
  and (select count(*) = 0 from public.orders)
  and (select count(*) = 0 from public.notifications),
  'reset starts without application data'
);

select ok(
  (select count(*) = 0 from auth.users),
  'reset starts without Supabase Auth users'
);

select ok(
  (
    select count(*) = 15
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and c.relrowsecurity
      and c.relname = any (array[
        'users',
        'restaurants',
        'menu_items',
        'sessions',
        'session_members',
        'invitations',
        'votes',
        'cart_items',
        'orders',
        'order_items',
        'notifications',
        'friends',
        'pos_seats',
        'pos_reservations',
        'tournament_results'
      ])
  ),
  'RLS is enabled on every application table'
);

select ok(
  (
    select count(*) = 0
    from pg_policies
    where schemaname = 'public'
      and tablename = any (array[
        'users',
        'restaurants',
        'menu_items',
        'sessions',
        'session_members',
        'invitations',
        'votes',
        'cart_items',
        'orders',
        'order_items',
        'notifications',
        'friends',
        'pos_seats',
        'pos_reservations',
        'tournament_results'
      ])
  ),
  'application tables are not exposed through browser-role RLS policies'
);

select ok(
  not has_table_privilege('anon', 'public.users', 'select'),
  'anon cannot read application tables'
);

select ok(
  not has_table_privilege('authenticated', 'public.users', 'select'),
  'authenticated cannot read application tables directly'
);

select ok(
  has_table_privilege('service_role', 'public.users', 'select')
  and has_table_privilege('service_role', 'public.users', 'insert')
  and has_table_privilege('service_role', 'public.users', 'update')
  and has_table_privilege('service_role', 'public.users', 'delete'),
  'service role has required CRUD privileges'
);

select ok(
  not has_table_privilege('service_role', 'public.users', 'truncate')
  and not has_table_privilege('service_role', 'public.users', 'trigger'),
  'service role does not receive destructive table-owner privileges'
);

select ok(
  to_regprocedure(
    'public.create_session_with_host_member(text,uuid,timestamptz,integer,integer,integer,text,numeric,numeric)'
  ) is not null
  and to_regprocedure('public.delete_session_cascade(uuid)') is not null
  and to_regprocedure(
    'public.create_order_with_items(uuid,uuid,uuid,integer,text,json)'
  ) is not null
  and to_regprocedure('public.check_schema_resources()') is not null,
  'all backend RPC signatures exist'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.create_order_with_items(uuid,uuid,uuid,integer,text,json)',
    'execute'
  ),
  'service role can execute the order RPC'
);

select ok(
  to_regprocedure(
    'public.create_order_with_items(uuid,uuid,integer,text,json)'
  ) is null,
  'obsolete five-argument order RPC is absent'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.create_order_with_items(uuid,uuid,uuid,integer,text,json)',
    'execute'
  ),
  'anon cannot execute the order RPC'
);

select ok(
  (
    select count(*) = 4
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = any (array[
        'create_session_with_host_member',
        'delete_session_cascade',
        'create_order_with_items',
        'check_schema_resources'
      ])
      and not p.prosecdef
  ),
  'backend RPCs execute with invoker rights'
);

select ok(
  exists (
    select 1
    from storage.buckets
    where id = 'order-photos'
      and public
      and file_size_limit = 5242880
      and allowed_mime_types @> array[
        'image/jpeg',
        'image/png',
        'image/webp'
      ]::text[]
  ),
  'order-photos bucket is public and limited to 5 MiB images'
);

select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'order_photos_public_read'
  ),
  'public order photos do not expose bucket-wide object listing'
);

create temporary table lunchsync_test_ids (
  user_id uuid not null,
  restaurant_id uuid not null,
  menu_item_id uuid not null,
  session_id uuid,
  order_id uuid
);

insert into lunchsync_test_ids (user_id, restaurant_id, menu_item_id)
values (
  '00000000-0000-0000-0000-000000000101',
  '00000000-0000-0000-0000-000000000201',
  '00000000-0000-0000-0000-000000000301'
);

insert into public.users (id, name, auth_provider)
values (
  '00000000-0000-0000-0000-000000000101',
  'Synthetic Customer',
  'EMAIL'
);

insert into public.restaurants (id, name)
values (
  '00000000-0000-0000-0000-000000000201',
  'Synthetic Restaurant'
);

insert into public.menu_items (
  id,
  restaurant_id,
  name,
  price
)
values (
  '00000000-0000-0000-0000-000000000301',
  '00000000-0000-0000-0000-000000000201',
  'Synthetic Menu',
  7500
);

update lunchsync_test_ids
set session_id = (
  public.create_session_with_host_member(
    'Synthetic Session',
    user_id,
    null,
    500,
    15000,
    30,
    null,
    37.5,
    127.0
  ) ->> 'id'
)::uuid;

select ok(
  (select count(*) = 1 from public.sessions)
  and (select count(*) = 1 from public.session_members),
  'session RPC creates the session and host membership atomically'
);

select throws_ok(
  $test$
    select public.create_order_with_items(
      (select session_id from lunchsync_test_ids),
      '00000000-0000-0000-0000-000000000999'::uuid,
      (select restaurant_id from lunchsync_test_ids),
      15000,
      'SIMULATE',
      json_build_array(
        json_build_object(
          'menuItemId', (select menu_item_id from lunchsync_test_ids),
          'quantity', 2,
          'price', 7500
        )
      )
    )
  $test$,
  '42501',
  'ORDER_SESSION_MEMBER_REQUIRED',
  'order RPC rejects a user without session membership'
);

select throws_ok(
  $test$
    select public.create_order_with_items(
      (select session_id from lunchsync_test_ids),
      (select user_id from lunchsync_test_ids),
      (select restaurant_id from lunchsync_test_ids),
      15000,
      'SIMULATE',
      json_build_array(
        json_build_object(
          'menuItemId', (select menu_item_id from lunchsync_test_ids),
          'quantity', 2,
          'price', 7500
        )
      )
    )
  $test$,
  'P0001',
  'ORDER_SESSION_NOT_READY',
  'order RPC rejects a session before a winner is finalized'
);

update public.sessions
set status = 'ORDERED',
    winner_restaurant_id = (select restaurant_id from lunchsync_test_ids)
where id = (select session_id from lunchsync_test_ids);

select throws_ok(
  $test$
    select public.create_order_with_items(
      (select session_id from lunchsync_test_ids),
      (select user_id from lunchsync_test_ids),
      '00000000-0000-0000-0000-000000000998'::uuid,
      15000,
      'SIMULATE',
      json_build_array(
        json_build_object(
          'menuItemId', (select menu_item_id from lunchsync_test_ids),
          'quantity', 2,
          'price', 7500
        )
      )
    )
  $test$,
  'P0001',
  'ORDER_SESSION_RESTAURANT_MISMATCH',
  'order RPC rejects a restaurant other than the session winner'
);

select ok(
  (select count(*) = 0 from public.orders)
  and (select count(*) = 0 from public.order_items),
  'rejected order attempts leave no header or line items'
);

update lunchsync_test_ids
set order_id = (
  public.create_order_with_items(
    session_id,
    user_id,
    restaurant_id,
    15000,
    'SIMULATE',
    json_build_array(
      json_build_object(
        'menuItemId', menu_item_id,
        'quantity', 2,
        'price', 7500
      )
    )
  ) ->> 'id'
)::uuid;

select ok(
  (
    select count(*) = 1
      and min(total_price) = 15000
      and bool_and(status = 'PENDING')
    from public.orders
  )
  and (
    select count(*) = 1
      and min(quantity) = 2
      and min(price) = 7500
    from public.order_items
  ),
  'order RPC creates a consistent header and line item atomically'
);

select ok(
  (
    select bool_and((item ->> 'present')::boolean)
    from json_array_elements(
      public.check_schema_resources() -> 'columns'
    ) item
  )
  and (
    select bool_and((item ->> 'present')::boolean)
    from json_array_elements(
      public.check_schema_resources() -> 'tables'
    ) item
  )
  and (
    select bool_and((item ->> 'present')::boolean)
    from json_array_elements(
      public.check_schema_resources() -> 'functions'
    ) item
  ),
  'startup schema healthcheck reports every required resource present'
);

-- The deletion RPC deliberately accepts only pre-order sessions. Restore the
-- shared synthetic fixture after exercising the ORDERED-only order contract so
-- the two RPC policies remain independent in this test transaction.
update public.sessions
set status = 'WAITING',
    winner_restaurant_id = null
where id = (select session_id from lunchsync_test_ids);

select ok(
  (
    public.delete_session_cascade(
      (select session_id from lunchsync_test_ids)
    ) ->> 'deletedSessionId'
  )::uuid = (select session_id from lunchsync_test_ids)
  ,
  'session deletion RPC returns the deleted session id'
);

select ok(
  (select count(*) = 0 from public.sessions)
  and (select count(*) = 0 from public.orders)
  and (select count(*) = 0 from public.order_items),
  'session deletion removes its dependent order graph atomically'
);

select * from finish();

rollback;
