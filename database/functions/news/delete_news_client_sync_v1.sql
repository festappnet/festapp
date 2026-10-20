CREATE OR REPLACE FUNCTION public.delete_news_client_sync_v1(p_occasion bigint, p_news_id bigint, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_entity jsonb; v_previous_id bigint; v_private_impacts jsonb;
  v_is_publishable boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o
    WHERE o.id=p_occasion;
  IF v_is_publishable IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='occasion not found';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'newsId',p_news_id,'expectedVersion',p_expected_version)::text,'UTF8'),
    'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.news.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT to_jsonb(n) INTO v_entity FROM public.news n
    WHERE n.id=p_news_id AND n.occasion=p_occasion FOR UPDATE;
  IF v_entity IS NULL THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'unchanged',200,jsonb_build_object('version',0,'news',NULL));
  END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('news','occasion',p_occasion,p_news_id::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='news' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_news_id::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'conflict',409,jsonb_build_object('version',v_version,'news',v_entity));
  END IF;
  SELECT n.id INTO v_previous_id FROM public.news n
    WHERE n.occasion=p_occasion AND n.id<p_news_id ORDER BY n.id DESC LIMIT 1;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_news',
    'userId',un."user")),'[]'::jsonb) INTO v_private_impacts
  FROM public.user_news un JOIN public.occasion_users ou
    ON ou.occasion=p_occasion AND ou."user"=un."user"
  WHERE un.occasion=p_occasion AND un.news_id=p_news_id;
  IF v_previous_id IS NULL THEN
    DELETE FROM public.user_news WHERE occasion=p_occasion AND news_id=p_news_id;
  ELSE
    UPDATE public.user_news SET news_id=v_previous_id
      WHERE occasion=p_occasion AND news_id=p_news_id;
  END IF;
  DELETE FROM public.news WHERE id=p_news_id;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='news'
    AND scope_type='occasion' AND scope_id=p_occasion
    AND aggregate_id=p_news_id::text;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.news.delete','content',jsonb_build_array(jsonb_build_object(
      'entityType','news','entityId',p_news_id,'operation','delete',
      'safeLabel','News','changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable THEN ARRAY['content_catalog'] ELSE '{}'::text[] END,
    v_private_impacts,'[]',jsonb_build_object('version',v_version,'news',NULL));
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_news_client_sync_v1(p_occasion bigint, p_news_id bigint, p_command_id uuid, p_expected_version bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_news_client_sync_v1(p_occasion bigint, p_news_id bigint, p_command_id uuid, p_expected_version bigint) TO authenticated;
