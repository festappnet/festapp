-- Group domain lock/impact helpers. No client EXECUTE.
CREATE OR REPLACE FUNCTION public.lock_group_occasion_internal_v1(p_occasion bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 PERFORM public.log_canonical_mutation_scope_internal_v1(p_occasion);
 PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion);
 PERFORM 1 FROM public.user_group_info WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 SELECT 'user_group','occasion',p_occasion,id::text,0 FROM public.user_group_info WHERE occasion=p_occasion ORDER BY id ON CONFLICT DO NOTHING;
 PERFORM 1 FROM public.client_aggregate_versions WHERE aggregate_type='user_group' AND scope_type='occasion' AND scope_id=p_occasion ORDER BY aggregate_id::bigint FOR UPDATE;
END $$;
CREATE OR REPLACE FUNCTION public.group_profile_impacts_internal_v1(p_occasion bigint,p_users uuid[])
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
 SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile','userId',u.id) ORDER BY u.id),'[]'::jsonb)
 FROM (SELECT unnest(p_users) id UNION SELECT uc."user" FROM public.user_companions uc WHERE uc.occasion=p_occasion AND uc.companion=ANY(p_users)) u
 JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=u.id;
$$;
CREATE OR REPLACE FUNCTION public.assert_group_place_owner_internal_v1(p_occasion bigint,p_group bigint,p_place bigint,p_removing boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 PERFORM 1 FROM public.places p WHERE p.id=p_place AND p.occasion=p_occasion AND p.type='group' AND p.is_hidden FOR UPDATE;
 IF NOT FOUND OR (SELECT count(*) FROM public.user_group_info WHERE place=p_place)<>1 OR NOT EXISTS(SELECT 1 FROM public.user_group_info WHERE id=p_group AND occasion=p_occasion AND place=p_place)
 OR EXISTS(SELECT 1 FROM public.activity_assignment_places WHERE place_id=p_place)
 OR EXISTS(SELECT 1 FROM public.activity_places WHERE place_id=p_place)
 OR EXISTS(SELECT 1 FROM public.events WHERE place=p_place)
 OR EXISTS(SELECT 1 FROM public.resources WHERE place=p_place)
 OR (p_removing AND (EXISTS(SELECT 1 FROM public.cleaning_reports WHERE place=p_place) OR EXISTS(SELECT 1 FROM public.cleaning_public_state WHERE place=p_place))) THEN
 RAISE invalid_parameter_value USING MESSAGE='private group place has ambiguous or external ownership'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.lock_group_occasion_internal_v1(bigint), public.group_profile_impacts_internal_v1(bigint,uuid[]), public.assert_group_place_owner_internal_v1(bigint,bigint,bigint,boolean) FROM PUBLIC,anon,authenticated;
