CREATE OR REPLACE FUNCTION public.save_information_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_information jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor uuid:=auth.uid(); v_id bigint; v_hidden_id bigint; v_old_hidden_id bigint;
  v_version bigint; v_begin jsonb; v_hash text; v_current jsonb;
  v_requested jsonb; v_entity jsonb; v_commit jsonb; v_public jsonb;
  v_response jsonb; v_is_publishable boolean; v_old_is_hidden boolean;
  v_new_is_hidden boolean; v_affects_public boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o
    WHERE o.id=p_occasion;
  IF v_is_publishable IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='occasion not found';
  END IF;
  PERFORM public.validate_information_content_internal_v1(p_information,false);
  v_id:=(p_information->>'id')::bigint;
  v_new_is_hidden:=(p_information->>'isHidden')::boolean;
  v_requested:=jsonb_build_object('id',v_id,'title',p_information->>'title',
    'description',p_information->>'description','type',p_information->>'type',
    'isHidden',v_new_is_hidden,'order',(p_information->>'order')::bigint,
    'data',p_information->'data','hiddenData',p_information->'hiddenData');
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'expectedVersion',p_expected_version,
    'information',p_information)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.information.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;

  IF v_id IS NOT NULL THEN
    PERFORM 1 FROM public.information i WHERE i.id=v_id AND i.occasion=p_occasion
      FOR UPDATE;
    IF NOT FOUND THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'rejected',404,jsonb_build_object('version',0,'information',NULL));
    END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('information','occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='information' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    SELECT jsonb_build_object('id',i.id,'title',i.title,'description',i.description,
      'type',i.type,'isHidden',i.is_hidden,'order',i."order",'data',i.data,
      'hiddenData',ih.data),i.is_hidden,i.information_hidden
      INTO v_current,v_old_is_hidden,v_old_hidden_id
    FROM public.information i LEFT JOIN public.information_hidden ih
      ON ih.id=i.information_hidden WHERE i.id=v_id;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'conflict',409,jsonb_build_object('version',v_version,'information',
          public.get_information_command_data_v1(v_id)));
    END IF;
  ELSIF p_expected_version IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new information must not have expected version';
  END IF;

  IF v_current IS NOT DISTINCT FROM v_requested THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'unchanged',200,jsonb_build_object('version',v_version,'information',
        public.get_information_command_data_v1(v_id)));
  END IF;

  IF p_information->>'type'='game' THEN
    IF v_old_hidden_id IS NULL THEN
      INSERT INTO public.information_hidden(data,occasion)
      VALUES (p_information->'hiddenData',p_occasion) RETURNING id INTO v_hidden_id;
    ELSE
      UPDATE public.information_hidden SET data=p_information->'hiddenData'
      WHERE id=v_old_hidden_id AND occasion=p_occasion RETURNING id INTO v_hidden_id;
      IF v_hidden_id IS NULL THEN
        RAISE invalid_parameter_value USING MESSAGE='cross-scope hidden information';
      END IF;
    END IF;
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO public.information(title,description,type,is_hidden,"order",data,
      information_hidden,occasion)
    VALUES (p_information->>'title',p_information->>'description',
      p_information->>'type',v_new_is_hidden,(p_information->>'order')::bigint,
      p_information->'data',v_hidden_id,p_occasion) RETURNING id INTO v_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('information','occasion',p_occasion,v_id::text,v_version);
  ELSE
    UPDATE public.information SET title=p_information->>'title',
      description=p_information->>'description',type=p_information->>'type',
      is_hidden=v_new_is_hidden,"order"=(p_information->>'order')::bigint,
      data=p_information->'data',information_hidden=v_hidden_id,
      updated_at=clock_timestamp() WHERE id=v_id;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='information'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
    IF v_old_hidden_id IS NOT NULL AND v_hidden_id IS NULL THEN
      DELETE FROM public.information_hidden WHERE id=v_old_hidden_id
        AND occasion=p_occasion;
    END IF;
  END IF;
  v_entity:=public.get_information_command_data_v1(v_id)||
    jsonb_build_object('aggregate_version',v_version);
  v_affects_public:=NOT COALESCE(v_old_is_hidden,true) OR NOT v_new_is_hidden;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.information.save','content',jsonb_build_array(jsonb_build_object(
      'entityType','information','entityId',v_id,
      'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_information->>'title',240),
      'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable AND v_affects_public THEN ARRAY['content_catalog']
      ELSE '{}'::text[] END,'[]','[]',
    jsonb_build_object('version',v_version,'information',v_entity));
END; $function$
;
REVOKE ALL ON FUNCTION public.save_information_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_information jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.save_information_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_information jsonb) TO authenticated;
