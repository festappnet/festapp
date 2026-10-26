BEGIN;

DO $$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.get_all_events_for_datagrid(bigint)'::regprocedure
  ) INTO v_definition;

  PERFORM assert_true(
    v_definition LIKE '%client_aggregate_versions%'
      AND v_definition LIKE '%aggregate_version%',
    'event admin grid returns the optimistic-concurrency version used by event saves'
  );

  SELECT pg_get_functiondef(
    'public.save_event_domain_command_internal_v1(bigint,uuid,bigint,jsonb)'::regprocedure
  ) INTO v_definition;

  PERFORM assert_true(
    v_definition LIKE '%AS parent(parent_id)%'
      AND v_definition LIKE '%AS requested_role(role_id)%',
    'event saves qualify relation ids instead of using ambiguous aliases'
  );
END;
$$;

ROLLBACK;
