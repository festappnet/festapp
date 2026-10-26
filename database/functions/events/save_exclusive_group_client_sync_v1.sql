CREATE OR REPLACE FUNCTION public.save_exclusive_group_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_group jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_id bigint; v_version bigint; v_begin jsonb;
  v_hash text; v_current jsonb; v_entity jsonb; v_event_ids bigint[];
  v_requested jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  IF p_group IS NULL OR jsonb_typeof(p_group)<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_group) key
      WHERE key NOT IN ('id','title','events'))
    OR nullif(btrim(p_group->>'title'),'') IS NULL
    OR octet_length(p_group->>'title')>2048
    OR jsonb_typeof(p_group->'events')<>'array'
    OR jsonb_array_length(p_group->'events')>500
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_group->'events') value
      WHERE jsonb_typeof(value)<>'number') THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid exclusive group'; END IF;
  SELECT COALESCE(array_agg(value::text::bigint ORDER BY value::text::bigint),
    '{}'::bigint[]) INTO v_event_ids FROM jsonb_array_elements(p_group->'events');
  IF cardinality(v_event_ids)<>cardinality(ARRAY(SELECT DISTINCT unnest(v_event_ids))) THEN
    RAISE invalid_parameter_value USING MESSAGE='duplicate exclusive event'; END IF;
  v_id:=(p_group->>'id')::bigint;
  IF v_id IS NULL AND p_expected_version IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new group must not have expected version'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'expectedVersion',p_expected_version,
    'group',p_group)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'schedule.exclusive_group.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_event_ids) event_id WHERE NOT EXISTS (
    SELECT 1 FROM public.events e WHERE e.id=event_id AND e.occasion=p_occasion)) THEN
    RAISE invalid_parameter_value USING MESSAGE='exclusive event outside occasion'; END IF;
  PERFORM 1 FROM public.events e WHERE e.id=ANY(v_event_ids) ORDER BY e.id FOR UPDATE;
  IF v_id IS NOT NULL THEN
    PERFORM 1 FROM public.exclusive_groups g WHERE g.id=v_id
      AND g.occasion=p_occasion FOR UPDATE;
    IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'rejected',404,jsonb_build_object('version',0,'group',NULL)); END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('exclusive_group','occasion',p_occasion,v_id::text,0)
    ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='exclusive_group' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    v_current:=public.get_exclusive_group_command_data_v1(v_id);
    IF p_expected_version IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
        jsonb_build_object('version',v_version,'group',v_current)); END IF;
    v_requested:=jsonb_build_object('id',v_id,'title',p_group->>'title',
      'exclusive_events',COALESCE((SELECT jsonb_agg(jsonb_build_object('event',event_id)
        ORDER BY event_id) FROM unnest(v_event_ids) event_id),'[]'::jsonb),
      'aggregate_version',v_version);
    IF v_current=v_requested THEN RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'unchanged',200,jsonb_build_object(
        'version',v_version,'group',v_current)); END IF;
    UPDATE public.exclusive_groups SET title=p_group->>'title' WHERE id=v_id;
    DELETE FROM public.exclusive_events WHERE "group"=v_id;
    INSERT INTO public.exclusive_events("group",event)
      SELECT v_id,event_id FROM unnest(v_event_ids) event_id;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='exclusive_group'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
  ELSE
    INSERT INTO public.exclusive_groups(title,occasion)
      VALUES (p_group->>'title',p_occasion) RETURNING id INTO v_id;
    INSERT INTO public.exclusive_events("group",event)
      SELECT v_id,event_id FROM unnest(v_event_ids) event_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('exclusive_group','occasion',p_occasion,v_id::text,v_version);
  END IF;
  v_entity:=public.get_exclusive_group_command_data_v1(v_id);
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'schedule.exclusive_group.save','schedule_constraints',
    jsonb_build_array(jsonb_build_object('entityType','exclusive_group',
      'entityId',v_id,'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_group->>'title',240),
      'changedFields',jsonb_build_array('title','events'))),
    '{}','[]','[]',jsonb_build_object('version',v_version,'group',v_entity));
END; $function$
;
REVOKE ALL ON FUNCTION public.save_exclusive_group_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_group jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_exclusive_group_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_group jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.save_exclusive_group_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_exclusive_group_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated,service_role;
