-- The initial remote migration was applied through MCP with
-- check_function_bodies disabled. A transcription error in the healthcheck
-- function body therefore surfaced only when the RPC was first executed.
-- Replace it with the reviewed declarative definition and preserve the repair
-- in migration history so local resets reproduce the remote sequence.

create or replace function public.check_schema_resources()
 returns json
 language plpgsql
 set search_path to 'pg_catalog', 'public'
as $function$
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

revoke all on function public.check_schema_resources()
from public, anon, authenticated;

grant execute on function public.check_schema_resources()
to service_role;
