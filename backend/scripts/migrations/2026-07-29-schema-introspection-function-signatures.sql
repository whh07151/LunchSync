-- Make the startup schema healthcheck distinguish the current order RPC from
-- obsolete overloads. The backend depends on the exact six-argument contract.

CREATE OR REPLACE FUNCTION public.check_schema_resources()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_columns   JSON;
  v_tables    JSON;
  v_functions JSON;
BEGIN
  WITH expected(table_name, column_name) AS (
    VALUES
      ('restaurants', 'image_url'),
      ('restaurants', 'rating'),
      ('users',       'fcm_token'),
      ('sessions',    'radius'),
      ('sessions',    'budget'),
      ('sessions',    'return_minutes'),
      ('sessions',    'memo')
  )
  SELECT json_agg(
           json_build_object(
             'table',   e.table_name,
             'column',  e.column_name,
             'present', c.column_name IS NOT NULL
           )
           ORDER BY e.table_name, e.column_name
         )
    INTO v_columns
  FROM expected e
  LEFT JOIN information_schema.columns c
    ON c.table_schema = 'public'
   AND c.table_name = e.table_name
   AND c.column_name = e.column_name;

  WITH expected(table_name) AS (
    VALUES
      ('pos_seats'),
      ('pos_reservations')
  )
  SELECT json_agg(
           json_build_object(
             'table',   e.table_name,
             'present', t.table_name IS NOT NULL
           )
           ORDER BY e.table_name
         )
    INTO v_tables
  FROM expected e
  LEFT JOIN information_schema.tables t
    ON t.table_schema = 'public'
   AND t.table_name = e.table_name;

  WITH expected(
    routine_name,
    required_argument_names,
    required_argument_types,
    required_return_type
  ) AS (
    VALUES
      (
        'delete_session_cascade',
        NULL::TEXT[],
        NULL::TEXT[],
        NULL::TEXT
      ),
      (
        'create_order_with_items',
        ARRAY[
          'p_session_id',
          'p_user_id',
          'p_restaurant_id',
          'p_total_price',
          'p_payment_method',
          'p_items'
        ]::TEXT[],
        ARRAY[
          'uuid',
          'uuid',
          'uuid',
          'integer',
          'text',
          'json'
        ]::TEXT[],
        'json'
      ),
      (
        'create_session_with_host_member',
        NULL::TEXT[],
        NULL::TEXT[],
        NULL::TEXT
      )
  )
  SELECT json_agg(
           json_build_object(
             'name', e.routine_name,
             'signature',
               CASE WHEN candidate.oid IS NULL THEN NULL ELSE
                 'public.' || e.routine_name || '(' ||
                 replace(oidvectortypes(candidate.proargtypes), ', ', ',') ||
                 ')'
               END,
             'parameters',
               CASE WHEN candidate.oid IS NULL THEN NULL ELSE (
                 SELECT json_agg(
                          json_build_object(
                            'name',
                              candidate.proargnames[arg.position::INTEGER],
                            'type', format_type(arg.type_oid, NULL)
                          )
                          ORDER BY arg.position
                        )
                 FROM unnest(candidate.proargtypes)
                      WITH ORDINALITY AS arg(type_oid, position)
               ) END,
             'returnType',
               CASE
                 WHEN candidate.oid IS NULL THEN NULL
                 ELSE format_type(candidate.prorettype, NULL)
               END,
             'contract',
               CASE
                 WHEN e.required_argument_types IS NULL THEN NULL
                 ELSE json_build_object(
                   'parameters',
                     (
                       SELECT json_agg(
                                json_build_object(
                                  'name',
                                    e.required_argument_names[position],
                                  'type',
                                    e.required_argument_types[position]
                                )
                                ORDER BY position
                              )
                       FROM generate_subscripts(
                         e.required_argument_types,
                         1
                       ) AS position
                     ),
                   'returnType', e.required_return_type
                 )
               END,
             'present',
               candidate.oid IS NOT NULL
               AND (
                 e.required_argument_types IS NULL
                 OR (
                   candidate.proargnames = e.required_argument_names
                   AND ARRAY(
                     SELECT format_type(type_oid, NULL)
                     FROM unnest(candidate.proargtypes) AS type_oid
                   ) = e.required_argument_types
                   AND format_type(candidate.prorettype, NULL) =
                       e.required_return_type
                 )
               )
           )
           ORDER BY e.routine_name
         )
    INTO v_functions
  FROM expected e
  LEFT JOIN LATERAL (
    SELECT p.oid, p.proargnames, p.proargtypes, p.prorettype
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = e.routine_name
    ORDER BY
      (
        e.required_argument_types IS NULL
        OR (
          p.proargnames = e.required_argument_names
          AND ARRAY(
            SELECT format_type(type_oid, NULL)
            FROM unnest(p.proargtypes) AS type_oid
          ) = e.required_argument_types
          AND format_type(p.prorettype, NULL) = e.required_return_type
        )
      ) DESC,
      p.oid
    LIMIT 1
  ) candidate ON TRUE;

  RETURN json_build_object(
    'columns', v_columns,
    'tables', v_tables,
    'functions', v_functions
  );
END;
$$;

REVOKE ALL ON FUNCTION public.check_schema_resources()
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.check_schema_resources()
TO service_role;
