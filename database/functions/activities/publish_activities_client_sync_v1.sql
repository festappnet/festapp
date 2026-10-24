CREATE OR REPLACE FUNCTION public.publish_activities_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_activities_data jsonb, p_history_data jsonb, p_parent_history_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE
  v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_version bigint;
  v_handler jsonb; v_history_id bigint; v_commit jsonb; v_response jsonb;
  v_private_impacts jsonb; v_old_users uuid[]; v_activity jsonb; v_assignment jsonb;
  v_actor_private_revision bigint; v_actor_private_payload jsonb;
  v_latest_publish_unchanged boolean:=false;
  v_autosave jsonb; v_cleanup integer:=0;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  IF p_activities_data IS NULL OR jsonb_typeof(p_activities_data)<>'array'
     OR p_history_data IS NULL OR jsonb_typeof(p_history_data)<>'object'
     OR octet_length(p_activities_data::text)>2097152
     OR octet_length(p_history_data::text)>2097152
     OR jsonb_array_length(p_activities_data)>2000 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid activities aggregate';
  END IF;
  FOR v_activity IN SELECT value FROM jsonb_array_elements(p_activities_data) LOOP
    IF jsonb_typeof(v_activity)<>'object' OR NOT (v_activity ?& ARRAY[
      'id','title','is_hidden','order','assignments'])
      OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_activity) key WHERE key NOT IN
        ('id','title','description','type','unit','is_hidden','order','data','assignments'))
      OR jsonb_typeof(v_activity->'assignments')<>'array'
      OR EXISTS (SELECT 1 FROM public.activities a
        WHERE a.id=(v_activity->>'id')::uuid AND a.occasion<>p_occasion) THEN
      RAISE invalid_parameter_value USING MESSAGE='invalid or cross-scope activity';
    END IF;
    FOR v_assignment IN SELECT value FROM jsonb_array_elements(v_activity->'assignments') LOOP
      IF jsonb_typeof(v_assignment)<>'object'
        OR NOT (v_assignment ?& ARRAY['id','linked_place_ids','linked_event_ids'])
        OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_assignment) key WHERE key NOT IN
          ('id','user','start_time','end_time','title','description','data',
           'linked_place_ids','linked_event_ids'))
        OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(
          COALESCE(v_assignment->'linked_place_ids','[]')) id
          LEFT JOIN public.places p ON p.id=id::bigint AND p.occasion=p_occasion
          WHERE p.id IS NULL)
        OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(
          COALESCE(v_assignment->'linked_event_ids','[]')) id
          LEFT JOIN public.events e ON e.id=id::bigint AND e.occasion=p_occasion
          WHERE e.id IS NULL)
        OR ((v_assignment->>'user') IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM public.occasion_users ou
          WHERE ou.occasion=p_occasion AND ou."user"=(v_assignment->>'user')::uuid))
        OR EXISTS (SELECT 1 FROM public.activity_assignments aa
          JOIN public.activities a ON a.id=aa.activity_id
          WHERE aa.id=(v_assignment->>'id')::uuid AND a.occasion<>p_occasion) THEN
        RAISE invalid_parameter_value USING MESSAGE='invalid activity assignment references';
      END IF;
    END LOOP;
  END LOOP;

  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'expectedVersion',p_expected_version,'activities',p_activities_data,
    'history',p_history_data,'parentHistoryId',p_parent_history_id)::text,
    'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'activities.publish',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('activities','occasion',p_occasion,p_occasion::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='activities' AND scope_type='occasion' AND scope_id=p_occasion
      AND aggregate_id=p_occasion::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    v_response:=jsonb_build_object('status','conflict','code',409,
      'data',jsonb_build_object('version',v_version),
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;
  -- Autosave rows are immutable replacement identities. Consume only the exact
  -- draft selected by this editor; a newer row from another tab is preserved.
  v_autosave:=p_history_data->'_consume_autosave';
  p_history_data:=p_history_data-'_consume_autosave';
  IF v_autosave IS NOT NULL THEN
    IF EXISTS(SELECT 1 FROM public.activity_history WHERE id=(v_autosave->>'id')::bigint
       AND (occasion_id<>p_occasion OR user_id<>v_actor OR history_type<>'AUTOSAVE')) THEN
      RAISE insufficient_privilege USING MESSAGE='autosave unavailable'; END IF;
    DELETE FROM public.activity_history WHERE id=(v_autosave->>'id')::bigint
      AND occasion_id=p_occasion AND user_id=v_actor AND history_type='AUTOSAVE'
      AND created_at=(v_autosave->>'created_at')::timestamptz;
    GET DIAGNOSTICS v_cleanup=ROW_COUNT;
  END IF;
  SELECT h.activities_data=p_history_data INTO v_latest_publish_unchanged
  FROM public.activity_history h WHERE h.occasion_id=p_occasion
    AND h.history_type='PUBLISH' ORDER BY h.id DESC LIMIT 1;
  IF COALESCE(v_latest_publish_unchanged,false) THEN
    v_response:=jsonb_build_object('status','unchanged','code',200,
      'data',jsonb_build_object('version',v_version,'historyId',p_parent_history_id,'draftConsumed',v_cleanup=1),
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;
  SELECT array_agg(DISTINCT aa."user") INTO v_old_users
    FROM public.activity_assignments aa JOIN public.activities a ON a.id=aa.activity_id
    WHERE a.occasion=p_occasion;
  v_handler:=public.update_activities_internal_v1(p_occasion,p_activities_data);
  IF COALESCE((v_handler->>'code')::integer,500)<>200 THEN
    RAISE EXCEPTION 'activities aggregate handler failed: %',v_handler->>'message';
  END IF;
  INSERT INTO public.activity_history
    (occasion_id,user_id,activities_data,history_type,note,parent_history_id)
  VALUES (p_occasion,v_actor,p_history_data,'PUBLISH','Published via application',
    p_parent_history_id) RETURNING id INTO v_history_id;
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='activities'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_occasion::text
    RETURNING version INTO v_version;
  WITH affected(user_id) AS (
    SELECT v_actor UNION
    SELECT unnest(COALESCE(v_old_users,'{}'::uuid[])) UNION
    SELECT aa."user" FROM public.activity_assignments aa
      JOIN public.activities a ON a.id=aa.activity_id WHERE a.occasion=p_occasion
  ) SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_activity',
      'userId',user_id)),'[]'::jsonb) INTO v_private_impacts FROM affected
      WHERE user_id IS NOT NULL;
  v_commit:=public.record_client_sync_commit_v1(p_occasion,'activities.publish',
    'activities',jsonb_build_array(jsonb_build_object('entityType','activities',
      'entityId',p_occasion,'operation','publish','safeLabel','Activities',
    'changedFields',jsonb_build_array('aggregate'))),'{}',v_private_impacts,
    '[]','user',NULL);
  SELECT s.source_revision INTO STRICT v_actor_private_revision
  FROM public.client_sync_private_scopes s
  WHERE s.component='private_activity' AND s.occasion=p_occasion
    AND s.user_id=v_actor;
  v_actor_private_payload:=public.get_my_events_and_activities(
    p_occasion,true)->'data';
  v_response:=jsonb_build_object('status','applied','code',200,
    'data',jsonb_build_object('version',v_version,'historyId',v_history_id,
      'activities',p_activities_data,'draftConsumed',v_cleanup=1),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit->>'commitId','replayed',false,'occurredAt',v_commit->>'occurredAt'),
    'sync',jsonb_build_object('replacements',jsonb_build_array(
      jsonb_build_object('component','private_activity',
        'revision',v_actor_private_revision,'payload',v_actor_private_payload))));
  RETURN public.finish_client_mutation_v1(p_command_id,v_response,
    (v_commit->>'commitId')::uuid);
END; $function$;
REVOKE ALL ON FUNCTION public.publish_activities_client_sync_v1(bigint,uuid,bigint,jsonb,jsonb,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.publish_activities_client_sync_v1(bigint,uuid,bigint,jsonb,jsonb,bigint) TO authenticated;
