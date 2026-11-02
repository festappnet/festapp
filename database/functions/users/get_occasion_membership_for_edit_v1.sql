CREATE OR REPLACE FUNCTION public.get_occasion_membership_for_edit_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT(auth.uid()=p_user OR public.can_manage_occasion_participants(p_occasion)) THEN RAISE insufficient_privilege USING MESSAGE='profile owner or manager required'; END IF;
 RETURN (SELECT to_jsonb(ou)||jsonb_build_object('aggregate_version',coalesce(v.version,0)) FROM public.occasion_users ou LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='occasion_user' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=p_user::text WHERE ou.occasion=p_occasion AND ou."user"=p_user AND (p_user=auth.uid() OR public.occasion_member_visible_internal(p_occasion,p_user)));
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_membership_for_edit_v1(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_membership_for_edit_v1(bigint,uuid) TO authenticated;
