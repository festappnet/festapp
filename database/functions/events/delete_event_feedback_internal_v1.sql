CREATE OR REPLACE FUNCTION public.delete_event_feedback_internal_v1(p_event bigint, p_client_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_deleted INTEGER := 0;
BEGIN
    IF v_user IS NULL AND p_client_id IS NULL THEN
        RETURN jsonb_build_object('code', 401, 'message', 'Client id is required for anonymous feedback');
    END IF;

    IF v_user IS NOT NULL THEN
        DELETE FROM public.event_feedback
        WHERE event = p_event
          AND "user" = v_user;
    ELSE
        DELETE FROM public.event_feedback
        WHERE event = p_event
          AND "user" IS NULL
          AND client_id = p_client_id;
    END IF;

    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object('deleted', v_deleted)
    );
END;
$function$
;

REVOKE ALL ON FUNCTION public.delete_event_feedback_internal_v1(p_event bigint, p_client_id uuid) FROM PUBLIC,anon,authenticated;
