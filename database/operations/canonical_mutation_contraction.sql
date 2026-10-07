-- GATED SOURCE ONLY. G2/G3 shared-consumer evidence and G4 authority required.
-- Scope: public.user_group_info, public.user_groups, public.activities, public.activity_assignments, public.activity_assignment_places, public.activity_assignment_events, public.activity_history, public.places. Shared places closure: true.
DO $mutation_overloads$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname=ANY(ARRAY['update_activities','save_activity_history','delete_autosave_history','import_user_group_assignments','import_occasion_users_from_csv','delete_occasion_user_ws','delete_occasion_user','game_guess','save_place_location']) AND p.oid::regprocedure::text<>ALL(ARRAY['update_activities(bigint,jsonb)','save_activity_history(bigint,jsonb,text,bigint,text)','delete_autosave_history(bigint)','import_user_group_assignments(bigint,jsonb)','import_occasion_users_from_csv(bigint,jsonb,jsonb)','delete_occasion_user_ws(uuid,bigint)','delete_occasion_user(uuid,bigint)','game_guess(bigint,text)','save_place_location(bigint,double precision,double precision)','update_activities(bigint)'])) THEN RAISE EXCEPTION 'unexpected legacy overload: re-inventory before contraction'; END IF;
END $mutation_overloads$;
DROP FUNCTION IF EXISTS public.update_activities(bigint,jsonb);
DROP FUNCTION IF EXISTS public.save_activity_history(bigint,jsonb,text,bigint,text);
DROP FUNCTION IF EXISTS public.delete_autosave_history(bigint);
DROP FUNCTION IF EXISTS public.import_user_group_assignments(bigint,jsonb);
DROP FUNCTION IF EXISTS public.import_occasion_users_from_csv(bigint,jsonb,jsonb);
DROP FUNCTION IF EXISTS public.delete_occasion_user_ws(uuid,bigint);
DROP FUNCTION IF EXISTS public.delete_occasion_user(uuid,bigint);
DROP FUNCTION IF EXISTS public.game_guess(bigint,text);
DROP FUNCTION IF EXISTS public.save_place_location(bigint,double precision,double precision);
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
-- Remove only the retired writer labels; readiness and capability stay unchanged.
UPDATE public.client_sync_component_sources SET legacy_writers=ARRAY(SELECT x FROM unnest(legacy_writers) x WHERE x<>ALL(ARRAY['update_activities','save_activity_history','delete_autosave_history','import_user_group_assignments','import_occasion_users_from_csv','delete_occasion_user_ws','delete_occasion_user','game_guess','save_place_location']::text[])) WHERE (component,source_relation) IN (('private_profile','public.user_group_info'::regclass),('private_profile','public.user_groups'::regclass),('private_activity','public.activities'::regclass),('private_activity','public.activity_assignments'::regclass),('private_activity','public.activity_assignment_places'::regclass),('private_activity','public.activity_assignment_events'::regclass),('private_profile','public.places'::regclass));
DO $mutation_absence$ BEGIN
 IF EXISTS(SELECT 1 FROM unnest(ARRAY['public.update_activities(bigint,jsonb)','public.save_activity_history(bigint,jsonb,text,bigint,text)','public.delete_autosave_history(bigint)','public.import_user_group_assignments(bigint,jsonb)','public.import_occasion_users_from_csv(bigint,jsonb,jsonb)','public.delete_occasion_user_ws(uuid,bigint)','public.delete_occasion_user(uuid,bigint)','public.game_guess(bigint,text)','public.save_place_location(bigint,double precision,double precision)']) signature WHERE to_regprocedure(signature) IS NOT NULL) THEN RAISE EXCEPTION 'legacy writer survived'; END IF;
END $mutation_absence$;
