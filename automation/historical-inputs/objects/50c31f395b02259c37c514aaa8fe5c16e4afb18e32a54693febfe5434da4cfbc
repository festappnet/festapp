CREATE OR REPLACE FUNCTION public.get_event_feedback_for_edit(p_event bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    v_occasion BIGINT;
    v_summary JSONB;
    v_items JSONB;
BEGIN
    SELECT occasion
    INTO v_occasion
    FROM public.events
    WHERE id = p_event;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Event not found');
    END IF;

    IF NOT public.get_is_editor_view_on_occasion(v_occasion) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'Insufficient permissions'
        );
    END IF;

    IF NOT public.get_is_event_feedback_enabled_on_occasion(v_occasion) THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Feedback feature is not enabled for this occasion'
        );
    END IF;

    SELECT jsonb_build_object(
        'total', COUNT(*),
        'happy', COUNT(*) FILTER (WHERE rating = 'happy'),
        'neutral', COUNT(*) FILTER (WHERE rating = 'neutral'),
        'sad', COUNT(*) FILTER (WHERE rating = 'sad')
    )
    INTO v_summary
    FROM public.event_feedback
    WHERE event = p_event;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', f.id,
                'created_at', f.created_at,
                'updated_at', f.updated_at,
                'rating', f.rating,
                'note', f.note,
                'user_name', NULLIF(
                    btrim(CONCAT_WS(' ', ui.name, ui.surname)), ''
                ),
                'is_anonymous', f."user" IS NULL
            )
            ORDER BY f.updated_at DESC
        ),
        '[]'::jsonb
    )
    INTO v_items
    FROM public.event_feedback f
    LEFT JOIN public.user_info ui ON ui.id = f."user"
    WHERE f.event = p_event;

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'summary', v_summary,
            'items', v_items
        )
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_event_feedback_for_edit(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_event_feedback_for_edit(bigint)
  TO authenticated, service_role;
