CREATE OR REPLACE FUNCTION public.submit_event_feedback_internal_v1(p_event bigint, p_rating text, p_note text DEFAULT NULL::text, p_client_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_event public.events%ROWTYPE;
    v_user UUID := auth.uid();
    v_note TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
    v_is_limited BOOLEAN;
    v_is_editor BOOLEAN;
    v_feedback public.event_feedback%ROWTYPE;
BEGIN
    IF p_rating NOT IN ('happy', 'neutral', 'sad') THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Invalid rating');
    END IF;

    IF char_length(COALESCE(v_note, '')) > 2000 THEN
        RETURN jsonb_build_object('code', 413, 'message', 'Feedback text is too long');
    END IF;

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
        RETURN jsonb_build_object('code', 404, 'message', 'Feedback feature is not enabled for this occasion');
    END IF;

    IF COALESCE(v_event.data->>'feedback_enabled', 'false') <> 'true' THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Feedback is not enabled for this event');
    END IF;

    v_is_editor := public.get_is_editor_view_on_occasion(v_event.occasion);

    IF now() < v_event.start_time AND NOT v_is_editor THEN
        RETURN jsonb_build_object('code', 409, 'message', 'Feedback is not open yet');
    END IF;

    v_is_limited := COALESCE(v_event.max_participants, 0) > 0;
    IF v_is_limited AND NOT v_is_editor THEN
        IF v_user IS NULL THEN
            RETURN jsonb_build_object('code', 401, 'message', 'Sign in is required for feedback on this event');
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM public.event_users eu
            WHERE eu.event = p_event
              AND eu."user" = v_user
        ) THEN
            RETURN jsonb_build_object('code', 403, 'message', 'Only signed-in participants can rate this event');
        END IF;
    END IF;

    IF v_user IS NULL AND p_client_id IS NULL THEN
        RETURN jsonb_build_object('code', 401, 'message', 'Client id is required for anonymous feedback');
    END IF;

    IF v_user IS NOT NULL THEN
        INSERT INTO public.event_feedback (event, occasion, "user", rating, note)
        VALUES (p_event, v_event.occasion, v_user, p_rating, v_note)
        ON CONFLICT (event, "user") WHERE "user" IS NOT NULL
        DO UPDATE SET
            rating = EXCLUDED.rating,
            note = EXCLUDED.note,
            updated_at = now()
        RETURNING * INTO v_feedback;
    ELSE
        INSERT INTO public.event_feedback (event, occasion, client_id, rating, note)
        VALUES (p_event, v_event.occasion, p_client_id, p_rating, v_note)
        ON CONFLICT (event, client_id) WHERE "user" IS NULL AND client_id IS NOT NULL
        DO UPDATE SET
            rating = EXCLUDED.rating,
            note = EXCLUDED.note,
            updated_at = now()
        RETURNING * INTO v_feedback;
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
$function$
;

REVOKE ALL ON FUNCTION public.submit_event_feedback_internal_v1(p_event bigint, p_rating text, p_note text, p_client_id uuid) FROM PUBLIC,anon,authenticated;
