CREATE OR REPLACE FUNCTION public.delete_empty_counseling_slots_client_sync_v1(p_speaker bigint, p_from timestamp with time zone, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_ids bigint[]; v_users uuid[]; v_impacts jsonb;
  v_publishable boolean;
BEGIN
  SELECT s.occasion,NOT o.is_hidden INTO v_occasion,v_publishable
    FROM public.speakers s JOIN public.occasions o ON o.id=s.occasion
    WHERE s.id=p_speaker;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.can_write_speakers(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('speaker',p_speaker,
    'from',p_from)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'program.counseling.delete_empty',
    v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(e.id ORDER BY e.id),'{}'::bigint[]) INTO v_ids
    FROM public.events e JOIN public.event_speakers es ON es.event=e.id
    WHERE es.speaker=p_speaker AND (e.data->>'is_counseling_slot')::boolean IS TRUE
      AND (p_from IS NULL OR e.start_time>=p_from)
      AND NOT EXISTS (SELECT 1 FROM public.event_users eu WHERE eu.event=e.id);
  PERFORM public.lock_event_deletion_scope_internal_v1(v_occasion,v_ids);
  PERFORM 1 FROM public.speakers WHERE id=p_speaker FOR NO KEY UPDATE;
  PERFORM pg_catalog.pg_advisory_xact_lock(p_speaker);
  IF EXISTS(SELECT 1 FROM public.events e JOIN public.event_speakers es ON es.event=e.id
    WHERE es.speaker=p_speaker AND (e.data->>'is_counseling_slot')::boolean IS TRUE
    AND (p_from IS NULL OR e.start_time>=p_from) AND NOT e.id=ANY(v_ids)
    AND NOT EXISTS(SELECT 1 FROM public.event_users WHERE event=e.id)) THEN
    RAISE serialization_failure USING MESSAGE='counseling slots changed; retry the same command'; END IF;
  -- A booking can commit while we wait for the event lock. Keep its metadata.
  v_ids:=ARRAY(SELECT id FROM public.events WHERE id=ANY(v_ids)
    AND NOT EXISTS(SELECT 1 FROM public.event_users WHERE event=events.id) ORDER BY id);
  PERFORM 1 FROM public.event_users_saved eus WHERE eus.event=ANY(v_ids)
    ORDER BY eus.event,eus."user" FOR UPDATE;
  SELECT COALESCE(array_agg(DISTINCT eus."user"),'{}'::uuid[]) INTO v_users
    FROM public.event_users_saved eus WHERE eus.event=ANY(v_ids);
  v_result:=public.delete_empty_counseling_slots_internal_v1(p_speaker,p_from);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),COALESCE(v_result->'data','{}')); END IF;
  IF cardinality(v_ids)=0 THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,v_result->'data'); END IF;
  DELETE FROM public.client_aggregate_versions v WHERE v.aggregate_type='event'
    AND v.scope_type='occasion' AND v.scope_id=v_occasion
    AND v.aggregate_id=ANY(ARRAY(SELECT id::text FROM unnest(v_ids) id));
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_program',
    'userId',id)),'[]'::jsonb) INTO v_impacts FROM unnest(v_users) id
    JOIN public.occasion_users ou ON ou.occasion=v_occasion AND ou."user"=id;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,v_occasion,
    'program.counseling.delete_empty','program',jsonb_build_array(jsonb_build_object(
      'entityType','counseling_slot','entityId',NULL,'operation','delete',
      'safeLabel','Empty counseling slots','changedFields',jsonb_build_array('events'))),
    CASE WHEN v_publishable THEN ARRAY['program_catalog','content_catalog','live_public']
      ELSE '{}'::text[] END,v_impacts,CASE WHEN v_publishable THEN COALESCE((
      SELECT jsonb_agg(jsonb_build_object('component','live_public','entityId',id))
      FROM unnest(v_ids) id),'[]'::jsonb) ELSE '[]'::jsonb END,v_result->'data');
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_empty_counseling_slots_client_sync_v1(p_speaker bigint, p_from timestamp with time zone, p_command_id uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_empty_counseling_slots_client_sync_v1(p_speaker bigint, p_from timestamp with time zone, p_command_id uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.delete_empty_counseling_slots_client_sync_v1(bigint,timestamp with time zone,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_empty_counseling_slots_client_sync_v1(bigint,timestamp with time zone,uuid) TO authenticated,service_role;
