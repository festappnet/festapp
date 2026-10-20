CREATE OR REPLACE FUNCTION public.delete_event_feedback_for_edit_client_sync_v1(p_occasion bigint, p_feedback bigint, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_organization bigint;
    v_begin jsonb;
    v_hash text;
    v_feedback public.event_feedback%ROWTYPE;
    v_private_impacts jsonb := '[]'::jsonb;
    v_replacements jsonb := '[]'::jsonb;
BEGIN
    SELECT o.organization
    INTO v_organization
    FROM public.occasions o
    WHERE o.id = p_occasion;

    IF v_actor IS NULL
       OR v_organization IS NULL
       OR NOT public.check_is_admin_of_organization(v_organization) THEN
        RAISE insufficient_privilege
            USING MESSAGE = 'occasion admin required';
    END IF;

    v_hash := encode(extensions.digest(convert_to(jsonb_build_object(
        'occasion', p_occasion,
        'feedback', p_feedback
    )::text, 'UTF8'), 'sha256'), 'hex');
    v_begin := public.begin_client_mutation_v1(
        p_command_id,
        'feedback.admin_delete',
        p_occasion,
        v_actor,
        v_hash
    );
    IF v_begin->>'disposition' = 'replay' THEN
        RETURN v_begin->'response';
    END IF;

    SELECT f.*
    INTO v_feedback
    FROM public.event_feedback f
    WHERE f.id = p_feedback
      AND f.occasion = p_occasion
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN public.complete_client_mutation_outcome_v1(
            p_command_id,
            'unchanged',
            200,
            jsonb_build_object('deleted', false)
        );
    END IF;

    DELETE FROM public.event_feedback
    WHERE id = v_feedback.id;

    IF v_feedback."user" IS NOT NULL AND EXISTS (
        SELECT 1
        FROM public.occasion_users ou
        WHERE ou.occasion = p_occasion
          AND ou."user" = v_feedback."user"
    ) THEN
        v_private_impacts := jsonb_build_array(jsonb_build_object(
            'component', 'private_feedback',
            'userId', v_feedback."user"
        ));
        IF v_feedback."user" = v_actor THEN
            v_replacements := jsonb_build_array(jsonb_build_object(
                'component', 'private_feedback',
                'userId', v_actor,
                'payload', public.get_private_feedback_payload_v1(
                    p_occasion,
                    v_actor
                )
            ));
        END IF;
    END IF;

    RETURN public.complete_client_mutation_applied_v1(
        p_command_id,
        p_occasion,
        'feedback.admin_delete',
        'feedback',
        jsonb_build_array(jsonb_build_object(
            'entityType', 'event_feedback',
            'entityId', v_feedback.id,
            'operation', 'delete',
            'safeLabel', 'Event feedback',
            'changedFields', jsonb_build_array('aggregate')
        )),
        '{}'::text[],
        v_private_impacts,
        '[]'::jsonb,
        jsonb_build_object('deleted', true),
        '{}'::text[],
        '[]'::jsonb,
        'user',
        NULL,
        v_replacements
    );
END;
$function$
;

REVOKE ALL ON FUNCTION public.delete_event_feedback_for_edit_client_sync_v1(p_occasion bigint, p_feedback bigint, p_command_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.delete_event_feedback_for_edit_client_sync_v1(p_occasion bigint, p_feedback bigint, p_command_id uuid) TO authenticated;
