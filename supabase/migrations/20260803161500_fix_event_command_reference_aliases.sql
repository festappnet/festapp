-- Qualify the event relation aliases. PostgreSQL otherwise resolves `id` in
-- `events.id = id` ambiguously and rejects every existing-event save.
CREATE OR REPLACE FUNCTION public.save_event_client_sync_v1(
  p_occasion bigint,
  p_command_id uuid,
  p_expected_version bigint,
  p_event jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_event_id bigint := (p_event->>'id')::bigint;
  v_version bigint;
  v_begin jsonb;
  v_commit jsonb;
  v_data jsonb;
  v_current jsonb;
  v_requested jsonb;
  v_response jsonb;
  v_program jsonb;
  v_hash text;
  v_changed boolean := true;
  v_is_publishable boolean;
  v_parent_ids bigint[];
  v_role_ids bigint[];
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable
  FROM public.occasions o WHERE o.id=p_occasion;
  IF v_is_publishable IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='occasion not found';
  END IF;
  IF p_event IS NULL OR jsonb_typeof(p_event)<>'object'
     OR octet_length(p_event::text)>131072
     OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_event) key WHERE key NOT IN
       ('id','title','startTime','endTime','maxParticipants','description',
        'placeId','splitForMenWomen','isGroupEvent','isHidden','type','data',
        'order','parentEventIds','eventRoleIds'))
     OR NOT (p_event ?& ARRAY['title','startTime','endTime','splitForMenWomen',
       'isGroupEvent','isHidden','order','parentEventIds','eventRoleIds'])
     OR jsonb_typeof(p_event->'parentEventIds')<>'array'
     OR jsonb_typeof(p_event->'eventRoleIds')<>'array'
     OR jsonb_array_length(p_event->'parentEventIds')>1000
     OR jsonb_array_length(p_event->'eventRoleIds')>1000
     OR length(p_event->>'title') NOT BETWEEN 1 AND 500
     OR (p_event->>'startTime')::timestamptz >= (p_event->>'endTime')::timestamptz
     OR COALESCE((p_event->>'maxParticipants')::bigint,0)<0 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid event aggregate';
  END IF;

  SELECT COALESCE(array_agg(value::bigint ORDER BY value::bigint),'{}')
    INTO v_parent_ids FROM jsonb_array_elements_text(p_event->'parentEventIds');
  SELECT COALESCE(array_agg(value::bigint ORDER BY value::bigint),'{}')
    INTO v_role_ids FROM jsonb_array_elements_text(p_event->'eventRoleIds');
  IF cardinality(v_parent_ids)<>cardinality(ARRAY(SELECT DISTINCT unnest(v_parent_ids)))
     OR cardinality(v_role_ids)<>cardinality(ARRAY(SELECT DISTINCT unnest(v_role_ids)))
     OR (v_event_id IS NOT NULL AND v_event_id=ANY(v_parent_ids))
     OR EXISTS (
       SELECT 1
       FROM unnest(v_parent_ids) AS parent(parent_id)
       LEFT JOIN public.events e
         ON e.id=parent.parent_id AND e.occasion=p_occasion
       WHERE e.id IS NULL
     )
     OR EXISTS (
       SELECT 1
       FROM unnest(v_role_ids) AS requested_role(role_id)
       LEFT JOIN public.role_info r
         ON r.id=requested_role.role_id AND r.occasion=p_occasion
       WHERE r.id IS NULL
     )
     OR ((p_event->>'placeId') IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.places p WHERE p.id=(p_event->>'placeId')::bigint
         AND p.occasion=p_occasion)) THEN
    RAISE invalid_parameter_value USING MESSAGE='event aggregate contains cross-scope references';
  END IF;
  v_requested:=jsonb_build_object(
    'id',v_event_id,'title',p_event->>'title',
    'startTime',(p_event->>'startTime')::timestamptz,
    'endTime',(p_event->>'endTime')::timestamptz,
    'maxParticipants',(p_event->>'maxParticipants')::bigint,
    'description',p_event->>'description',
    'placeId',(p_event->>'placeId')::bigint,
    'splitForMenWomen',(p_event->>'splitForMenWomen')::boolean,
    'isGroupEvent',(p_event->>'isGroupEvent')::boolean,
    'isHidden',(p_event->>'isHidden')::boolean,'type',p_event->>'type',
    'data',p_event->'data','order',(p_event->>'order')::bigint,
    'parentEventIds',to_jsonb(v_parent_ids),'eventRoleIds',to_jsonb(v_role_ids));

  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'expectedVersion',p_expected_version,'event',p_event)::text,
    'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'event.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;

  IF v_event_id IS NOT NULL THEN
    PERFORM 1 FROM public.events e WHERE e.id=v_event_id AND e.occasion=p_occasion
      FOR UPDATE;
    IF NOT FOUND THEN
      v_response:=jsonb_build_object('status','rejected','code',404,
        'data',jsonb_build_object('eventId',v_event_id),
        'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
          'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
        'sync',jsonb_build_object('replacements','[]'::jsonb));
      RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
    END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('event','occasion',p_occasion,v_event_id::text,0)
    ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='event' AND scope_type='occasion'
        AND scope_id=p_occasion AND aggregate_id=v_event_id::text FOR UPDATE;
    v_current:=public.get_event_command_data_v1(v_event_id);
    IF p_expected_version IS DISTINCT FROM v_version THEN
      v_response:=jsonb_build_object('status','conflict','code',409,
        'data',jsonb_build_object('version',v_version,'event',v_current),
        'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
          'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
        'sync',jsonb_build_object('replacements','[]'::jsonb));
      RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
    END IF;
    v_changed:=v_current IS DISTINCT FROM v_requested;
  ELSIF p_expected_version IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new event must not have an expected version';
  END IF;

  IF NOT v_changed THEN
    v_response:=jsonb_build_object('status','unchanged','code',200,
      'data',jsonb_build_object('version',v_version,'event',v_current),
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;

  IF v_event_id IS NULL THEN
    INSERT INTO public.events(title,start_time,end_time,max_participants,description,
      place,split_for_men_women,is_group_event,is_hidden,occasion,type,data,"order")
    VALUES (p_event->>'title',(p_event->>'startTime')::timestamptz,
      (p_event->>'endTime')::timestamptz,(p_event->>'maxParticipants')::bigint,
      p_event->>'description',(p_event->>'placeId')::bigint,
      (p_event->>'splitForMenWomen')::boolean,(p_event->>'isGroupEvent')::boolean,
      (p_event->>'isHidden')::boolean,p_occasion,p_event->>'type',p_event->'data',
      (p_event->>'order')::bigint) RETURNING id INTO v_event_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('event','occasion',p_occasion,v_event_id::text,v_version);
  ELSE
    UPDATE public.events SET title=p_event->>'title',
      start_time=(p_event->>'startTime')::timestamptz,
      end_time=(p_event->>'endTime')::timestamptz,
      max_participants=(p_event->>'maxParticipants')::bigint,
      description=p_event->>'description',place=(p_event->>'placeId')::bigint,
      split_for_men_women=(p_event->>'splitForMenWomen')::boolean,
      is_group_event=(p_event->>'isGroupEvent')::boolean,
      is_hidden=(p_event->>'isHidden')::boolean,type=p_event->>'type',
      data=p_event->'data',"order"=(p_event->>'order')::bigint,updated_at=now()
    WHERE id=v_event_id;
    UPDATE public.client_aggregate_versions SET version=version+1,updated_at=clock_timestamp()
      WHERE aggregate_type='event' AND scope_type='occasion'
        AND scope_id=p_occasion AND aggregate_id=v_event_id::text
      RETURNING version INTO v_version;
  END IF;
  DELETE FROM public.event_groups WHERE event_child=v_event_id;
  INSERT INTO public.event_groups(event_parent,event_child)
    SELECT parent.parent_id,v_event_id
    FROM unnest(v_parent_ids) AS parent(parent_id);
  DELETE FROM public.event_roles WHERE event=v_event_id;
  INSERT INTO public.event_roles(event,role)
    SELECT v_event_id,requested_role.role_id
    FROM unnest(v_role_ids) AS requested_role(role_id);

  v_data:=jsonb_build_object('version',v_version,
    'event',public.get_event_command_data_v1(v_event_id));
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'event.save','program',jsonb_build_array(jsonb_build_object(
      'entityType','event','entityId',v_event_id,
      'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_event->>'title',240),
      'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable THEN ARRAY['program_catalog'] ELSE '{}'::text[] END,
    '[]','[]',v_data);
END;
$$;

REVOKE ALL ON FUNCTION public.save_event_client_sync_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_event_client_sync_v1(bigint,uuid,bigint,jsonb)
  TO authenticated;
