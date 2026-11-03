-- Avoid production PL/pgSQL ambiguity between generic `id` aliases and
-- surrounding statements. This is a forward repair; the applied expansion
-- migration remains immutable.
CREATE OR REPLACE FUNCTION public.set_saved_program_client_sync_v1(
  p_occasion bigint,p_event_ids bigint[],p_mode text,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_ids bigint[]; v_before bigint[]; v_after bigint[];
  v_changed_ids bigint[]; v_begin jsonb; v_hash text; v_commit jsonb;
  v_private_revision bigint; v_live_revision bigint; v_private_payload jsonb;
  v_live_payload jsonb; v_response jsonb;
  v_is_publishable boolean;
BEGIN
  IF v_actor IS NULL OR p_mode NOT IN ('join','remove','replace')
    OR cardinality(COALESCE(p_event_ids,'{}'))>5000
    OR NOT EXISTS (SELECT 1 FROM public.occasion_users ou
      WHERE ou.occasion=p_occasion AND ou."user"=v_actor) THEN
    RAISE insufficient_privilege USING MESSAGE='invalid saved-program command';
  END IF;
  SELECT NOT o.is_hidden INTO STRICT v_is_publishable
  FROM public.occasions o WHERE o.id=p_occasion;
  SELECT COALESCE(array_agg(DISTINCT input.event_id ORDER BY input.event_id),'{}')
    INTO v_ids
    FROM unnest(COALESCE(p_event_ids,'{}')) AS input(event_id);
  IF EXISTS (
    SELECT 1
    FROM unnest(v_ids) AS input(event_id)
    LEFT JOIN public.events e
      ON e.id=input.event_id AND e.occasion=p_occasion
    WHERE e.id IS NULL
  ) THEN
    RAISE invalid_parameter_value USING MESSAGE='saved program contains cross-scope events';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'eventIds',to_jsonb(v_ids),'mode',p_mode)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'program.saved.'||p_mode,
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'saved-program:'||v_actor::text||':'||p_occasion::text,0));
  SELECT COALESCE(array_agg(es.event ORDER BY es.event),'{}') INTO v_before
    FROM public.event_users_saved es JOIN public.events e ON e.id=es.event
    WHERE es."user"=v_actor AND e.occasion=p_occasion;
  IF p_mode='replace' THEN
    DELETE FROM public.event_users_saved es USING public.events e
      WHERE es.event=e.id AND es."user"=v_actor AND e.occasion=p_occasion
        AND NOT es.event=ANY(v_ids);
    INSERT INTO public.event_users_saved(event,"user")
      SELECT input.event_id,v_actor
      FROM unnest(v_ids) AS input(event_id)
      ON CONFLICT DO NOTHING;
  ELSIF p_mode='join' THEN
    INSERT INTO public.event_users_saved(event,"user")
      SELECT input.event_id,v_actor
      FROM unnest(v_ids) AS input(event_id)
      ON CONFLICT DO NOTHING;
  ELSE
    DELETE FROM public.event_users_saved es
      WHERE es."user"=v_actor AND es.event=ANY(v_ids);
  END IF;
  SELECT COALESCE(array_agg(es.event ORDER BY es.event),'{}') INTO v_after
    FROM public.event_users_saved es JOIN public.events e ON e.id=es.event
    WHERE es."user"=v_actor AND e.occasion=p_occasion;
  IF v_before=v_after THEN
    v_response:=jsonb_build_object('status','unchanged','code',200,
      'data',jsonb_build_object('saved',to_jsonb(v_after)),
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;
  SELECT array_agg(DISTINCT changed.event_id ORDER BY changed.event_id)
    INTO v_changed_ids
    FROM (
      (SELECT unnest(v_before) event_id EXCEPT SELECT unnest(v_after))
      UNION
      (SELECT unnest(v_after) event_id EXCEPT SELECT unnest(v_before))
    ) changed;
  v_commit:=public.record_client_sync_commit_v1(p_occasion,'program.saved.'||p_mode,
    'saved_program',jsonb_build_array(jsonb_build_object('entityType','saved_program',
      'entityId',v_actor,'operation','update','safeLabel','Saved program',
      'changedFields',jsonb_build_array('event_ids'))),
    CASE WHEN v_is_publishable THEN ARRAY['live_public'] ELSE '{}'::text[] END,
    jsonb_build_array(jsonb_build_object('component','private_program','userId',v_actor)),
    CASE WHEN v_is_publishable THEN (
      SELECT jsonb_agg(jsonb_build_object(
        'component','live_public','entityId',changed.event_id
      ))
      FROM unnest(v_changed_ids) AS changed(event_id)
    ) ELSE '[]'::jsonb END,'user',NULL);
  SELECT source_revision INTO v_private_revision FROM public.client_sync_private_scopes
    WHERE component='private_program' AND occasion=p_occasion AND user_id=v_actor;
  SELECT jsonb_build_object(
    'signedIn',(SELECT COALESCE(jsonb_agg(eu.event ORDER BY eu.event),'[]'::jsonb)
      FROM public.event_users eu JOIN public.events e ON e.id=eu.event
      WHERE eu."user"=v_actor AND e.occasion=p_occasion),
    'saved',to_jsonb(v_after)) INTO v_private_payload;
  IF v_is_publishable THEN
    SELECT source_revision INTO v_live_revision FROM public.client_sync_scopes
      WHERE component='live_public' AND scope_type='occasion' AND scope_id=p_occasion;
    INSERT INTO public.event_public_state
      (occasion,event,participant_count,saved_count,remaining_capacity,revision,projected_at)
    SELECT e.occasion,e.id,count(DISTINCT eu."user"),count(DISTINCT es."user"),
      CASE WHEN e.max_participants IS NULL THEN NULL
        ELSE GREATEST(e.max_participants-count(DISTINCT eu."user"),0) END,
      v_live_revision,clock_timestamp()
    FROM public.events e LEFT JOIN public.event_users eu ON eu.event=e.id
    LEFT JOIN public.event_users_saved es ON es.event=e.id
    WHERE e.occasion=p_occasion AND e.id=ANY(v_changed_ids)
    GROUP BY e.occasion,e.id,e.max_participants
    ON CONFLICT (occasion,event) DO UPDATE SET participant_count=EXCLUDED.participant_count,
      saved_count=EXCLUDED.saved_count,remaining_capacity=EXCLUDED.remaining_capacity,
      revision=EXCLUDED.revision,projected_at=EXCLUDED.projected_at;
    SELECT jsonb_build_object(
      'events',COALESCE(jsonb_agg(jsonb_build_object('eventId',s.event,
        'participantCount',s.participant_count,'savedCount',s.saved_count,
        'remainingCapacity',s.remaining_capacity) ORDER BY s.event),'[]'::jsonb),
      'cleaning',(SELECT COALESCE(jsonb_agg(jsonb_build_object('placeId',c.place,
        'status',c.status,'openReportCount',c.open_report_count) ORDER BY c.place),'[]'::jsonb)
        FROM public.cleaning_public_state c WHERE c.occasion=p_occasion))
      INTO v_live_payload FROM public.event_public_state s JOIN public.events e ON e.id=s.event
      WHERE s.occasion=p_occasion AND NOT e.is_hidden;
  END IF;
  v_response:=jsonb_build_object('status','applied','code',200,
    'data',jsonb_build_object('saved',to_jsonb(v_after)),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit->>'commitId','replayed',false,'occurredAt',v_commit->>'occurredAt'),
    'sync',jsonb_build_object('replacements',
      CASE WHEN v_is_publishable THEN jsonb_build_array(jsonb_build_object(
        'component','live_public','revision',v_live_revision,
        'payload',v_live_payload)) ELSE '[]'::jsonb END ||
      jsonb_build_array(jsonb_build_object('component','private_program',
        'revision',v_private_revision,'payload',v_private_payload))));
  RETURN public.finish_client_mutation_v1(p_command_id,v_response,
    (v_commit->>'commitId')::uuid);
END; $$;

REVOKE ALL ON FUNCTION public.set_saved_program_client_sync_v1(bigint,bigint[],text,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_saved_program_client_sync_v1(bigint,bigint[],text,uuid)
  TO authenticated;
