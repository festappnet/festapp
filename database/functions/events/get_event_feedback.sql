CREATE OR REPLACE FUNCTION public.get_event_feedback(
    p_event bigint,
    p_client_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    v_event public.events%ROWTYPE;
    v_user UUID := auth.uid();
    v_feedback public.event_feedback%ROWTYPE;
BEGIN
    SELECT *
    INTO v_event
    FROM public.events
    WHERE id = p_event
      AND is_hidden = false;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Event not found');
    END IF;

    IF NOT public.get_is_event_allowed(p_event) THEN
        RETURN jsonb_build_object('code', 403, 'message', 'Event is not available');
    END IF;

    IF NOT public.get_is_event_feedback_enabled_on_occasion(v_event.occasion) THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Feedback feature is not enabled for this occasion'
        );
    END IF;

    IF v_user IS NOT NULL THEN
        SELECT *
        INTO v_feedback
        FROM public.event_feedback
        WHERE event = p_event
          AND "user" = v_user
        LIMIT 1;
    ELSIF p_client_id IS NOT NULL THEN
        SELECT *
        INTO v_feedback
        FROM public.event_feedback
        WHERE event = p_event
          AND "user" IS NULL
          AND client_id = p_client_id
        LIMIT 1;
    ELSE
        RETURN jsonb_build_object('code', 200, 'data', NULL);
    END IF;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 200, 'data', NULL);
    END IF;

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'id', v_feedback.id,
            'event', v_feedback.event,
            'rating', v_feedback.rating,
            'note', v_feedback.note,
            'created_at', v_feedback.created_at,
            'updated_at', v_feedback.updated_at
        )
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_event_feedback(bigint, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_event_feedback(bigint, uuid)
  TO anon, authenticated, service_role;
