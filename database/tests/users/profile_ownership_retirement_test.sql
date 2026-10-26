-- Retired private command implementations cannot be re-exposed by an old
-- migration replay; public contracts and their grants remain the same.
DO $$
DECLARE signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY[
  'public.advance_group_profile_heads_internal_v1(bigint,uuid[])',
  'public.save_profile_companion_internal_v1(bigint,uuid,uuid,bigint,jsonb)',
  'public.import_profiles_companion_internal_v1(bigint,uuid,jsonb,jsonb)',
  'public.replace_group_assignments_companion_internal_v1(bigint,uuid,jsonb)',
  'public.delete_occasion_user_companion_internal_v1(bigint,uuid,uuid,bigint)'
 ] LOOP
  PERFORM assert_true(to_regprocedure(signature) IS NULL,'retired implementation stays absent: '||signature);
 END LOOP;
 FOREACH signature IN ARRAY ARRAY[
  'public.save_profile_client_sync_v1(bigint,uuid,uuid,bigint,jsonb)',
  'public.import_profiles_client_sync_v1(bigint,uuid,jsonb,jsonb)',
  'public.replace_group_assignments_client_sync_v1(bigint,uuid,jsonb)',
  'public.delete_occasion_user_client_sync_v1(bigint,uuid,uuid,bigint)'
 ] LOOP
  PERFORM assert_true(has_function_privilege('authenticated',signature,'EXECUTE'),'public command remains callable: '||signature);
  PERFORM assert_true(NOT has_function_privilege('anon',signature,'EXECUTE'),'anonymous execution remains denied: '||signature);
 END LOOP;
END $$;
