-- GATED SOURCE ONLY: verified CSM deployment and explicit reopening authority.
-- Reopens typed commands only. Old RPCs/direct DML remain inaccessible.
DO $reopen$
DECLARE signature text; relation regclass; client_role text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.canonical_mutation_write_release_gate
  WHERE singleton AND paused AND minimum_build=620 AND organization_ids=ARRAY[12]::bigint[]) THEN
  RAISE EXCEPTION 'expected paused CSM build-620 gate required'; END IF;
 FOREACH signature IN ARRAY ARRAY['public.update_activities(bigint,jsonb)','public.save_activity_history(bigint,jsonb,text,bigint,text)','public.delete_autosave_history(bigint)','public.import_user_group_assignments(bigint,jsonb)','public.import_occasion_users_from_csv(bigint,jsonb,jsonb)','public.delete_occasion_user_ws(uuid,bigint)','public.delete_occasion_user(uuid,bigint)','public.game_guess(bigint,text)','public.save_place_location(bigint,double precision,double precision)'] LOOP
  FOREACH client_role IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_function_privilege(client_role,to_regprocedure(signature),'EXECUTE') THEN RAISE EXCEPTION 'old writer still reachable: % %',client_role,signature; END IF;
  END LOOP;
 END LOOP;
 FOR relation IN SELECT unnest(ARRAY['public.user_group_info','public.user_groups','public.activities','public.activity_assignments','public.activity_assignment_places','public.activity_assignment_events','public.activity_history','public.places']::regclass[]) LOOP
  FOREACH client_role IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_table_privilege(client_role,relation,'INSERT,UPDATE,DELETE,TRUNCATE') OR has_any_column_privilege(client_role,relation,'INSERT,UPDATE') THEN RAISE EXCEPTION 'direct write still reachable: % %',client_role,relation; END IF;
  END LOOP;
 END LOOP;
END $reopen$;
GRANT EXECUTE ON FUNCTION public.save_user_group_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_user_group_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.replace_group_assignments_client_sync_v1(bigint,uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_activity_draft_client_sync_v1(bigint,uuid,bigint,jsonb,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.discard_activity_draft_client_sync_v1(bigint,uuid,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.publish_activities_client_sync_v1(bigint,uuid,bigint,jsonb,jsonb,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.move_place_client_sync_v1(bigint,bigint,uuid,bigint,double precision,double precision) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_place_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_place_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated;
UPDATE public.canonical_mutation_write_release_gate SET paused=false WHERE singleton;
NOTIFY pgrst, 'reload schema';
