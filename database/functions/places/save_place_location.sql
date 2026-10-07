-- Released G3 compatibility boundary. The typed move command owns the DML.
-- This facade generates its intent/token server-side and cannot protect stale edits.
CREATE OR REPLACE FUNCTION public.save_place_location(p_place_id bigint,p_lat double precision,p_lng double precision)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE occasion bigint; version bigint; result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RETURN jsonb_build_object('code',401,'message','Sign in is required to move a place'); END IF;
 SELECT p.occasion INTO occasion FROM public.places p WHERE id=p_place_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('code',404,'message','Place not found'); END IF;
 SELECT v.version INTO version FROM public.client_aggregate_versions v WHERE aggregate_type='place' AND scope_type='occasion' AND scope_id=occasion AND aggregate_id=p_place_id::text;
 result:=public.move_place_client_sync_v1(occasion,p_place_id,extensions.gen_random_uuid(),COALESCE(version,0),p_lat,p_lng);
 RETURN jsonb_build_object('code',(result->>'code')::int,'data',jsonb_build_object('id',p_place_id));
EXCEPTION WHEN insufficient_privilege THEN RETURN jsonb_build_object('code',403,'message','You cannot change this place');
END $$;
