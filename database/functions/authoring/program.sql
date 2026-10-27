-- Stage 8 transport boundary. Each operation keeps its existing domain owner.
CREATE OR REPLACE FUNCTION public.require_program_domain_internal_v1(p_occasion bigint,p_domain text,p_write boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE app boolean; features jsonb; allowed boolean;
BEGIN
 SELECT coalesce((g.data->>'IS_APP_SUPPORTED')::boolean,false),o.features INTO app,features
 FROM public.occasions o JOIN public.organizations g ON g.id=o.organization WHERE o.id=p_occasion;
 IF p_domain<>'services' AND app IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='application variant does not support this domain'; END IF;
 IF p_domain IN ('activities','services','counseling') AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(features,'[]')) f
   WHERE f->>'code'=CASE WHEN p_domain='activities' THEN 'volunteers' WHEN p_domain='counseling' THEN 'counseling' ELSE 'services' END AND coalesce((f->>'is_enabled')::boolean,false)) THEN
  RAISE insufficient_privilege USING MESSAGE='occasion feature is disabled'; END IF;
 allowed:=CASE WHEN p_domain IN ('events','attendance','exclusiveGroups') THEN CASE WHEN p_write THEN public.can_write_schedule(p_occasion) ELSE public.can_read_schedule_editor(p_occasion) END
  WHEN p_domain IN ('places','placeTypes','paths') THEN CASE WHEN p_write THEN public.can_write_places(p_occasion) ELSE public.can_read_map_editor_bundle(p_occasion) END
  WHEN p_domain IN ('speakers','topics','counseling','eventSpeakers') THEN CASE WHEN p_write THEN public.can_write_speakers(p_occasion) ELSE public.can_read_speakers_editor(p_occasion) END
  WHEN p_domain='activities' THEN CASE WHEN p_write THEN public.can_write_activity_plan(p_occasion) ELSE public.can_read_activity_editor(p_occasion) END
  WHEN p_domain='services' THEN public.can_write_service_items(p_occasion) ELSE false END;
 IF allowed IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='ordinary program permission required'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.require_program_domain_internal_v1(bigint,text,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.manage_program_authoring(p_occasion bigint,p_organization bigint,p_unit bigint,p_action text,p_payload jsonb,p_command_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE domain text:=split_part(p_action,'.',1); verb text:=split_part(p_action,'.',2);
 entity bigint:=(p_payload->>'entityId')::bigint; lim int:=coalesce((p_payload->>'limit')::int,50);
 result jsonb; graph jsonb; draft public.activity_history%ROWTYPE; history jsonb; version bigint; payload jsonb:=coalesce(p_payload,'{}');
BEGIN
 PERFORM public.lock_people_scope_internal_v1(p_occasion,p_organization,p_unit);
 PERFORM public.require_program_domain_internal_v1(p_occasion,domain,p_command_id IS NOT NULL);
 IF jsonb_typeof(payload) IS DISTINCT FROM 'object' OR octet_length(payload::text)>4194304 OR lim NOT BETWEEN 1 AND 100 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid program request'; END IF;
 IF domain='events' AND verb='list' THEN
  SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]'::jsonb)) INTO result FROM (
   SELECT x.id,x.title,coalesce(v.version,0) AS "aggregateVersion" FROM public.events x
   LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='event' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=x.id::text
   WHERE x.occasion=p_occasion AND (payload->>'after' IS NULL OR x.id>(payload->>'after')::bigint) ORDER BY x.id LIMIT lim) page;
  RETURN result;
 ELSIF domain='events' AND verb='inspect' THEN
  PERFORM 1 FROM public.events WHERE id=entity AND occasion=p_occasion FOR SHARE;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='program entity outside scope'; END IF;
  SELECT jsonb_build_object('entityId',x.id,'aggregateVersion',coalesce(v.version,0),'entity',public.get_event_command_data_v1(x.id)) INTO result
   FROM public.events x LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='event' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=x.id::text
   WHERE x.id=entity AND x.occasion=p_occasion;
  RETURN result;
 END IF;
 IF domain='exclusiveGroups' AND verb='list' THEN
  SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]'::jsonb)) INTO result FROM (
   SELECT x.id,x.title,coalesce(v.version,0) AS "aggregateVersion" FROM public.exclusive_groups x
   LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='exclusive_group' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=x.id::text
   WHERE x.occasion=p_occasion AND (payload->>'after' IS NULL OR x.id>(payload->>'after')::bigint) ORDER BY x.id LIMIT lim) page;
  RETURN result;
 ELSIF domain='exclusiveGroups' AND verb='inspect' THEN
  PERFORM 1 FROM public.exclusive_groups WHERE id=entity AND occasion=p_occasion FOR SHARE;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='program entity outside scope'; END IF;
  SELECT jsonb_build_object('entityId',x.id,'aggregateVersion',coalesce(v.version,0),'entity',public.get_exclusive_group_command_data_v1(x.id)) INTO result
   FROM public.exclusive_groups x LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='exclusive_group' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=x.id::text
   WHERE x.id=entity AND x.occasion=p_occasion;
  RETURN result;
 END IF;
 IF domain='places' AND verb='list' THEN
  SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]'::jsonb)) INTO result FROM (
   SELECT x.id,x.title,coalesce(v.version,0) AS "aggregateVersion" FROM public.places x
   LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='place' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=x.id::text
   WHERE x.occasion=p_occasion AND (payload->>'after' IS NULL OR x.id>(payload->>'after')::bigint) ORDER BY x.id LIMIT lim) page;
  RETURN result;
 ELSIF domain='places' AND verb='inspect' THEN
  PERFORM 1 FROM public.places WHERE id=entity AND occasion=p_occasion FOR SHARE;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='program entity outside scope'; END IF;
  SELECT jsonb_build_object('entityId',x.id,'aggregateVersion',coalesce(v.version,0),'entity',to_jsonb(x)) INTO result
   FROM public.places x LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='place' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=x.id::text
   WHERE x.id=entity AND x.occasion=p_occasion;
  RETURN result;
 END IF;
 IF domain='placeTypes' AND verb='list' THEN
  SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]'::jsonb)) INTO result FROM (
   SELECT x.id,x.title,coalesce(v.version,0) AS "aggregateVersion" FROM public.place_types x
   LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='place_type' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=x.id::text
   WHERE x.occasion=p_occasion AND (payload->>'after' IS NULL OR x.id>(payload->>'after')::bigint) ORDER BY x.id LIMIT lim) page;
  RETURN result;
 ELSIF domain='placeTypes' AND verb='inspect' THEN
  PERFORM 1 FROM public.place_types WHERE id=entity AND occasion=p_occasion FOR SHARE;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='program entity outside scope'; END IF;
  SELECT jsonb_build_object('entityId',x.id,'aggregateVersion',coalesce(v.version,0),'entity',to_jsonb(x)) INTO result
   FROM public.place_types x LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='place_type' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=x.id::text
   WHERE x.id=entity AND x.occasion=p_occasion;
  RETURN result;
 END IF;
 IF domain='paths' AND verb='list' THEN
  SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]'::jsonb)) INTO result FROM (
   SELECT x.id,x.title,coalesce(v.version,0) AS "aggregateVersion" FROM public.path_groups x
   LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='path' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=x.id::text
   WHERE x.occasion=p_occasion AND (payload->>'after' IS NULL OR x.id>(payload->>'after')::bigint) ORDER BY x.id LIMIT lim) page;
  RETURN result;
 ELSIF domain='paths' AND verb='inspect' THEN
  PERFORM 1 FROM public.path_groups WHERE id=entity AND occasion=p_occasion FOR SHARE;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='program entity outside scope'; END IF;
  SELECT jsonb_build_object('entityId',x.id,'aggregateVersion',coalesce(v.version,0),'entity',to_jsonb(x)) INTO result
   FROM public.path_groups x LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='path' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=x.id::text
   WHERE x.id=entity AND x.occasion=p_occasion;
  RETURN result;
 END IF;
 IF domain='speakers' AND verb='list' THEN
  SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]'::jsonb)) INTO result FROM (
   SELECT x.id,x.title,coalesce(v.version,0) AS "aggregateVersion" FROM public.speakers x
   LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='speaker' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=x.id::text
   WHERE x.occasion=p_occasion AND (payload->>'after' IS NULL OR x.id>(payload->>'after')::bigint) ORDER BY x.id LIMIT lim) page;
  RETURN result;
 ELSIF domain='speakers' AND verb='inspect' THEN
  PERFORM 1 FROM public.speakers WHERE id=entity AND occasion=p_occasion FOR SHARE;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='program entity outside scope'; END IF;
  SELECT jsonb_build_object('entityId',x.id,'aggregateVersion',coalesce(v.version,0),'entity',public.get_speaker_command_data_v1(x.id)) INTO result
   FROM public.speakers x LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='speaker' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=x.id::text
   WHERE x.id=entity AND x.occasion=p_occasion;
  RETURN result;
 END IF;
 IF domain='topics' AND verb='list' THEN
  SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]'::jsonb)) INTO result FROM (
   SELECT x.id,x.title,coalesce(v.version,0) AS "aggregateVersion" FROM public.speaker_topics x
   LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='speaker_topic' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=x.id::text
   WHERE x.occasion=p_occasion AND (payload->>'after' IS NULL OR x.id>(payload->>'after')::bigint) ORDER BY x.id LIMIT lim) page;
  RETURN result;
 ELSIF domain='topics' AND verb='inspect' THEN
  PERFORM 1 FROM public.speaker_topics WHERE id=entity AND occasion=p_occasion FOR SHARE;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='program entity outside scope'; END IF;
  SELECT jsonb_build_object('entityId',x.id,'aggregateVersion',coalesce(v.version,0),'entity',to_jsonb(x)) INTO result
   FROM public.speaker_topics x LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='speaker_topic' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=x.id::text
   WHERE x.id=entity AND x.occasion=p_occasion;
  RETURN result;
 END IF;
 IF domain='places' AND verb='icons' THEN
  SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]'::jsonb)) INTO result FROM (
   SELECT i.id,i.data,i.link,i.unit FROM public.icons i JOIN public.occasions o ON o.id=p_occasion
   WHERE i.organization=o.organization AND (i.unit IS NULL OR i.unit=o.unit) AND (payload->>'after' IS NULL OR i.id>(payload->>'after')::bigint) ORDER BY i.id LIMIT lim) page;
  RETURN result;
 ELSIF domain='events' AND verb='roles' THEN
  SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]'::jsonb)) INTO result FROM (
   SELECT id,title FROM public.role_info WHERE occasion=p_occasion AND (payload->>'after' IS NULL OR id>(payload->>'after')::bigint) ORDER BY id LIMIT lim) page;
  RETURN result;
 ELSIF domain='eventSpeakers' AND verb='inspect' THEN
  PERFORM 1 FROM public.events WHERE id=entity AND occasion=p_occasion FOR SHARE;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='event outside scope'; END IF;
  SELECT jsonb_build_object('entityId',entity,'aggregateVersion',coalesce(v.version,0),'speakerIds',coalesce((SELECT jsonb_agg(speaker ORDER BY speaker) FROM public.event_speakers WHERE event=entity),'[]'::jsonb)) INTO result
   FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='event' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=entity::text;
  RETURN result;
 ELSIF domain='counseling' AND verb='list' THEN
  IF NOT EXISTS(SELECT 1 FROM public.speakers WHERE id=entity AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='speaker outside scope'; END IF;
  SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]'::jsonb)) INTO result FROM (
   SELECT e.id,e.title,e.start_time,e.end_time,e.type,coalesce(v.version,0) AS "aggregateVersion" FROM public.events e JOIN public.event_speakers es ON es.event=e.id
   LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='event' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=e.id::text
   WHERE e.occasion=p_occasion AND es.speaker=entity AND (payload->>'after' IS NULL OR e.id>(payload->>'after')::bigint) ORDER BY e.id LIMIT lim) page;
  RETURN result;
 END IF;
 IF domain='services' AND verb='list' THEN
  IF payload->>'type' NOT IN ('food','accommodation') THEN RAISE invalid_parameter_value USING MESSAGE='service family required'; END IF;
  SELECT jsonb_build_object('items',coalesce(jsonb_agg(item ORDER BY item->>'code'),'[]'::jsonb)) INTO result FROM (
   SELECT item FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(coalesce(o.services->(payload->>'type'),'[]')) item
   WHERE o.id=p_occasion AND (payload->>'after' IS NULL OR item->>'code'>payload->>'after') ORDER BY item->>'code' LIMIT lim) page;
  RETURN result;
 ELSIF domain='activities' AND verb='inspect' THEN
  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
  SELECT * INTO draft FROM public.activity_history WHERE occasion_id=p_occasion AND user_id=auth.uid() AND history_type='AUTOSAVE' ORDER BY id DESC LIMIT 1;
  graph:=public.current_activity_graph_internal_v1(p_occasion);
  result:=jsonb_build_object('aggregateVersion',coalesce((SELECT v.version FROM public.client_aggregate_versions v WHERE v.aggregate_type='activities' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=p_occasion::text),0),
   'latestPublishId',(SELECT id FROM public.activity_history WHERE occasion_id=p_occasion AND history_type='PUBLISH' ORDER BY id DESC LIMIT 1),
   'draftId',draft.id,'draftParentHistoryId',draft.parent_history_id,'graph',graph,'draftGraph',CASE WHEN draft.id IS NULL THEN NULL ELSE public.activity_history_graph_internal_v1(p_occasion,draft.activities_data,false) END);
  IF octet_length(result::text)>4194304 THEN RAISE program_limit_exceeded USING MESSAGE='activity aggregate exceeds authoring limit'; END IF;
  RETURN result;
 END IF;
 IF p_command_id IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='explicit program command identity required'; END IF;
 -- Scope-bind referenced resources before invoking a command which accepts an ID.
 IF domain IN ('attendance','eventSpeakers') AND NOT EXISTS(SELECT 1 FROM public.events WHERE id=entity AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='event outside scope'; END IF;
 IF domain='counseling' AND NOT EXISTS(SELECT 1 FROM public.speakers WHERE id=entity AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='speaker outside scope'; END IF;
 IF p_action='events.save' THEN result:=public.save_event_client_sync_v1(p_occasion,p_command_id,(payload->>'expectedVersion')::bigint,payload->'entity');
 ELSIF p_action='events.delete' THEN result:=public.delete_event_client_sync_v1(p_occasion,entity,p_command_id,(payload->>'expectedVersion')::bigint);
 ELSIF p_action='attendance.set' THEN result:=public.set_event_attendance_client_sync_v1(entity,(payload->>'participantId')::uuid,payload->>'action',p_command_id);
 ELSIF p_action='exclusiveGroups.save' THEN result:=public.save_exclusive_group_client_sync_v1(p_occasion,p_command_id,(payload->>'expectedVersion')::bigint,payload->'entity');
 ELSIF p_action='exclusiveGroups.delete' THEN result:=public.delete_exclusive_group_client_sync_v1(p_occasion,entity,p_command_id,(payload->>'expectedVersion')::bigint);
 ELSIF p_action='places.save' THEN result:=public.save_place_client_sync_v1(p_occasion,p_command_id,(payload->>'expectedVersion')::bigint,payload->'entity');
 ELSIF p_action='places.delete' THEN result:=public.delete_place_client_sync_v1(p_occasion,entity,p_command_id,(payload->>'expectedVersion')::bigint);
 ELSIF p_action='places.move' THEN result:=public.move_place_client_sync_v1(p_occasion,entity,p_command_id,(payload->>'expectedVersion')::bigint,(payload->>'lat')::double precision,(payload->>'lng')::double precision);
 ELSIF p_action='placeTypes.save' THEN result:=public.save_place_type_client_sync_v1(p_occasion,p_command_id,(payload->>'expectedVersion')::bigint,payload->'entity');
 ELSIF p_action='placeTypes.delete' THEN result:=public.delete_place_type_client_sync_v1(p_occasion,entity,p_command_id,(payload->>'expectedVersion')::bigint);
 ELSIF p_action='paths.save' THEN result:=public.save_path_client_sync_v1(p_occasion,p_command_id,(payload->>'expectedVersion')::bigint,payload->'entity');
 ELSIF p_action='paths.delete' THEN result:=public.delete_path_client_sync_v1(p_occasion,entity,p_command_id,(payload->>'expectedVersion')::bigint);
 ELSIF p_action='speakers.save' THEN result:=public.save_speaker_client_sync_v1(p_occasion,p_command_id,(payload->>'expectedVersion')::bigint,payload->'entity');
 ELSIF p_action='speakers.delete' THEN result:=public.delete_speaker_client_sync_v1(p_occasion,entity,p_command_id,(payload->>'expectedVersion')::bigint);
 ELSIF p_action='topics.save' THEN result:=public.save_speaker_topic_client_sync_v1(p_occasion,p_command_id,(payload->>'expectedVersion')::bigint,payload->'entity');
 ELSIF p_action='topics.delete' THEN result:=public.delete_speaker_topic_client_sync_v1(p_occasion,entity,p_command_id,(payload->>'expectedVersion')::bigint);
 ELSIF p_action='eventSpeakers.save' THEN result:=public.save_event_speakers_client_sync_v1(p_occasion,entity,p_command_id,(payload->>'expectedVersion')::bigint,ARRAY(SELECT value::bigint FROM jsonb_array_elements_text(payload->'speakerIds')));
 ELSIF p_action='counseling.createSlots' THEN result:=public.create_counseling_slots_client_sync_v1(entity,(payload->>'start')::timestamptz,(payload->>'end')::timestamptz,(payload->>'slotMinutes')::int,(payload->>'placeId')::bigint,(payload->>'capacity')::int,payload->>'title',(payload->>'breakMinutes')::int,p_command_id);
 ELSIF p_action='counseling.deleteEmptySlots' THEN result:=public.delete_empty_counseling_slots_client_sync_v1(entity,(payload->>'from')::timestamptz,p_command_id);
 ELSIF p_action='counseling.deleteSlot' THEN result:=public.delete_counseling_slot_client_sync_v1(entity,(payload->>'eventId')::bigint,p_command_id,(payload->>'expectedVersion')::bigint);
 ELSIF p_action='services.create' THEN result:=public.create_service_item_client_sync_v1(p_occasion,payload->>'type',payload->>'code',payload->>'title',(payload->>'reference')::bigint,p_command_id);
 ELSIF p_action='services.update' THEN result:=public.update_service_item_client_sync_v1(p_occasion,payload->>'type',payload->>'code',payload->>'title',(payload->>'reference')::bigint,p_command_id);
 ELSIF p_action='services.delete' THEN result:=public.delete_service_item_client_sync_v1(p_occasion,payload->>'type',payload->>'code',(payload->>'force')::boolean,p_command_id);
 ELSIF p_action='activities.saveDraft' THEN result:=public.save_activity_draft_client_sync_v1(p_occasion,p_command_id,(payload->>'expectedVersion')::bigint,public.activity_graph_history_internal_v1(payload->'graph'),(payload->>'parentHistoryId')::bigint);
 ELSIF p_action='activities.discardDraft' THEN result:=public.discard_activity_draft_client_sync_v1(p_occasion,p_command_id,(payload->>'expectedDraftId')::bigint);
 ELSIF p_action='activities.publish' THEN result:=public.publish_activities_client_sync_v1(p_occasion,p_command_id,(payload->>'expectedVersion')::bigint,payload->'graph',public.activity_graph_history_internal_v1(payload->'graph'),(payload->>'parentHistoryId')::bigint);
 ELSE RAISE invalid_parameter_value USING MESSAGE='unsupported program command'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.manage_program_authoring(bigint,bigint,bigint,text,jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.manage_program_authoring(bigint,bigint,bigint,text,jsonb,uuid) TO authenticated,service_role;
