-- Legacy deletion adapter for released speaker editors.
CREATE OR REPLACE FUNCTION public.delete_speaker_topic(p_topic_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint; ver bigint; r jsonb;
BEGIN
 SELECT occasion INTO oc FROM public.speaker_topics WHERE id=p_topic_id;
 IF oc IS NULL THEN RETURN jsonb_build_object('code',404); END IF;
 IF auth.uid() IS NULL OR NOT public.can_write_speakers(oc) THEN RETURN jsonb_build_object('code',403); END IF;
 PERFORM 1 FROM public.speaker_topics WHERE id=p_topic_id AND occasion=oc FOR UPDATE;
 SELECT coalesce(v.version,0) INTO ver FROM (SELECT 1) seed
 LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='speaker_topic'
 AND v.scope_type='occasion' AND v.scope_id=oc AND v.aggregate_id=p_topic_id::text;
 r:=public.delete_speaker_topic_client_sync_v1(oc,p_topic_id,extensions.gen_random_uuid(),ver);
 RETURN jsonb_build_object('code',r->'code');
END $$;

REVOKE ALL ON FUNCTION public.delete_speaker_topic(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_speaker_topic(bigint) TO authenticated;
