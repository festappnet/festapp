-- Legacy partial patch adapter. Omitted fields survive; explicit nullable fields clear.
CREATE OR REPLACE FUNCTION public.update_speaker_topic(p_occasion bigint,p_topic jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_id bigint:=(p_topic->>'id')::bigint; v_version bigint; v_payload jsonb; r jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_write_speakers(p_occasion) THEN
  RETURN jsonb_build_object('code',403); END IF;
 IF v_id IS NOT NULL THEN
  PERFORM 1 FROM public.speaker_topics WHERE id=v_id AND occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('code',404); END IF;
  v_payload:=(SELECT to_jsonb(t) FROM public.speaker_topics t WHERE t.id=v_id);
  SELECT coalesce(v.version,0) INTO v_version FROM (SELECT 1) seed
   LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='speaker_topic'
   AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=v_id::text;
 ELSE v_payload:=jsonb_build_object('title','','order',0,'is_hidden',false); END IF;
 v_payload:=v_payload||p_topic;
 IF nullif(btrim(v_payload->>'title'),'') IS NULL THEN RETURN jsonb_build_object('code',400); END IF;
 r:=public.save_speaker_topic_client_sync_v1(p_occasion,extensions.gen_random_uuid(),v_version,jsonb_build_object('id',v_payload->'id','title',v_payload->'title','order',v_payload->'order','is_hidden',v_payload->'is_hidden'));
 RETURN jsonb_build_object('code',r->'code','data',r#>'{data,topic}');
END $$;

REVOKE ALL ON FUNCTION public.update_speaker_topic(bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_speaker_topic(bigint,jsonb) TO authenticated;
