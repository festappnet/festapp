BEGIN;

DO $$
DECLARE
  v_unscoped text[];
  v_non_public text[];
BEGIN
  SELECT array_agg(
    p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
    ORDER BY p.proname
  )
  INTO v_unscoped
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname LIKE '%\_internal\_v1' ESCAPE '\'
    AND p.proconfig IS NULL;

  PERFORM assert_true(
    v_unscoped IS NULL,
    'client-sync internal functions own an explicit search_path: ' ||
      COALESCE(array_to_string(v_unscoped, ', '), '')
  );

  SELECT array_agg(
    n.nspname || '.' || p.proname ||
      '(' || pg_get_function_identity_arguments(p.oid) || ')'
    ORDER BY n.nspname, p.proname
  )
  INTO v_non_public
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE p.prokind = 'f'
    AND n.nspname = 'eshop';

  PERFORM assert_true(
    v_non_public IS NULL,
    'application functions are canonical in public, not eshop: ' ||
      COALESCE(array_to_string(v_non_public, ', '), '')
  );

  PERFORM assert_true(
    to_regprocedure(
      'public.get_products_for_ticket_all_available(bigint)'
    ) IS NOT NULL,
    'available-products RPC exists in the canonical public schema'
  );

  PERFORM assert_true(
    has_function_privilege(
      'authenticated',
      'public.get_products_for_ticket_all_available(bigint)',
      'EXECUTE'
    ),
    'authenticated clients can execute the canonical available-products RPC'
  );

  PERFORM assert_true(
    (SELECT p.proconfig @> ARRAY['search_path=public, extensions']
       FROM pg_proc p
      WHERE p.oid = 'public.delete_order_internal_v1(bigint)'::regprocedure),
    'delete-order internal function has its own canonical search_path'
  );
END;
$$;

ROLLBACK;
