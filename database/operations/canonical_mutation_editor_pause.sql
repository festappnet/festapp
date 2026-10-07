-- PREPARED ONLY: requires explicit shared editor-pause authority before apply.
-- Run atomically through the canonical target guard after private ACL capture.
-- All 11 active occasions share these grants. No tenant-local ACL is implied.
-- Pause prevents mixed old/new editors; it does not satisfy G3 or open editing.
-- Forward recovery must reopen canonical RPCs only after the release gate.
-- Establish the gate before draining writes. Exact build/org match is fail-closed.
DO $mutation_overloads$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname=ANY(ARRAY['update_activities','save_activity_history','delete_autosave_history','import_user_group_assignments','import_occasion_users_from_csv','delete_occasion_user_ws','delete_occasion_user','game_guess','save_place_location']) AND p.oid::regprocedure::text<>ALL(ARRAY['update_activities(bigint,jsonb)','save_activity_history(bigint,jsonb,text,bigint,text)','delete_autosave_history(bigint)','import_user_group_assignments(bigint,jsonb)','import_occasion_users_from_csv(bigint,jsonb,jsonb)','delete_occasion_user_ws(uuid,bigint)','delete_occasion_user(uuid,bigint)','game_guess(bigint,text)','save_place_location(bigint,double precision,double precision)','update_activities(bigint)'])) THEN RAISE EXCEPTION 'unexpected legacy overload: re-inventory before contraction'; END IF;
END $mutation_overloads$;
DO $gate$ BEGIN
 IF to_regprocedure('public.assert_canonical_mutation_write_release_internal_v1(bigint)') IS NULL THEN RAISE EXCEPTION 'release guard migration required'; END IF;
 IF EXISTS(SELECT 1 FROM public.canonical_mutation_write_release_gate WHERE minimum_build<>620 OR organization_ids<>ARRAY[12]::bigint[]) THEN RAISE EXCEPTION 'unexpected existing release policy'; END IF;
END $gate$;
INSERT INTO public.canonical_mutation_write_release_gate(singleton,paused,minimum_build,organization_ids)
 VALUES(true,true,620,ARRAY[12]) ON CONFLICT(singleton) DO UPDATE SET paused=true;
-- Drain in-flight writes before the atomic grant switch. The executor bounds
-- this transaction to 45 seconds; a timeout leaves every change unapplied.
LOCK TABLE public.user_group_info,public.user_groups,public.activities,
 public.activity_assignments,public.activity_assignment_places,
 public.activity_assignment_events,public.activity_history,public.places
 IN ACCESS EXCLUSIVE MODE;
DO $pause_functions$
DECLARE signature text; function_id regprocedure; role_name text; client_role text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['public.update_activities(bigint,jsonb)','public.save_activity_history(bigint,jsonb,text,bigint,text)','public.delete_autosave_history(bigint)','public.import_user_group_assignments(bigint,jsonb)','public.import_occasion_users_from_csv(bigint,jsonb,jsonb)','public.delete_occasion_user_ws(uuid,bigint)','public.delete_occasion_user(uuid,bigint)','public.game_guess(bigint,text)','public.save_place_location(bigint,double precision,double precision)','public.save_user_group_client_sync_v1(bigint,uuid,bigint,jsonb)','public.delete_user_group_client_sync_v1(bigint,bigint,uuid,bigint)','public.replace_group_assignments_client_sync_v1(bigint,uuid,jsonb)','public.save_activity_draft_client_sync_v1(bigint,uuid,bigint,jsonb,bigint)','public.discard_activity_draft_client_sync_v1(bigint,uuid,bigint)','public.publish_activities_client_sync_v1(bigint,uuid,bigint,jsonb,jsonb,bigint)','public.move_place_client_sync_v1(bigint,bigint,uuid,bigint,double precision,double precision)','public.save_place_client_sync_v1(bigint,uuid,bigint,jsonb)','public.delete_place_client_sync_v1(bigint,bigint,uuid,bigint)'] LOOP
  function_id:=to_regprocedure(signature);
  IF function_id IS NULL THEN RAISE EXCEPTION 'pause signature missing: %',signature; END IF;
  EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC',function_id);
  FOR role_name IN SELECT DISTINCT r.rolname FROM pg_roles r
   WHERE r.rolname IN('anon','authenticated') OR pg_has_role('anon',r.oid,'MEMBER') OR pg_has_role('authenticated',r.oid,'MEMBER') LOOP
   IF role_name IN('postgres','service_role','authenticator') THEN RAISE EXCEPTION 'ordinary role inherits privileged lane: repair role membership explicitly'; END IF;
   EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM %I',function_id,role_name);
  END LOOP;
  FOREACH client_role IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_function_privilege(client_role,function_id,'EXECUTE') THEN RAISE EXCEPTION 'effective pause bypass: % %',client_role,signature; END IF;
  END LOOP;
 END LOOP;
END $pause_functions$;
DO $mutation_acl$
DECLARE relation regclass; role_name text; column_names text; client_role text;
BEGIN
 FOR relation IN SELECT unnest(ARRAY['public.user_group_info','public.user_groups','public.activities','public.activity_assignments','public.activity_assignment_places','public.activity_assignment_events','public.activity_history','public.places']::regclass[]) LOOP
  SELECT string_agg(quote_ident(attname),',') INTO column_names FROM pg_attribute WHERE attrelid=relation AND attnum>0 AND NOT attisdropped;
  EXECUTE format('REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON TABLE %s FROM PUBLIC',relation);
  EXECUTE format('REVOKE INSERT(%s),UPDATE(%s) ON TABLE %s FROM PUBLIC',column_names,column_names,relation);
  FOR role_name IN SELECT DISTINCT r.rolname FROM pg_roles r WHERE r.rolname IN('anon','authenticated') OR pg_has_role('anon',r.oid,'MEMBER') OR pg_has_role('authenticated',r.oid,'MEMBER') LOOP
   IF role_name IN('postgres','service_role','authenticator') THEN RAISE EXCEPTION 'ordinary role inherits privileged lane: repair role membership explicitly'; END IF;
   EXECUTE format('REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON TABLE %s FROM %I',relation,role_name);
   EXECUTE format('REVOKE INSERT(%s),UPDATE(%s) ON TABLE %s FROM %I',column_names,column_names,relation,role_name);
  END LOOP;
  FOREACH client_role IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_table_privilege(client_role,relation,'INSERT,UPDATE,DELETE,TRUNCATE') OR has_any_column_privilege(client_role,relation,'INSERT,UPDATE') THEN RAISE EXCEPTION 'effective DML survived: % %',client_role,relation; END IF;
  END LOOP;
 END LOOP;
END $mutation_acl$;
NOTIFY pgrst, 'reload schema';
