-- One occasion-user teardown handler. Authorization and receipt belong to its callers.
CREATE OR REPLACE FUNCTION public.remove_occasion_user_domain_internal_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE groups bigint[]; impacts jsonb;
BEGIN
 PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
 SELECT COALESCE(array_agg(g.id),'{}') INTO groups FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group" WHERE ug."user"=p_user AND g.occasion=p_occasion;
 impacts:=public.group_profile_impacts_internal_v1(p_occasion,ARRAY(SELECT "user" FROM public.user_groups WHERE "group"=ANY(groups))||ARRAY[p_user]);
 impacts:=(SELECT COALESCE(jsonb_agg(x),'[]') FROM jsonb_array_elements(impacts) x WHERE x->>'userId'<>p_user::text)||public.remove_user_activity_internal_v1(p_occasion,ARRAY[p_user]);
 UPDATE public.news SET created_by=NULL WHERE created_by=p_user AND occasion=p_occasion;
 DELETE FROM public.user_groups WHERE "user"=p_user AND "group"=ANY(groups);
 UPDATE public.client_aggregate_versions SET version=version+1,updated_at=clock_timestamp() WHERE aggregate_type='user_group' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=ANY(ARRAY(SELECT id::text FROM unnest(groups) id));
 DELETE FROM public.event_users WHERE "user"=p_user AND event IN(SELECT id FROM public.events WHERE occasion=p_occasion);
 DELETE FROM public.event_users_saved WHERE "user"=p_user AND event IN(SELECT id FROM public.events WHERE occasion=p_occasion);
 DELETE FROM public.user_news WHERE "user"=p_user AND occasion=p_occasion;
 DELETE FROM public.occasion_users WHERE "user"=p_user AND occasion=p_occasion;
 DELETE FROM public.client_sync_private_scopes WHERE occasion=p_occasion AND user_id=p_user;
 DELETE FROM public.client_aggregate_versions WHERE aggregate_type='occasion_user' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_user::text;
 RETURN impacts;
END $$;
REVOKE ALL ON FUNCTION public.remove_occasion_user_domain_internal_v1(bigint,uuid) FROM PUBLIC,anon,authenticated;
