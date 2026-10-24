CREATE OR REPLACE FUNCTION public.set_event_attendance_client_sync_v1(p_event_id bigint, p_participant_id uuid, p_action text, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor uuid:=auth.uid(); v_occasion bigint; v_event public.events%ROWTYPE;
  v_begin jsonb; v_hash text; v_response jsonb; v_commit jsonb;
  v_private_revision bigint; v_live_revision bigint; v_private_payload jsonb;
  v_live_payload jsonb; v_code integer; v_registration_start timestamptz;
  v_feature jsonb; v_limit integer; v_count bigint; v_group bigint;
  v_is_male boolean; v_changed boolean:=false; v_status text;
  v_needs_occasion_join boolean:=false; v_profile_revision bigint;
  v_profile_payload jsonb; v_private_impacts jsonb; v_items jsonb;
  v_is_publishable boolean; v_companion_owner uuid;
BEGIN
  IF p_action NOT IN ('sign_in','sign_out') OR p_participant_id IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid attendance command';
  END IF;
  SELECT r.occasion INTO v_occasion FROM public.client_mutation_receipts r WHERE r.command_id=p_command_id
    AND r.actor_id=v_actor AND r.command_name='event.attendance.'||p_action;
  IF NOT FOUND THEN
  SELECT e.occasion,NOT o.is_hidden INTO v_occasion,v_is_publishable
  FROM public.events e JOIN public.occasions o ON o.id=e.occasion
  WHERE e.id=p_event_id;
  ELSE
    SELECT NOT is_hidden INTO v_is_publishable FROM public.occasions WHERE id=v_occasion;
  END IF;
  IF v_actor IS NULL OR v_occasion IS NULL OR NOT (
    v_actor=p_participant_id OR EXISTS (SELECT 1 FROM public.user_companions c
      WHERE c.occasion=v_occasion AND c."user"=v_actor AND c.companion=p_participant_id AND COALESCE((public.get_companion_feature_policy_v1(v_occasion)->>'is_enabled')::boolean,false))
    OR public.can_write_schedule(v_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='participant attendance permission required';
  END IF;
  SELECT c."user" INTO v_companion_owner FROM public.user_companions c
    JOIN public.occasion_users ou ON ou."user"=c."user" AND ou.occasion=v_occasion
    WHERE c.occasion=v_occasion AND c.companion=p_participant_id ORDER BY c."user" LIMIT 1;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('eventId',p_event_id,
    'participantId',p_participant_id,'action',p_action)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'event.attendance.'||p_action,
    v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;

  PERFORM public.notification_center_active_internal((SELECT organization FROM public.occasions WHERE id=v_occasion));
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'attendance-user:'||p_participant_id::text||':'||v_occasion::text,0));
  FOR v_group IN SELECT ee."group" FROM public.exclusive_events ee
      WHERE ee.event=p_event_id ORDER BY ee."group" LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'attendance-group:'||v_group::text,0));
  END LOOP;
  SELECT * INTO STRICT v_event FROM public.events e WHERE e.id=p_event_id
    AND e.occasion=v_occasion FOR UPDATE;

  PERFORM public.notification_center_event_capacity_internal(p_event_id,v_actor);
  IF p_action='sign_out' THEN
    IF NOT EXISTS (SELECT 1 FROM public.event_users eu
      WHERE eu.event=p_event_id AND eu."user"=p_participant_id) THEN
      v_status:='unchanged'; v_code:=404;
    ELSIF clock_timestamp() > v_event.end_time THEN
      v_status:='rejected'; v_code:=201;
    ELSE
      DELETE FROM public.event_users WHERE event=p_event_id AND "user"=p_participant_id;
      v_changed:=true; v_code:=200;
    END IF;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.occasion_users ou
      WHERE ou.occasion=v_occasion AND ou."user"=p_participant_id) THEN
      IF v_actor=p_participant_id AND EXISTS (SELECT 1 FROM public.occasions o
        WHERE o.id=v_occasion AND o.is_open) THEN
        v_needs_occasion_join:=true;
      END IF;
      IF NOT v_needs_occasion_join THEN
        v_status:='rejected'; v_code:=403;
      END IF;
    END IF;
    IF v_code IS NULL AND EXISTS (SELECT 1 FROM public.event_users eu
      WHERE eu.event=p_event_id AND eu."user"=p_participant_id) THEN
      v_status:='unchanged'; v_code:=103;
    END IF;
    IF v_code IS NULL AND clock_timestamp() > v_event.end_time THEN
      v_status:='rejected'; v_code:=100;
    END IF;

    IF v_code IS NULL AND COALESCE((v_event.data->>'is_counseling_slot')::boolean,false) THEN
      SELECT f INTO v_feature FROM public.occasions o,
        LATERAL jsonb_array_elements(o.features) f
      WHERE o.id=v_occasion AND f->>'code'='counseling' LIMIT 1;
      IF v_feature IS NULL OR COALESCE((v_feature->>'is_enabled')::boolean,false)=false THEN
        v_status:='rejected'; v_code:=108;
      ELSE
        v_registration_start:=(v_feature->>'registration_start_time')::timestamptz;
        IF v_registration_start IS NOT NULL AND clock_timestamp()<v_registration_start THEN
          v_status:='rejected'; v_code:=104;
        END IF;
        v_limit:=COALESCE((v_feature->>'max_active_bookings')::integer,1);
        IF v_code IS NULL AND v_limit>0 THEN
          SELECT count(*) INTO v_count FROM public.event_users eu
          JOIN public.events e ON e.id=eu.event
          WHERE eu."user"=p_participant_id AND e.occasion=v_occasion
            AND COALESCE((e.data->>'is_counseling_slot')::boolean,false)
            AND e.end_time>clock_timestamp();
          IF v_count>=v_limit THEN v_status:='rejected'; v_code:=109; END IF;
        END IF;
      END IF;
    ELSIF v_code IS NULL THEN
      SELECT f INTO v_feature FROM public.occasions o,
        LATERAL jsonb_array_elements(o.features) f
      WHERE o.id=v_occasion AND f->>'code'='workshops' LIMIT 1;
      IF v_feature IS NOT NULL THEN
        IF COALESCE((v_feature->>'is_enabled')::boolean,false)=false THEN
          v_status:='rejected'; v_code:=108;
        ELSE
          v_registration_start:=(v_feature->>'start_time')::timestamptz;
          IF v_registration_start IS NOT NULL AND clock_timestamp()<v_registration_start THEN
            v_status:='rejected'; v_code:=104;
          END IF;
        END IF;
      END IF;
    END IF;

    IF v_code IS NULL AND EXISTS (
      SELECT 1 FROM public.exclusive_events target
      JOIN public.exclusive_events occupied ON occupied."group"=target."group"
      JOIN public.event_users eu ON eu.event=occupied.event
      WHERE target.event=p_event_id AND eu."user"=p_participant_id) THEN
      v_status:='rejected'; v_code:=102;
    END IF;
    IF v_code IS NULL AND EXISTS (
      SELECT 1 FROM public.event_users eu JOIN public.events e ON e.id=eu.event
      WHERE eu."user"=p_participant_id AND e.id<>p_event_id
        AND e.start_time<v_event.end_time AND e.end_time>v_event.start_time) THEN
      v_status:='rejected'; v_code:=107;
    END IF;
    IF v_code IS NULL AND COALESCE(v_event.max_participants,0)>0 THEN
      SELECT count(*) INTO v_count FROM public.event_users eu WHERE eu.event=p_event_id;
      IF v_event.split_for_men_women THEN
        SELECT COALESCE(u.sex='male',false) INTO v_is_male
          FROM public.user_info u WHERE u.id=p_participant_id;
        SELECT count(*) INTO v_count FROM public.event_users eu
          JOIN public.user_info u ON u.id=eu."user" WHERE eu.event=p_event_id
            AND (u.sex='male')=v_is_male;
        IF v_count>=v_event.max_participants/2 THEN
          v_status:='rejected'; v_code:=CASE WHEN v_is_male THEN 105 ELSE 106 END;
        END IF;
      ELSIF v_count>=v_event.max_participants THEN
        v_status:='rejected'; v_code:=101;
      END IF;
    END IF;
    IF v_code IS NULL THEN
      IF v_needs_occasion_join THEN
        PERFORM public.add_user_to_occasion_internal_v1(v_occasion,p_participant_id);
        IF NOT EXISTS (SELECT 1 FROM public.occasion_users ou
          WHERE ou.occasion=v_occasion AND ou."user"=p_participant_id) THEN
          RAISE EXCEPTION 'occasion membership handler did not create membership';
        END IF;
      END IF;
      INSERT INTO public.event_users(event,"user") VALUES(p_event_id,p_participant_id);
      v_changed:=true; v_code:=200;
    END IF;
  END IF;

  IF NOT v_changed THEN
    v_response:=jsonb_build_object('status',v_status,'code',v_code,
      'data',jsonb_build_object('eventId',p_event_id,'participantId',p_participant_id,
        'isSignedIn',EXISTS(SELECT 1 FROM public.event_users eu
          WHERE eu.event=p_event_id AND eu."user"=p_participant_id),
        'eventsRegistrationStart',v_registration_start),
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;

  PERFORM public.notification_center_event_capacity_internal(p_event_id,v_actor);
  v_items:=jsonb_build_array(jsonb_build_object(
      'entityType','event_attendance','entityId',p_event_id||':'||p_participant_id::text,
      'operation','update','safeLabel','Event attendance',
      'changedFields',jsonb_build_array('is_signed_in')));
  v_private_impacts:=jsonb_build_array(jsonb_build_object(
    'component','private_program','userId',p_participant_id));
  IF v_companion_owner IS NOT NULL THEN
    v_private_impacts:=v_private_impacts||jsonb_build_array(jsonb_build_object(
      'component','private_profile','userId',v_companion_owner));
  END IF;
  IF v_needs_occasion_join THEN
    v_items:=v_items||jsonb_build_array(jsonb_build_object(
      'entityType','occasion_membership','entityId',p_participant_id,
      'operation','insert','safeLabel','Occasion membership',
      'changedFields',jsonb_build_array('occasion')));
    v_private_impacts:=v_private_impacts||jsonb_build_array(jsonb_build_object(
      'component','private_profile','userId',p_participant_id));
  END IF;
  v_commit:=public.record_client_sync_commit_v1(v_occasion,
    'event.attendance.'||p_action,'attendance',v_items,
    CASE WHEN v_is_publishable THEN ARRAY['live_public'] ELSE '{}'::text[] END,
    v_private_impacts,CASE WHEN v_is_publishable THEN jsonb_build_array(
      jsonb_build_object('component','live_public','entityId',p_event_id))
      ELSE '[]'::jsonb END,'user',NULL);
  SELECT source_revision INTO v_private_revision FROM public.client_sync_private_scopes
    WHERE component='private_program' AND occasion=v_occasion AND user_id=p_participant_id;
  IF v_needs_occasion_join OR v_companion_owner IS NOT NULL THEN
    SELECT source_revision INTO STRICT v_profile_revision
    FROM public.client_sync_private_scopes
    WHERE component='private_profile' AND occasion=v_occasion
      AND user_id=COALESCE(v_companion_owner,p_participant_id);
    v_profile_payload:=public.get_private_profile_payload_v1(
      v_occasion,COALESCE(v_companion_owner,p_participant_id));
  END IF;
  SELECT jsonb_build_object(
    'signedIn',COALESCE(jsonb_agg(eu.event ORDER BY eu.event),'[]'::jsonb),
    'saved',(SELECT COALESCE(jsonb_agg(es.event ORDER BY es.event),'[]'::jsonb)
      FROM public.event_users_saved es JOIN public.events e ON e.id=es.event
      WHERE es."user"=p_participant_id AND e.occasion=v_occasion))
    INTO v_private_payload FROM public.event_users eu JOIN public.events e ON e.id=eu.event
    WHERE eu."user"=p_participant_id AND e.occasion=v_occasion;
  IF v_is_publishable THEN
    SELECT source_revision INTO v_live_revision FROM public.client_sync_scopes
      WHERE component='live_public' AND scope_type='occasion' AND scope_id=v_occasion;
    INSERT INTO public.event_public_state
      (occasion,event,participant_count,saved_count,remaining_capacity,revision,projected_at)
    SELECT v_occasion,v_event.id,count(DISTINCT eu."user"),count(DISTINCT es."user"),
      CASE WHEN v_event.max_participants IS NULL THEN NULL
        ELSE GREATEST(v_event.max_participants-count(DISTINCT eu."user"),0) END,
      v_live_revision,clock_timestamp()
    FROM (SELECT 1) seed LEFT JOIN public.event_users eu ON eu.event=v_event.id
    LEFT JOIN public.event_users_saved es ON es.event=v_event.id
    ON CONFLICT (occasion,event) DO UPDATE SET
      participant_count=EXCLUDED.participant_count,saved_count=EXCLUDED.saved_count,
      remaining_capacity=EXCLUDED.remaining_capacity,revision=EXCLUDED.revision,
      projected_at=EXCLUDED.projected_at;
    SELECT jsonb_build_object(
      'events',COALESCE(jsonb_agg(jsonb_build_object('eventId',s.event,
        'participantCount',s.participant_count,'savedCount',s.saved_count,
        'remainingCapacity',s.remaining_capacity) ORDER BY s.event),'[]'::jsonb),
      'cleaning',(SELECT COALESCE(jsonb_agg(jsonb_build_object('placeId',c.place,
        'status',c.status,'openReportCount',c.open_report_count) ORDER BY c.place),'[]'::jsonb)
        FROM public.cleaning_public_state c WHERE c.occasion=v_occasion))
      INTO v_live_payload FROM public.event_public_state s JOIN public.events e ON e.id=s.event
      WHERE s.occasion=v_occasion AND NOT e.is_hidden;
  END IF;
  v_response:=jsonb_build_object('status','applied','code',200,
    'data',jsonb_build_object('eventId',p_event_id,'participantId',p_participant_id,
      'isSignedIn',p_action='sign_in'),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit->>'commitId','replayed',false,'occurredAt',v_commit->>'occurredAt'),
    'sync',jsonb_build_object('replacements',
      CASE WHEN v_is_publishable THEN jsonb_build_array(jsonb_build_object(
        'component','live_public','revision',v_live_revision,
        'payload',v_live_payload)) ELSE '[]'::jsonb END ||
      CASE WHEN v_actor=p_participant_id THEN jsonb_build_array(jsonb_build_object(
        'component','private_program','revision',v_private_revision,
        'payload',v_private_payload)) ELSE '[]'::jsonb END ||
        CASE WHEN v_needs_occasion_join OR v_companion_owner=v_actor
          THEN jsonb_build_array(jsonb_build_object(
          'component','private_profile','revision',v_profile_revision,
          'payload',v_profile_payload)) ELSE '[]'::jsonb END));
  RETURN public.finish_client_mutation_v1(p_command_id,v_response,
    (v_commit->>'commitId')::uuid);
END; $function$
;

REVOKE ALL ON FUNCTION public.set_event_attendance_client_sync_v1(p_event_id bigint, p_participant_id uuid, p_action text, p_command_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.set_event_attendance_client_sync_v1(p_event_id bigint, p_participant_id uuid, p_action text, p_command_id uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.set_event_attendance_client_sync_v1(bigint,uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_event_attendance_client_sync_v1(bigint,uuid,text,uuid) TO authenticated,service_role;
