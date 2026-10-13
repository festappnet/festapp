CREATE OR REPLACE FUNCTION public.get_app_config_v218(data_in jsonb)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    org_id bigint := (data_in->>'organization')::bigint;
    link_txt text := data_in->>'link';
    form_link text := data_in->>'form_link';
    unit_id bigint := (data_in->>'unit_id')::bigint;
    platform_info jsonb := data_in->'platform';
    platform_name text := platform_info->>'platform';
    occasionId bigint;
    default_unit bigint;
    editor_unit_id bigint;
    is_open_bool BOOLEAN;
    is_app_supported_bool BOOLEAN := FALSE;
    occasion_user occasion_users%rowtype;
    unit_user unit_users%rowtype;
    is_admin_bool BOOLEAN;
    occasion_link text;
    occasion_unit bigint;
    bank_account_ids bigint[];
    occasion_json jsonb;
    unit_json jsonb;
    user_info_json jsonb;
    org_json jsonb;
    user_groups_json jsonb;
    is_editor_view_on_occasion_bool BOOLEAN;
    user_occasions_json jsonb;
    user_units_json jsonb;
    current_user_id UUID := auth.uid();
BEGIN
    -- Log the request details in log_app_config table
    INSERT INTO public.log_app_config (organization, platform)
    VALUES (org_id, platform_info);

    -- Map "pwa" to "web" for platform consistency
    IF platform_name = 'pwa' THEN
        platform_name := 'web';
    END IF;

    -- =========================================================
    -- RESOLVE CONTEXT (Occasion vs Unit)
    -- Priority: Form/Link > Representative Occasion > Unit ID > Default Occasion
    -- =========================================================

    -- 1. Try to find occasion via form_link
    IF form_link IS NOT NULL AND form_link <> '' THEN
        SELECT f.occasion, o.link
          INTO occasionId, occasion_link
        FROM public.forms f
        JOIN public.occasions o ON f.occasion = o.id
        WHERE f.link = form_link
          AND o.organization = org_id;
    END IF;

    -- 2. If no occasion found yet, try via link_txt
    IF occasionId IS NULL AND link_txt IS NOT NULL AND link_txt <> '' THEN
        SELECT id, link
          INTO occasionId, occasion_link
        FROM occasions
        WHERE link = link_txt
          AND organization = org_id;

        -- If link_txt is provided but *not* found, this is a hard 404.
        IF occasionId IS NULL THEN
            RETURN json_build_object(
                'code', 404,
                'message', 'Occasion not found'
            );
        END IF;
    END IF;

    -- 3. If no specific link found, check for REPRESENTATIVE OCCASION
    IF occasionId IS NULL AND unit_id IS NULL THEN
        SELECT (data->>'REPRESENTATIVE_OCCASION')::bigint
          INTO occasionId
        FROM organizations
        WHERE id = org_id;

        -- If found, fetch its link for consistency
        IF occasionId IS NOT NULL THEN
            SELECT link INTO occasion_link
            FROM occasions
            WHERE id = occasionId AND organization = org_id;
        END IF;
    END IF;

    -- 4. If no occasion (and no Representative Occasion), try to use unit_id
    IF occasionId IS NULL AND unit_id IS NOT NULL THEN
        occasionId := NULL; -- Ensure no occasion is loaded.

        default_unit := unit_id;

        SELECT json_build_object('id', u.id, 'title', u.title, 'data', u.data)
            INTO unit_json
        FROM units u
        WHERE u.id = default_unit;

        SELECT *
            INTO unit_user
        FROM unit_users
        WHERE unit = default_unit
            AND "user" = current_user_id;

    -- If no occasion and no unit found yet, try Default Occasion
    ELSIF occasionId IS NULL THEN
        -- Try to get the DEFAULT_OCCASION (Representative was already checked in step 3)
        SELECT (data->>'DEFAULT_OCCASION')::bigint
          INTO occasionId
        FROM organizations
        WHERE id = org_id;

        IF occasionId IS NOT NULL THEN
            -- Default occasion exists; fetch its link
            SELECT link
              INTO occasion_link
            FROM occasions
            WHERE id = occasionId AND organization = org_id;
        END IF;
    END IF;

    -- =========================================================
    -- GATHER DATA
    -- =========================================================

    IF occasionId IS NOT NULL THEN
        -- Process occasion-related queries only if an occasion was determined

        -- Get the is_open status for the occasion
        SELECT is_open
          INTO is_open_bool
        FROM occasions
        WHERE id = occasionId;

        -- Get the occasion user record if it exists
        SELECT *
          INTO occasion_user
        FROM occasion_users
        WHERE occasion = occasionId
          AND "user" = current_user_id;

        -- Retrieve the unit ID from the occasion
        SELECT unit
          INTO occasion_unit
        FROM occasions
        WHERE id = occasionId;

        -- Get the unit user record if it exists
        SELECT *
          INTO unit_user
        FROM unit_users
        WHERE unit = occasion_unit
          AND "user" = current_user_id;

        -- Check if the current user is an admin on the occasion
        is_admin_bool := get_is_admin_on_occasion(occasionId);

        -- Check if the current user has editor_view permissions on the occasion
        is_editor_view_on_occasion_bool := get_is_editor_view_on_occasion(occasionId);

        -- Retrieve IS_APP_SUPPORTED from Organization data. Defaults to FALSE.
        SELECT COALESCE((data->>'IS_APP_SUPPORTED')::boolean, FALSE)
          INTO is_app_supported_bool
        FROM organizations
        WHERE id = org_id;

        -- If the occasion is not open, enforce access restrictions
        -- BUT bypass this check if is_app_supported_bool is FALSE.
        IF is_open_bool = FALSE AND is_app_supported_bool = TRUE THEN
            IF is_editor_view_on_occasion_bool <> TRUE
               AND (SELECT get_is_editor_order_view_on_occasion(occasionId)) <> TRUE
               AND (SELECT get_is_editor_on_unit(occasion_unit)) <> TRUE THEN
                RETURN json_build_object(
                    'code', 403,
                    'message', 'Access forbidden',
                    'link', occasion_link,
                    'unit_user', COALESCE(row_to_json(unit_user)::jsonb, NULL)
                );
            END IF;
        END IF;

        -- If the occasion user record is not found and the user is authenticated, add the user to the occasion
        IF occasion_user IS NULL AND current_user_id IS NOT NULL THEN
            IF is_app_supported_bool IS TRUE 
               OR (unit_user.is_manager IS TRUE OR unit_user.is_editor IS TRUE OR unit_user.is_editor_view IS TRUE) THEN
                PERFORM add_user_to_occasion(occasionId, current_user_id);

                SELECT *
                  INTO occasion_user
                FROM occasion_users
                WHERE occasion = occasionId
                  AND "user" = current_user_id;
            END IF;
        END IF;
    ELSE
        -- If no occasion is set (because a specific unit was used and no Rep Occasion existed), use the unit as the context
        occasion_unit := default_unit;
        is_admin_bool := false;
    END IF;

    -- Retrieve unit_user again in case the user was added and now belongs to the unit
    IF unit_user IS NULL AND occasion_unit IS NOT NULL AND current_user_id IS NOT NULL THEN
        SELECT *
          INTO unit_user
        FROM unit_users
        WHERE unit = occasion_unit
          AND "user" = current_user_id;
    END IF;

    -- Fetch list of bank account IDs where the user is an admin
    SELECT array_agg(bank_account)
      INTO bank_account_ids
    FROM eshop.bank_account_users
    WHERE "user" = current_user_id
      AND is_admin = true;

    -- Fetch full occasion details as a JSON object if an occasion is set
    IF occasionId IS NOT NULL THEN
        SELECT row_to_json(o)
          INTO occasion_json
        FROM occasions o
        WHERE o.id = occasionId;
    ELSE
        occasion_json := '{}'::jsonb;
    END IF;

    -- Fetch full unit details as a JSON object
    IF occasion_unit IS NOT NULL THEN
        SELECT json_build_object('id', u.id, 'title', u.title, 'data', u.data)
          INTO unit_json
        FROM units u
        WHERE u.id = occasion_unit;
    ELSE
        IF unit_json IS NULL THEN
            unit_json := '{}'::jsonb;
        END IF;
    END IF;

    -- Fetch occasions for the user based on the specified logic
    IF occasion_unit IS NOT NULL AND current_user_id IS NOT NULL THEN
        IF is_editor_view_on_occasion_bool OR (current_user_id IS NOT NULL AND (SELECT get_is_editor_on_unit(occasion_unit))) THEN
            -- If user is an editor or unit editor, get all occasions for the unit
            SELECT json_agg(json_build_object('id', o.id, 'title', o.title, 'link', o.link, 'start_time', o.start_time, 'end_time', o.end_time) ORDER BY o.start_time DESC)
            INTO user_occasions_json
            FROM (
                SELECT * FROM public.occasions
                WHERE unit = occasion_unit
                ORDER BY start_time DESC
                LIMIT 100
            ) o;
        ELSE
            -- Otherwise, get only occasions the user is explicitly on for that unit
            -- AND where they have privileged access (manager, editor, etc.)
            SELECT json_agg(
                json_build_object(
                    'id', o.id, 
                    'title', o.title, 
                    'link', o.link, 
                    'start_time', o.start_time, 
                    'end_time', o.end_time
                ) ORDER BY o.start_time DESC
            )
            INTO user_occasions_json
            FROM (
                 SELECT o.*
                 FROM public.occasions o
                 JOIN public.occasion_users ou ON ou.occasion = o.id
                 WHERE ou."user" = current_user_id
                 AND o.unit = occasion_unit
                 AND (
                     ou.is_manager IS TRUE 
                     OR ou.is_editor IS TRUE 
                     OR ou.is_editor_view IS TRUE 
                     OR ou.is_editor_order IS TRUE 
                     OR ou.is_editor_order_view IS TRUE
                 )
                 ORDER BY o.start_time DESC
                 LIMIT 100
            ) o;
        END IF;
    END IF;

    -- Fetch units for the user based on unit rights or occasion rights
    SELECT json_agg(jsonb_build_object('id', u.id, 'title', u.title) ORDER BY u.title)
    INTO user_units_json
    FROM public.units u
    WHERE (
        EXISTS (
            SELECT 1 
            FROM public.unit_users uu 
            WHERE uu.unit = u.id 
            AND uu."user" = current_user_id 
            AND uu.is_editor_view = TRUE
        )
        OR
        EXISTS (
            SELECT 1 
            FROM public.occasions o
            JOIN public.occasion_users ou ON ou.occasion = o.id
            WHERE o.unit = u.id 
            AND ou."user" = current_user_id
            AND (
                ou.is_manager IS TRUE 
                OR ou.is_editor IS TRUE 
                OR ou.is_editor_view IS TRUE 
                OR ou.is_editor_order IS TRUE 
                OR ou.is_editor_order_view IS TRUE
            )
        )
    );

    -- Fetch user information along with associated units and occasions
    SELECT row_to_json(ui)::jsonb || jsonb_build_object(
            'units', COALESCE(user_units_json, '[]'::jsonb),
            'occasions', COALESCE(user_occasions_json, '[]'::jsonb)
          )
      INTO user_info_json
    FROM public.user_info ui
    WHERE ui.id = current_user_id;

    -- Fetch organization info
    SELECT json_build_object(
        'title', title,
        'APP_NAME', data->>'APP_NAME',
        'PLATFORMS', data->'PLATFORMS',
        'DEFAULT_URL', data->>'DEFAULT_URL',
        'DEFAULT_LANGUAGE', data->>'DEFAULT_LANGUAGE',
        'IS_REGISTRATION_ENABLED', (data->>'IS_REGISTRATION_ENABLED')::boolean,
        'IS_UNIT_CREATION_ENABLED', (data->>'IS_UNIT_CREATION_ENABLED')::boolean,
        'IS_APP_SUPPORTED', (data->>'IS_APP_SUPPORTED')::boolean,
        'DEFAULT_UNIT', (data->>'DEFAULT_UNIT')::int,
        'REPRESENTATIVE_OCCASION', (data->>'REPRESENTATIVE_OCCASION')::int
    ) INTO org_json
    FROM public.organizations
    WHERE id = org_id;

    -- Fetch the user's groups for the specific occasion
    IF occasionId IS NOT NULL THEN
        user_groups_json := public.get_user_groups(occasionId);
    END IF;

    RETURN json_build_object(
        'code', 200,
        'is_admin', is_admin_bool,
        'occasion_user', COALESCE(row_to_json(occasion_user)::jsonb, NULL),
        'unit_user', COALESCE(row_to_json(unit_user)::jsonb, NULL),
        'occasion', COALESCE(occasion_json, '{}'::jsonb),
        'unit', COALESCE(unit_json, '{}'::jsonb),
        'bank_accounts_admin', COALESCE(bank_account_ids, '{}'),
        'user_info', COALESCE(user_info_json, '{}'::jsonb),
        'organization', COALESCE(org_json::jsonb, '{}'::jsonb),
        'groups', COALESCE(user_groups_json, '{}'::jsonb)
    );
END;
$$;
