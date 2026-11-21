-- Run only during an authorized activation against the verified target.
-- Keep an existing canonical observation hook enabled. Reject unknown hooks.
DO $activation$
DECLARE
  v_hook text;
  v_observe boolean := false;
BEGIN
  IF to_regprocedure('public.enforce_account_assurance_request_v1()') IS NULL
    OR to_regprocedure('public.enforce_account_assurance_and_observe_v1()') IS NULL THEN
    RAISE EXCEPTION 'account assurance migration required';
  END IF;

  FOR v_hook IN
    SELECT split_part(setting, '=', 2)
    FROM pg_db_role_setting options
    CROSS JOIN LATERAL unnest(options.setconfig) setting
    WHERE options.setrole = 'authenticator'::regrole
      AND options.setdatabase IN (0, (SELECT oid FROM pg_database WHERE datname = current_database()))
      AND setting LIKE 'pgrst.db_pre_request=%'
  LOOP
    CASE v_hook
      WHEN 'public.log_canonical_mutation_request_v1', 'public.enforce_account_assurance_and_observe_v1' THEN
        v_observe := true;
      WHEN '', 'public.enforce_account_assurance_request_v1' THEN
        NULL;
      ELSE
        RAISE EXCEPTION 'existing pre-request hook requires explicit composition';
    END CASE;
  END LOOP;

  EXECUTE format('ALTER ROLE authenticator IN DATABASE %I SET pgrst.db_pre_request TO %L',
    current_database(), CASE WHEN v_observe THEN 'public.enforce_account_assurance_and_observe_v1'
      ELSE 'public.enforce_account_assurance_request_v1' END);
END $activation$;
NOTIFY pgrst, 'reload config';
