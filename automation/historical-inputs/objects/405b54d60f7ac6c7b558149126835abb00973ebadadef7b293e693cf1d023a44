CREATE OR REPLACE FUNCTION public.save_unit_client_sync_v1(p_unit bigint, p_command_id uuid, p_expected_version bigint, p_unit_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_version bigint;
  v_before jsonb; v_after jsonb; v_commit public.client_commits%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_manager_on_unit(p_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  IF p_unit_data IS NULL OR jsonb_typeof(p_unit_data)<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_unit_data) key
      WHERE key NOT IN ('id','title','data'))
    OR (p_unit_data->>'id')::bigint IS DISTINCT FROM p_unit
    OR nullif(btrim(p_unit_data->>'title'),'') IS NULL
    OR length(p_unit_data->>'title')>30
    OR jsonb_typeof(COALESCE(p_unit_data->'data','{}'::jsonb))<>'object'
    OR octet_length(p_unit_data::text)>262144 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid unit aggregate'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'unit',p_unit,'expectedVersion',p_expected_version,
    'data',p_unit_data)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_unit_client_mutation_v1(p_command_id,'unit.config.save',
    p_unit,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT jsonb_build_object('id',u.id,'title',u.title,'data',u.data)
    INTO v_before FROM public.units u WHERE u.id=p_unit FOR UPDATE;
  IF v_before IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'rejected',404,jsonb_build_object('version',0,'unit',NULL)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('unit','unit',p_unit,p_unit::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='unit' AND scope_type='unit'
      AND scope_id=p_unit AND aggregate_id=p_unit::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'unit',v_before||
        jsonb_build_object('aggregate_version',v_version))); END IF;
  v_after:=jsonb_build_object('id',p_unit,'title',p_unit_data->>'title',
    'data',COALESCE(p_unit_data->'data','{}'::jsonb));
  IF v_before=v_after THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('version',v_version,
      'unit',v_before||jsonb_build_object('aggregate_version',v_version))); END IF;
  PERFORM public.update_unit_internal_v1(
    p_unit,p_unit_data->>'title',COALESCE(p_unit_data->'data','{}'::jsonb));
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='unit' AND scope_type='unit'
    AND scope_id=p_unit AND aggregate_id=p_unit::text RETURNING version INTO v_version;
  INSERT INTO public.client_commits
    (unit,actor_id,actor_display,actor_kind,source,change_class)
  SELECT p_unit,v_actor,nullif(concat_ws(' ',ui.name,ui.surname),''),'user',
    'unit.config.save','configuration' FROM public.user_info ui WHERE ui.id=v_actor
  RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES (v_commit.commit_id,0,'unit',p_unit::text,'update',
    left(p_unit_data->>'title',240),ARRAY['configuration']);
  PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,p_unit);
  RETURN public.finish_client_mutation_v1(p_command_id,jsonb_build_object(
    'status','applied','code',200,'data',jsonb_build_object('version',v_version,
      'unit',v_after||jsonb_build_object('aggregate_version',v_version)),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit.commit_id,'replayed',false,'occurredAt',v_commit.occurred_at),
    'sync',jsonb_build_object('replacements','[]'::jsonb)),v_commit.commit_id);
END; $function$
;
REVOKE ALL ON FUNCTION public.save_unit_client_sync_v1(p_unit bigint, p_command_id uuid, p_expected_version bigint, p_unit_data jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_unit_client_sync_v1(p_unit bigint, p_command_id uuid, p_expected_version bigint, p_unit_data jsonb) TO authenticated;
