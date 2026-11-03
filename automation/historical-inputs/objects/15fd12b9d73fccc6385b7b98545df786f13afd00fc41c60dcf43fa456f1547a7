CREATE OR REPLACE FUNCTION public.delete_exclusive_group_client_sync_v1(p_occasion bigint, p_group_id bigint, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_entity jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'groupId',p_group_id,
    'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'schedule.exclusive_group.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.exclusive_groups g WHERE g.id=p_group_id
    AND g.occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('version',0,'group',NULL)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('exclusive_group','occasion',p_occasion,p_group_id::text,0)
  ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='exclusive_group' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_group_id::text FOR UPDATE;
  v_entity:=public.get_exclusive_group_command_data_v1(p_group_id);
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'group',v_entity)); END IF;
  DELETE FROM public.exclusive_events WHERE "group"=p_group_id;
  DELETE FROM public.exclusive_groups WHERE id=p_group_id;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='exclusive_group'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_group_id::text;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'schedule.exclusive_group.delete','schedule_constraints',
    jsonb_build_array(jsonb_build_object('entityType','exclusive_group',
      'entityId',p_group_id,'operation','delete','safeLabel',left(v_entity->>'title',240),
      'changedFields',jsonb_build_array('aggregate'))),
    '{}','[]','[]',jsonb_build_object('version',v_version,'group',NULL));
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_exclusive_group_client_sync_v1(p_occasion bigint, p_group_id bigint, p_command_id uuid, p_expected_version bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_exclusive_group_client_sync_v1(p_occasion bigint, p_group_id bigint, p_command_id uuid, p_expected_version bigint) TO authenticated;
