CREATE OR REPLACE FUNCTION public.lock_group_place_scope_internal_v1(p_occasion bigint,p_place bigint)
RETURNS bigint[] LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ids bigint[]; current_ids bigint[];
BEGIN
 SELECT ARRAY(SELECT g.id FROM public.user_group_info g JOIN public.places p ON p.id=g.place
  WHERE p.id=p_place AND p.occasion=p_occasion AND g.occasion=p_occasion AND p.is_hidden AND p.type='group' ORDER BY g.id) INTO ids;
 PERFORM 1 FROM public.user_group_info WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.places WHERE id=p_place AND occasion=p_occasion FOR UPDATE;
 SELECT ARRAY(SELECT g.id FROM public.user_group_info g JOIN public.places p ON p.id=g.place
  WHERE p.id=p_place AND p.occasion=p_occasion AND g.occasion=p_occasion AND p.is_hidden AND p.type='group' ORDER BY g.id) INTO current_ids;
 IF ids IS DISTINCT FROM current_ids THEN RAISE serialization_failure USING MESSAGE='group place ownership changed; retry the same command'; END IF;
 RETURN ids;
END $$;
REVOKE ALL ON FUNCTION public.lock_group_place_scope_internal_v1(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
