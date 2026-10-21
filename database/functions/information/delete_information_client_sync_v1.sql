CREATE OR REPLACE FUNCTION public.delete_information_client_sync_v1(p_occasion bigint, p_information_id bigint, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor uuid:=auth.uid(); v_version bigint; v_hidden_id bigint;
  v_entity jsonb; v_begin jsonb; v_hash text; v_commit jsonb; v_public jsonb;
  v_response jsonb; v_is_publishable boolean; v_is_hidden boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.can_write_information(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o
    WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'informationId',p_information_id,'expectedVersion',p_expected_version)::text,
    'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.information.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT public.get_information_command_data_v1(i.id),i.information_hidden,i.is_hidden
    INTO v_entity,v_hidden_id,v_is_hidden FROM public.information i
    WHERE i.id=p_information_id AND i.occasion=p_occasion FOR UPDATE;
  IF v_entity IS NULL THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'unchanged',200,jsonb_build_object('version',0,'information',NULL));
  END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('information','occasion',p_occasion,p_information_id::text,0)
  ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='information' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_information_id::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'conflict',409,jsonb_build_object('version',v_version,
        'information',v_entity));
  END IF;
  DELETE FROM public.information WHERE id=p_information_id;
  IF v_hidden_id IS NOT NULL THEN
    DELETE FROM public.information_hidden WHERE id=v_hidden_id AND occasion=p_occasion;
  END IF;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='information'
    AND scope_type='occasion' AND scope_id=p_occasion
    AND aggregate_id=p_information_id::text;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.information.delete','content',jsonb_build_array(jsonb_build_object(
      'entityType','information','entityId',p_information_id,'operation','delete',
      'safeLabel',left(v_entity->>'title',240),
      'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable AND NOT v_is_hidden THEN ARRAY['content_catalog']
      ELSE '{}'::text[] END,'[]','[]',
    jsonb_build_object('version',v_version,'information',NULL));
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_information_client_sync_v1(p_occasion bigint, p_information_id bigint, p_command_id uuid, p_expected_version bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.delete_information_client_sync_v1(p_occasion bigint, p_information_id bigint, p_command_id uuid, p_expected_version bigint) TO authenticated;
