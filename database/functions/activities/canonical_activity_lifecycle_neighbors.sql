CREATE OR REPLACE FUNCTION public.remove_user_activity_internal_v1(p_occasion bigint,p_users uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE impacted uuid[]; n int; impacts jsonb;
BEGIN
 PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
 SELECT ARRAY(SELECT DISTINCT aa."user" FROM public.activity_assignments aa JOIN public.activities a ON a.id=aa.activity_id WHERE a.occasion=p_occasion) INTO impacted;
 DELETE FROM public.activity_assignments aa USING public.activities a WHERE a.id=aa.activity_id AND a.occasion=p_occasion AND aa."user"=ANY(p_users);
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n=0 THEN RETURN '[]'; END IF;
 UPDATE public.client_aggregate_versions SET version=version+1,updated_at=clock_timestamp() WHERE aggregate_type='activities' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_occasion::text;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_activity','userId',id) ORDER BY id),'[]') INTO impacts FROM unnest(impacted) id JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=id WHERE NOT id=ANY(p_users);
 RETURN impacts;
END $$;
REVOKE ALL ON FUNCTION public.remove_user_activity_internal_v1(bigint,uuid[]) FROM PUBLIC,anon,authenticated;
