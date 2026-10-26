-- Legacy deletion adapter for released speaker editors.
CREATE OR REPLACE FUNCTION public.delete_speaker(p_speaker_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint; ver bigint; r jsonb;
BEGIN
 SELECT occasion INTO oc FROM public.speakers WHERE id=p_speaker_id;
 IF oc IS NULL THEN RETURN jsonb_build_object('code',404); END IF;
 IF auth.uid() IS NULL OR NOT public.can_write_speakers(oc) THEN RETURN jsonb_build_object('code',403); END IF;
 PERFORM public.lock_speaker_event_dependencies_internal_v1(p_speaker_id);
 PERFORM 1 FROM public.speakers WHERE id=p_speaker_id AND occasion=oc FOR UPDATE;
 SELECT coalesce(v.version,0) INTO ver FROM (SELECT 1) seed
 LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='speaker'
 AND v.scope_type='occasion' AND v.scope_id=oc AND v.aggregate_id=p_speaker_id::text;
 r:=public.delete_speaker_client_sync_v1(oc,p_speaker_id,extensions.gen_random_uuid(),ver);
 RETURN jsonb_build_object('code',r->'code');
END $$;

REVOKE ALL ON FUNCTION public.delete_speaker(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_speaker(bigint) TO authenticated;
