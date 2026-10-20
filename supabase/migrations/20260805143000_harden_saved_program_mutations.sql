-- Scope legacy saved-program writes to one occasion and serialize them with
-- the Client Sync V1 command. Both paths use the same transaction lock key.
CREATE OR REPLACE FUNCTION public.set_saved_program(
    p_occasion BIGINT,
    p_event_ids BIGINT[],
    p_mode TEXT
)
RETURNS BIGINT[]
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_ids BIGINT[];
    v_saved BIGINT[];
BEGIN
    IF v_actor IS NULL OR p_mode NOT IN ('join', 'remove', 'replace')
       OR cardinality(COALESCE(p_event_ids, '{}')) > 5000
       OR NOT EXISTS (
           SELECT 1 FROM public.occasion_users ou
           WHERE ou.occasion = p_occasion AND ou."user" = v_actor
       ) THEN
        RAISE insufficient_privilege USING MESSAGE = 'invalid saved-program command';
    END IF;

    SELECT COALESCE(array_agg(DISTINCT input.event_id ORDER BY input.event_id), '{}')
    INTO v_ids
    FROM unnest(COALESCE(p_event_ids, '{}')) AS input(event_id);

    IF EXISTS (
        SELECT 1 FROM unnest(v_ids) AS input(event_id)
        LEFT JOIN public.events e
          ON e.id = input.event_id AND e.occasion = p_occasion
        WHERE e.id IS NULL
    ) THEN
        RAISE invalid_parameter_value
            USING MESSAGE = 'saved program contains cross-scope events';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(
        'saved-program:' || v_actor::text || ':' || p_occasion::text, 0));

    IF p_mode = 'replace' THEN
        DELETE FROM public.event_users_saved es USING public.events e
        WHERE es.event = e.id AND es."user" = v_actor
          AND e.occasion = p_occasion AND NOT es.event = ANY(v_ids);
    ELSIF p_mode = 'remove' THEN
        DELETE FROM public.event_users_saved es
        WHERE es."user" = v_actor AND es.event = ANY(v_ids);
    END IF;

    IF p_mode IN ('join', 'replace') THEN
        INSERT INTO public.event_users_saved(event, "user")
        SELECT input.event_id, v_actor
        FROM unnest(v_ids) AS input(event_id)
        ON CONFLICT DO NOTHING;
    END IF;

    SELECT COALESCE(array_agg(es.event ORDER BY es.event), '{}') INTO v_saved
    FROM public.event_users_saved es JOIN public.events e ON e.id = es.event
    WHERE es."user" = v_actor AND e.occasion = p_occasion;
    RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.set_saved_program(BIGINT, BIGINT[], TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_saved_program(BIGINT, BIGINT[], TEXT)
    TO authenticated;

-- Keep the V1 mutation's existing transactional implementation, but ensure
-- even an idempotent/no-op response contains a revisioned private replacement.
-- Without the revision a delayed no-op response cannot be safely ordered
-- against a mutation performed on another device.
ALTER FUNCTION public.set_saved_program_client_sync_v1(BIGINT, BIGINT[], TEXT, UUID)
  RENAME TO set_saved_program_client_sync_v1_transactional;

REVOKE ALL ON FUNCTION public.set_saved_program_client_sync_v1_transactional(
  BIGINT, BIGINT[], TEXT, UUID
) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.set_saved_program_client_sync_v1(
  p_occasion BIGINT,
  p_event_ids BIGINT[],
  p_mode TEXT,
  p_command_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_response JSONB;
  v_revision BIGINT;
  v_payload JSONB;
BEGIN
  v_response := public.set_saved_program_client_sync_v1_transactional(
    p_occasion, p_event_ids, p_mode, p_command_id
  );

  IF jsonb_array_length(v_response #> '{sync,replacements}') = 0 THEN
    SELECT source_revision INTO v_revision
    FROM public.client_sync_private_scopes
    WHERE component = 'private_program'
      AND occasion = p_occasion
      AND user_id = v_actor;

    IF v_revision IS NOT NULL THEN
      SELECT jsonb_build_object(
        'signedIn', (
          SELECT COALESCE(jsonb_agg(eu.event ORDER BY eu.event), '[]'::jsonb)
          FROM public.event_users eu
          JOIN public.events e ON e.id = eu.event
          WHERE eu."user" = v_actor AND e.occasion = p_occasion
        ),
        'saved', (
          SELECT COALESCE(jsonb_agg(es.event ORDER BY es.event), '[]'::jsonb)
          FROM public.event_users_saved es
          JOIN public.events e ON e.id = es.event
          WHERE es."user" = v_actor AND e.occasion = p_occasion
        )
      ) INTO v_payload;

      v_response := jsonb_set(
        v_response,
        '{sync,replacements}',
        jsonb_build_array(jsonb_build_object(
          'component', 'private_program',
          'revision', v_revision,
          'payload', v_payload
        ))
      );
    END IF;
  END IF;

  RETURN v_response;
END;
$$;

REVOKE ALL ON FUNCTION public.set_saved_program_client_sync_v1(
  BIGINT, BIGINT[], TEXT, UUID
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_saved_program_client_sync_v1(
  BIGINT, BIGINT[], TEXT, UUID
) TO authenticated;
