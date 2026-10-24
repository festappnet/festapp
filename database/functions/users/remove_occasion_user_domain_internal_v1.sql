-- Private dependency of authorized membership/order teardown commands.
CREATE OR REPLACE FUNCTION public.lock_activity_aggregate_internal_v1(p_occasion bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 VALUES('activities','occasion',p_occasion,p_occasion::text,0) ON CONFLICT DO NOTHING;
 PERFORM 1 FROM public.client_aggregate_versions WHERE aggregate_type='activities'
   AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_occasion::text FOR UPDATE;
END $$;

CREATE OR REPLACE FUNCTION public.remove_occasion_user_domain_internal_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE groups bigint[]; impacts jsonb; removed integer;
BEGIN
 PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
 PERFORM 1 FROM public.user_group_info WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
 SELECT coalesce(array_agg(DISTINCT g.id),'{}') INTO groups
 FROM public.user_group_info g LEFT JOIN public.user_groups m ON m."group"=g.id
 WHERE g.occasion=p_occasion AND (m."user"=p_user OR g.leader=p_user);
 SELECT coalesce(jsonb_agg(jsonb_build_object('component','private_profile','userId',m."user")),'[]')
 INTO impacts FROM public.user_groups m WHERE m."group"=ANY(groups) AND m."user"<>p_user;
 UPDATE public.news SET created_by=NULL WHERE occasion=p_occasion AND created_by=p_user;
 UPDATE public.user_group_info SET leader=NULL WHERE occasion=p_occasion AND leader=p_user;
 DELETE FROM public.user_groups WHERE "user"=p_user AND "group"=ANY(groups);
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 SELECT 'user_group','occasion',p_occasion,id::text,1 FROM unnest(groups) id
 ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
 SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
 DELETE FROM public.activity_assignments aa USING public.activities a
 WHERE aa.activity_id=a.id AND a.occasion=p_occasion AND aa."user"=p_user;
 GET DIAGNOSTICS removed=ROW_COUNT;
 IF removed>0 THEN
  UPDATE public.client_aggregate_versions SET version=version+1,updated_at=clock_timestamp()
  WHERE aggregate_type='activities' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_occasion::text;
  impacts:=impacts||jsonb_build_array(jsonb_build_object('component','private_activity','userId',p_user));
 END IF;
 DELETE FROM public.event_users WHERE "user"=p_user AND event IN(SELECT id FROM public.events WHERE occasion=p_occasion);
 DELETE FROM public.event_users_saved WHERE "user"=p_user AND event IN(SELECT id FROM public.events WHERE occasion=p_occasion);
 DELETE FROM public.user_news WHERE "user"=p_user AND occasion=p_occasion;
 DELETE FROM public.occasion_users WHERE "user"=p_user AND occasion=p_occasion;
 RETURN impacts;
END $$;
REVOKE ALL ON FUNCTION public.lock_activity_aggregate_internal_v1(bigint),
 public.remove_occasion_user_domain_internal_v1(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
