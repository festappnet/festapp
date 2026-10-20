CREATE OR REPLACE FUNCTION public.delete_event_client_sync_v1(p_occasion bigint, p_event_id bigint, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_version bigint; v_event jsonb;
  v_commit jsonb; v_program jsonb; v_response jsonb; v_hash text;
  v_is_publishable boolean; v_users uuid[]; v_private_impacts jsonb;
  v_had_speakers boolean; v_effects jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable
  FROM public.occasions o WHERE o.id=p_occasion;
  IF v_is_publishable IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='occasion not found';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'eventId',p_event_id,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'event.delete',p_occasion,
    v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.lock_event_deletion_scope_internal_v1(p_occasion,ARRAY[p_event_id]);
  PERFORM 1 FROM public.events e WHERE e.id=p_event_id AND e.occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN
    v_response:=jsonb_build_object('status','unchanged','code',200,
      'data',jsonb_build_object('eventId',p_event_id,'deleted',false),
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('event','occasion',p_occasion,p_event_id::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='event' AND scope_type='occasion' AND scope_id=p_occasion
      AND aggregate_id=p_event_id::text FOR UPDATE;
  v_event:=public.get_event_command_data_v1(p_event_id);
  IF p_expected_version IS DISTINCT FROM v_version THEN
    v_response:=jsonb_build_object('status','conflict','code',409,
      'data',jsonb_build_object('version',v_version,'event',v_event),
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;
  SELECT ARRAY(SELECT DISTINCT id FROM (
    SELECT eu."user" id FROM public.event_users eu WHERE eu.event=p_event_id
    UNION SELECT eus."user" FROM public.event_users_saved eus
      WHERE eus.event=p_event_id) users ORDER BY id) INTO v_users;
  v_effects:=public.delete_events_domain_internal_v1(p_occasion,ARRAY[p_event_id]);
  v_had_speakers:=(v_effects->>'hadSpeakers')::boolean;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_program',
    'userId',id)),'[]'::jsonb) INTO v_private_impacts
    FROM unnest(COALESCE(v_users,'{}'::uuid[])) id
    JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=id;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'event.delete','program',jsonb_build_array(jsonb_build_object(
      'entityType','event','entityId',p_event_id,'operation','delete',
      'safeLabel',left(v_event->>'title',240),
      'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable THEN ARRAY['program_catalog','live_public']||
      CASE WHEN v_had_speakers THEN ARRAY['content_catalog'] ELSE '{}'::text[] END
      ELSE '{}'::text[] END,v_private_impacts,
    CASE WHEN v_is_publishable THEN jsonb_build_array(jsonb_build_object(
      'component','live_public','entityId',p_event_id))||coalesce((SELECT jsonb_agg(jsonb_build_object('component','live_public','entityId',value::bigint)) FROM jsonb_array_elements_text(v_effects->'childIds')),'[]'::jsonb) ELSE '[]'::jsonb END,
    jsonb_build_object('eventId',p_event_id,'deleted',true));
END; $function$
;

REVOKE ALL ON FUNCTION public.delete_event_client_sync_v1(p_occasion bigint, p_event_id bigint, p_command_id uuid, p_expected_version bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.delete_event_client_sync_v1(p_occasion bigint, p_event_id bigint, p_command_id uuid, p_expected_version bigint) TO authenticated;
