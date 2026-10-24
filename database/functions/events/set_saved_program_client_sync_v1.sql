CREATE OR REPLACE FUNCTION public.set_saved_program_client_sync_v1(p_occasion bigint, p_event_ids bigint[], p_mode text, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
$function$
;

REVOKE ALL ON FUNCTION public.set_saved_program_client_sync_v1(p_occasion bigint, p_event_ids bigint[], p_mode text, p_command_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.set_saved_program_client_sync_v1(p_occasion bigint, p_event_ids bigint[], p_mode text, p_command_id uuid) TO authenticated;
