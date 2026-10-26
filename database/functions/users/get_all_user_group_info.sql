CREATE OR REPLACE FUNCTION public.get_all_user_groups(p_occasion_id bigint, p_type text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
    groups_json jsonb;
    game_defs_json jsonb;
    places_json jsonb;
    result_data jsonb;
BEGIN
    -- Authorization Check: User must have editor view permissions for the occasion.
    IF NOT get_is_editor_view_on_occasion(p_occasion_id) THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;

    SELECT COALESCE(
        jsonb_agg(to_jsonb(p) ORDER BY p."order" NULLS LAST, p.title),
        '[]'::jsonb
    )
    INTO places_json
    FROM public.places p
    WHERE p.occasion = p_occasion_id
      AND NOT p.is_hidden
      AND p.coordinates->'latLng'->>'lat' IS NOT NULL
      AND p.coordinates->'latLng'->>'lng' IS NOT NULL;

    -- If authorized, fetch all matching groups for the occasion.
    SELECT
        COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', ugi.id,
                'title', ugi.title,
                'description', ugi.description,
                'type', ugi.type,
                'data', ugi.data,
                'place', ugi.place,
                'places', ( -- Nested place object
                    SELECT row_to_json(p)::jsonb
                    FROM public.places p
                    WHERE p.id = ugi.place
                ),
                'user_groups', ( -- Nested array of participants with admin status
                    SELECT COALESCE(jsonb_agg(
                        jsonb_build_object(
                            'is_admin', ug.is_admin,
                            -- The user_info object now only contains id, name, and surname.
                            'user_info', jsonb_build_object(
                                'id', p_ui.id,
                                'name', p_ui.name,
                                'surname', p_ui.surname
                            )
                        )
                    ), '[]'::jsonb)
                    FROM public.user_groups ug
                    JOIN public.user_info p_ui ON ug."user" = p_ui.id
                    WHERE ug."group" = ugi.id
                )
            )
        ), '[]'::jsonb)
    INTO groups_json
    FROM public.user_group_info ugi
    WHERE ugi.occasion = p_occasion_id
      AND (p_type IS NULL AND ugi.type IS NULL OR ugi.type = p_type);

    -- If the requested type is 'game', also fetch the game definitions (checkpoints).
    IF p_type = 'game' THEN
        SELECT jsonb_object_agg(info.id, info.title)
        INTO game_defs_json
        FROM public.information info
        WHERE info.type = 'game' AND info.occasion = p_occasion_id;
    END IF;

    -- Combine the results into a single data object.
    result_data := jsonb_build_object(
        'groups', groups_json,
        'game_definitions', game_defs_json,
        'places', places_json
    );

    -- Return the data directly on success.
    RETURN result_data;
END;
$$;
