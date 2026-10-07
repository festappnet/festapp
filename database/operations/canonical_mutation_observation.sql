-- Explicit operational activation, after the additive observation migration.
-- Applies only to the already verified current database. Changes no ACL/readiness.
DO $observation$
DECLARE setting text;
BEGIN
 IF to_regprocedure('public.log_canonical_mutation_request_v1()') IS NULL
 OR NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pgaudit') THEN
  RAISE EXCEPTION 'observation migration and pgaudit required';
 END IF;
 IF current_setting('pgaudit.log_parameter')<>'off' OR EXISTS(
  SELECT 1 FROM pg_db_role_setting s CROSS JOIN LATERAL unnest(s.setconfig) c
  WHERE s.setdatabase IN (0,(SELECT oid FROM pg_database WHERE datname=current_database()))
  AND c='pgaudit.log_parameter=on'
 ) THEN RAISE EXCEPTION 'parameter logging must be disabled before observation'; END IF;
 SELECT c INTO setting FROM pg_db_role_setting s CROSS JOIN LATERAL unnest(s.setconfig) c
 WHERE s.setrole='authenticator'::regrole AND s.setdatabase IN (0,(SELECT oid FROM pg_database WHERE datname=current_database()))
 AND c LIKE 'pgrst.db_pre_request=%' AND c NOT IN ('pgrst.db_pre_request=','pgrst.db_pre_request=public.log_canonical_mutation_request_v1') LIMIT 1;
 IF setting IS NOT NULL THEN RAISE EXCEPTION 'existing pre-request hook must be preserved explicitly'; END IF;
 EXECUTE format('ALTER ROLE authenticator IN DATABASE %I SET pgrst.db_pre_request TO %L',current_database(),'public.log_canonical_mutation_request_v1');
 -- No statement text or bound parameters, including service/SQL writers.
 FOREACH setting IN ARRAY ARRAY['authenticator','postgres'] LOOP
  EXECUTE format('ALTER ROLE %I IN DATABASE %I SET pgaudit.log TO %L',setting,current_database(),'write,ddl,role');
  EXECUTE format('ALTER ROLE %I IN DATABASE %I SET pgaudit.log_statement TO %L',setting,current_database(),'off');
  -- Supabase postgres can configure log/log_statement/log_relation, but does
  -- not have SET privilege on log_parameter. Preserve the verified off value.
  EXECUTE format('ALTER ROLE %I IN DATABASE %I SET pgaudit.log_relation TO %L',setting,current_database(),'on');
  -- The self-hosted image starts with log_min_messages=fatal. LOG is above
  -- ERROR for server filtering: retain audit/LOG without enabling SQL errors.
  EXECUTE format('ALTER ROLE %I IN DATABASE %I SET log_min_messages TO %L',setting,current_database(),'log');
 END LOOP;
END $observation$;
NOTIFY pgrst, 'reload config';
-- Role audit settings apply to newly established connections. Verify effective
-- authenticator settings before starting the dated window; reload alone is not
-- evidence that an existing pool adopted them. No restart is hidden in this SQL.
