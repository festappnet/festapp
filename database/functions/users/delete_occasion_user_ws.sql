-- Released Flutter void facade; its locked compatibility revision cannot stand
-- in for an original editor baseline. Remove after installed-client upgrade.
CREATE OR REPLACE FUNCTION public.delete_occasion_user_ws(usr_to_delete uuid,occasion_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE version bigint; result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.get_is_manager_on_occasion(occasion_id) OR public.get_is_admin_on_occasion(occasion_id)) THEN
  RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
 PERFORM public.lock_activity_aggregate_internal_v1(occasion_id);
 PERFORM 1 FROM public.user_group_info WHERE occasion=occasion_id ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.occasion_users WHERE occasion=occasion_id AND "user"=usr_to_delete FOR UPDATE;
 SELECT coalesce(v.version,0) INTO version FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
 ON v.aggregate_type='occasion_user' AND v.scope_type='occasion' AND v.scope_id=occasion_id AND v.aggregate_id=usr_to_delete::text;
 result:=public.delete_occasion_user_client_sync_v1(occasion_id,usr_to_delete,extensions.gen_random_uuid(),version);
 IF result->>'status' NOT IN('applied','unchanged') THEN RAISE EXCEPTION 'membership deletion rejected'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.delete_occasion_user_ws(uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_occasion_user_ws(uuid,bigint) TO authenticated;
