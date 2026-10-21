-- Legacy partial patch adapter. Omitted fields survive; explicit nullable fields clear.
CREATE OR REPLACE FUNCTION public.update_speaker(p_occasion bigint,p_speaker jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_id bigint:=(p_speaker->>'id')::bigint; v_version bigint; v_payload jsonb; r jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_write_speakers(p_occasion) THEN
  RETURN jsonb_build_object('code',403); END IF;
 IF v_id IS NOT NULL THEN
  PERFORM 1 FROM public.speakers WHERE id=v_id AND occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('code',404); END IF;
  v_payload:=public.get_speaker_command_data_v1(v_id);
  SELECT coalesce(v.version,0) INTO v_version FROM (SELECT 1) seed
   LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='speaker'
   AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=v_id::text;
 ELSE v_payload:=jsonb_build_object('title','','order',0,'is_hidden',false)||jsonb_build_object('data','{}'::jsonb,'topics','[]'::jsonb); END IF;
 v_payload:=v_payload||p_speaker;
 -- Historical patch API ignores foreign topic IDs and collapses duplicates.
 -- Canonical callers validate their full aggregate strictly.
 IF p_speaker ? 'topics' THEN
  v_payload:=jsonb_set(v_payload,'{topics}',coalesce((SELECT jsonb_agg(t.id ORDER BY t.id)
   FROM public.speaker_topics t WHERE t.occasion=p_occasion AND t.id IN
    (SELECT value::bigint FROM jsonb_array_elements_text(p_speaker->'topics'))),'[]'));
 END IF;
 IF nullif(btrim(v_payload->>'title'),'') IS NULL THEN RETURN jsonb_build_object('code',400); END IF;
 r:=public.save_speaker_client_sync_v1(p_occasion,extensions.gen_random_uuid(),v_version,jsonb_build_object('id',v_payload->'id','title',v_payload->'title','subtitle',v_payload->'subtitle','description',v_payload->'description','image',v_payload->'image','order',v_payload->'order','is_hidden',v_payload->'is_hidden','data',v_payload->'data','topics',v_payload->'topics'));
 RETURN jsonb_build_object('code',r->'code','data',r#>'{data,speaker}');
END $$;

REVOKE ALL ON FUNCTION public.update_speaker(bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_speaker(bigint,jsonb) TO authenticated;
