CREATE OR REPLACE FUNCTION public.get_event_feedback_export_for_edit(
    p_occasion bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    v_items JSONB;
BEGIN
    IF NOT (
        public.get_is_editor_view_on_occasion(p_occasion)
        OR public.get_is_admin_on_occasion(p_occasion)
    ) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'Insufficient permissions'
        );
    END IF;

    IF NOT public.get_is_event_feedback_enabled_on_occasion(p_occasion) THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Feedback feature is not enabled for this occasion'
        );
    END IF;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'event_id', e.id,
                'event_title', e.title,
                'event_start_time', e.start_time,
                'event_end_time', e.end_time,
                'feedback_id', f.id,
                'created_at', f.created_at,
                'updated_at', f.updated_at,
                'rating', f.rating,
                'note', f.note,
                'user_name', NULLIF(
                    btrim(CONCAT_WS(' ', ui.name, ui.surname)), ''
                ),
                'is_anonymous', f."user" IS NULL
            )
            ORDER BY e.start_time ASC, e.title ASC, f.updated_at DESC
        ),
        '[]'::jsonb
    )
    INTO v_items
    FROM public.event_feedback f
    JOIN public.events e ON e.id = f.event
    LEFT JOIN public.user_info ui ON ui.id = f."user"
    WHERE f.occasion = p_occasion;

    RETURN jsonb_build_object('code', 200, 'data', v_items);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_event_feedback_export_for_edit(bigint)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_event_feedback_export_for_edit(bigint)
  TO authenticated, service_role;
