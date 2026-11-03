-- Global identity columns appear in every occasion profile. The caller holds
-- user_info before any membership/version locks, and owns its origin receipt.
CREATE OR REPLACE FUNCTION public.publish_user_profile_change_internal_v1(p_user uuid,p_origin bigint,p_before jsonb)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE oc bigint;
BEGIN
 IF p_before IS NOT DISTINCT FROM (SELECT to_jsonb(ui) FROM public.user_info ui WHERE id=p_user) THEN RETURN; END IF;
 FOR oc IN SELECT occasion FROM public.occasion_users WHERE "user"=p_user AND occasion IS DISTINCT FROM p_origin ORDER BY occasion LOOP
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES('occasion_user','occasion',oc,p_user::text,1)
  ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
  SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
  PERFORM public.impact_private_profile_users_v1(oc,ARRAY[p_user],'profile.global.changed');
  PERFORM public.impact_companion_owners_v1(oc,ARRAY[p_user],'profile.companion_identity.changed');
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.publish_user_profile_change_internal_v1(uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
