CREATE OR REPLACE FUNCTION public.get_user_group_info_with_users(p_group_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE
    v_occasion_id bigint;
    v_is_member boolean;
    v_is_editor_view boolean;
    v_current_user_is_admin boolean;
    result_json jsonb;
BEGIN
    -- Check if the group exists and get its occasion for permission checks.
    SELECT occasion INTO v_occasion_id FROM public.user_group_info WHERE id = p_group_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'USER_GROUP_NOT_FOUND';
    END IF;

    -- Authorization Check: User must be a member or have editor view permissions on the occasion.
    SELECT EXISTS (SELECT 1 FROM public.user_groups WHERE "group" = p_group_id AND "user" = auth.uid()) INTO v_is_member;
    v_is_editor_view := get_is_editor_view_on_occasion(v_occasion_id);

    IF NOT v_is_member AND NOT v_is_editor_view THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;

    -- Get the current user's admin status for this specific group.
    SELECT is_admin INTO v_current_user_is_admin FROM public.user_groups WHERE "group" = p_group_id AND "user" = auth.uid();

    -- If authorized, build the final JSON object.
    SELECT
        jsonb_build_object(
            'id', ugi.id,
            'title', ugi.title,
            'description', ugi.description,
            'type', ugi.type,
            'data', ugi.data,
            'place', ugi.place, -- This is placeId
            'is_admin', COALESCE(v_current_user_is_admin, false),
            'places', (SELECT row_to_json(p)::jsonb||jsonb_build_object('aggregate_version',COALESCE((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='place' AND scope_type='occasion' AND scope_id=v_occasion_id AND aggregate_id=p.id::text),0)) FROM public.places p WHERE p.id = ugi.place),
            'user_groups', (
                SELECT COALESCE(jsonb_agg(
                    jsonb_build_object(
                        'is_admin', ug.is_admin,
                        'user_info', row_to_json(p_ui)::jsonb
                    )
                ), '[]'::jsonb)
                FROM public.user_groups ug
                JOIN public.user_info p_ui ON ug."user" = p_ui.id
                WHERE ug."group" = ugi.id
            )
        )
    INTO result_json
    FROM public.user_group_info ugi
    WHERE ugi.id = p_group_id;

    RETURN result_json;
END;
$function$
;
