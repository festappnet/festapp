CREATE OR REPLACE FUNCTION public.set_event_speakers(p_event bigint,p_speakers bigint[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint; ver bigint; result jsonb;
BEGIN
 SELECT occasion INTO oc FROM public.events WHERE id=p_event;
 IF oc IS NULL THEN RETURN jsonb_build_object('code',404); END IF;
 IF public.can_write_speakers(oc) IS NOT TRUE THEN RETURN jsonb_build_object('code',403); END IF;
 PERFORM 1 FROM public.events WHERE id=p_event FOR UPDATE;
 SELECT coalesce(v.version,0) INTO ver FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
 ON v.aggregate_type='event' AND v.scope_type='occasion' AND v.scope_id=oc AND v.aggregate_id=p_event::text;
 result:=public.save_event_speakers_client_sync_v1(oc,p_event,extensions.gen_random_uuid(),ver,p_speakers);
 RETURN jsonb_build_object('code',result->'code');
EXCEPTION WHEN invalid_parameter_value THEN RETURN jsonb_build_object('code',400);
END $$;
REVOKE ALL ON FUNCTION public.set_event_speakers(bigint,bigint[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_event_speakers(bigint,bigint[]) TO authenticated;
