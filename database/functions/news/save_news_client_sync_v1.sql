CREATE OR REPLACE FUNCTION public.save_news_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_news jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor uuid:=auth.uid(); v_id bigint; v_version bigint; v_begin jsonb;
  v_hash text; v_current jsonb; v_entity jsonb; v_is_publishable boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.can_write_news(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o
    WHERE o.id=p_occasion;
  IF v_is_publishable IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='occasion not found';
  END IF;
  IF p_news IS NULL OR jsonb_typeof(p_news)<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_news) key
      WHERE key NOT IN ('id','message'))
    OR NOT (p_news ? 'message')
    OR octet_length(COALESCE(p_news->>'message','')) NOT BETWEEN 1 AND 524288 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid news';
  END IF;
  v_id:=(p_news->>'id')::bigint;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'expectedVersion',p_expected_version,
    'news',p_news)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.news.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_id IS NOT NULL THEN
    SELECT jsonb_build_object('id',n.id,'message',n.message) INTO v_current
    FROM public.news n WHERE n.id=v_id AND n.occasion=p_occasion FOR UPDATE;
    IF v_current IS NULL THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'rejected',404,jsonb_build_object('version',0,'news',NULL));
    END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('news','occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='news' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      SELECT to_jsonb(n)||jsonb_build_object('aggregate_version',v_version)
        INTO v_entity FROM public.news n WHERE n.id=v_id;
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'conflict',409,jsonb_build_object('version',v_version,'news',v_entity));
    END IF;
    IF v_current=jsonb_build_object('id',v_id,'message',p_news->>'message') THEN
      SELECT to_jsonb(n)||jsonb_build_object('aggregate_version',v_version)
        INTO v_entity FROM public.news n WHERE n.id=v_id;
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'unchanged',200,jsonb_build_object('version',v_version,'news',v_entity));
    END IF;
    UPDATE public.news SET message=p_news->>'message',updated_at=clock_timestamp()
      WHERE id=v_id;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='news'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
  ELSE
    IF p_expected_version IS NOT NULL THEN
      RAISE invalid_parameter_value USING MESSAGE='new news must not have expected version';
    END IF;
    INSERT INTO public.news(message,created_by,occasion)
    VALUES (p_news->>'message',v_actor,p_occasion) RETURNING id INTO v_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('news','occasion',p_occasion,v_id::text,v_version);
  END IF;
  SELECT to_jsonb(n)||jsonb_build_object('aggregate_version',v_version)
    INTO v_entity FROM public.news n WHERE n.id=v_id;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.news.save','content',jsonb_build_array(jsonb_build_object(
      'entityType','news','entityId',v_id,
      'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel','News','changedFields',jsonb_build_array('message'))),
    CASE WHEN v_is_publishable THEN ARRAY['content_catalog'] ELSE '{}'::text[] END,
    '[]','[]',jsonb_build_object('version',v_version,'news',v_entity));
END; $function$
;
REVOKE ALL ON FUNCTION public.save_news_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_news jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_news_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_news jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.save_news_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_news_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated,service_role;
