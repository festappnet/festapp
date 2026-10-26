CREATE OR REPLACE FUNCTION public.delete_event(p_event bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint; ver bigint; r jsonb;
BEGIN
 SELECT occasion INTO oc FROM public.events WHERE id=p_event;
 IF oc IS NULL THEN RETURN jsonb_build_object('code',404); END IF;
 IF auth.uid() IS NULL OR NOT public.can_write_schedule(oc) THEN RETURN jsonb_build_object('code',403); END IF;
 PERFORM public.lock_event_deletion_scope_internal_v1(oc,ARRAY[p_event]);
 PERFORM 1 FROM public.events WHERE id=p_event AND occasion=oc FOR UPDATE;
 SELECT coalesce(v.version,0) INTO ver FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
 ON v.aggregate_type='event' AND v.scope_type='occasion' AND v.scope_id=oc AND v.aggregate_id=p_event::text;
 r:=public.delete_event_client_sync_v1(oc,p_event,extensions.gen_random_uuid(),ver);
 RETURN jsonb_build_object('code',r->'code');
END $$;

REVOKE ALL ON FUNCTION public.delete_event(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.delete_event(bigint) TO authenticated;
