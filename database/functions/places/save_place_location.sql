CREATE OR REPLACE FUNCTION public.save_place_location(p_place_id bigint,p_lat double precision,p_lng double precision)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint; ver bigint; r jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RETURN jsonb_build_object('code',401); END IF;
 SELECT occasion INTO oc FROM public.places WHERE id=p_place_id;
 PERFORM public.lock_group_place_scope_internal_v1(oc,p_place_id);
 IF oc IS NULL THEN RETURN jsonb_build_object('code',404); END IF;
 SELECT coalesce(v.version,0) INTO ver FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
 ON v.aggregate_type='place' AND v.scope_type='occasion' AND v.scope_id=oc AND v.aggregate_id=p_place_id::text;
 r:=public.move_place_client_sync_v1(oc,p_place_id,extensions.gen_random_uuid(),ver,p_lat,p_lng);
 RETURN jsonb_build_object('code',r->'code','data',jsonb_build_object('id',p_place_id));
EXCEPTION WHEN insufficient_privilege THEN RETURN jsonb_build_object('code',403);
END $$;

REVOKE ALL ON FUNCTION public.save_place_location(bigint,double precision,double precision) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.save_place_location(bigint,double precision,double precision) TO authenticated;
