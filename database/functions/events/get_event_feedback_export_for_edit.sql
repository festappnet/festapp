CREATE OR REPLACE FUNCTION public.get_event_feedback_export_page_internal_v1(
    p_occasion bigint
,p_after bigint DEFAULT NULL,p_limit integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    v_items JSONB;
BEGIN
    IF NOT public.can_read_schedule_feedback(p_occasion) THEN
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
                'is_anonymous', ui.id IS NULL
            )
            ORDER BY e.start_time ASC, e.title ASC, f.updated_at DESC
        ),
        '[]'::jsonb
    )
    INTO v_items
    FROM (SELECT * FROM public.event_feedback WHERE occasion=p_occasion AND (p_after IS NULL OR id>p_after) ORDER BY id LIMIT p_limit) f
    JOIN public.events e ON e.id = f.event
    LEFT JOIN public.user_info ui ON ui.id = f."user" AND public.organization_member_visible_internal(ui.organization,ui.id)
    WHERE f.occasion = p_occasion;

    RETURN jsonb_build_object('code', 200, 'data', v_items);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_event_feedback_export_page_internal_v1(bigint,bigint,integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_event_feedback_export_for_edit(p_occasion bigint)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_event_feedback_export_page_internal_v1(p_occasion,NULL,NULL);
$$;
REVOKE ALL ON FUNCTION public.get_event_feedback_export_for_edit(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_event_feedback_export_for_edit(bigint) TO authenticated;
