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
    v_organization_admin boolean := false;
    v_context_organization public.organizations%ROWTYPE;
    v_context_occasion public.occasions%ROWTYPE;
    v_membership_added boolean := false;
    v_demo boolean := false;
    v_demo_read boolean := false;
    v_demo_unit_ids bigint[];
    occasion_link text;
    occasion_unit bigint;
    bank_account_ids bigint[];
    bank_capabilities jsonb;
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
    -- A direct unit link must stay inside the requested tenant.
    IF unit_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.units u
        WHERE u.id = unit_id AND u.organization = org_id
    ) THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Unit not found');
    END IF;

    SELECT * INTO v_context_organization FROM public.organizations WHERE id=org_id;
    v_organization_admin := public.can_manage_organization_settings(org_id);

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
        SELECT o.* INTO v_context_occasion
        FROM public.forms f
        JOIN public.occasions o ON f.occasion = o.id
        WHERE f.id = public.resolve_form_link_internal(form_link)
          AND o.organization = org_id;
        occasionId := v_context_occasion.id;
        occasion_link := v_context_occasion.link;
        IF occasionId IS NULL THEN
            RETURN jsonb_build_object('code',404,'message','Form not found');
        END IF;
    END IF;

    -- 2. If no occasion found yet, try via link_txt
    IF occasionId IS NULL AND link_txt IS NOT NULL AND link_txt <> '' THEN
        SELECT o.* INTO v_context_occasion
        FROM public.occasions o
        WHERE o.id = public.resolve_occasion_link_internal(link_txt,org_id)
          AND o.organization = org_id;
        occasionId := v_context_occasion.id;
        occasion_link := v_context_occasion.link;

        -- If link_txt is provided but *not* found, this is a hard 404.
        IF occasionId IS NULL THEN
            RETURN jsonb_build_object(
                'code', 404,
                'message', 'Occasion not found'
            );
        END IF;
    END IF;

    -- 3. If no specific link found, check for REPRESENTATIVE OCCASION
    IF occasionId IS NULL AND unit_id IS NULL THEN
        occasionId := (v_context_organization.data->>'REPRESENTATIVE_OCCASION')::bigint;

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

        SELECT jsonb_build_object('id', u.id, 'title', u.title, 'data', u.data)
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
        occasionId := (v_context_organization.data->>'DEFAULT_OCCASION')::bigint;

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

        -- Link/form resolution already loaded this exact tenant-bound row.
        -- Reuse it within the request instead of reading it a second time.
        IF v_context_occasion.id IS DISTINCT FROM occasionId THEN
          SELECT o.* INTO v_context_occasion FROM public.occasions o
            WHERE o.id=occasionId AND o.organization=org_id;
        END IF;
        IF v_context_occasion.id IS NULL THEN
          RETURN jsonb_build_object('code',404,'message','Occasion not found');
        END IF;
        is_open_bool := v_context_occasion.is_open;
        occasion_unit := v_context_occasion.unit;
        v_demo := public.is_demo_occasion(occasionId);
        v_demo_read := CASE WHEN v_demo THEN public.can_read_demo_occasion(occasionId) ELSE false END;
        IF v_demo AND NOT v_demo_read THEN
            RETURN jsonb_build_object('code',403,'message','Demo access denied');
        END IF;

        -- Get the occasion user record if it exists
        SELECT *
          INTO occasion_user
        FROM occasion_users
        WHERE occasion = occasionId
          AND "user" = current_user_id;

        -- Get the unit user record if it exists
        SELECT *
          INTO unit_user
        FROM unit_users
        WHERE unit = occasion_unit
          AND "user" = current_user_id;

        -- Check if the current user is an admin on the occasion
        is_admin_bool := public.active_membership(
          v_organization_admin,v_demo);

        -- Check if the current user has editor_view permissions on the occasion
        is_editor_view_on_occasion_bool := public.readable_membership(occasion_user.is_editor_view,v_demo,v_demo_read);

        -- Retrieve IS_APP_SUPPORTED from Organization data. Defaults to FALSE.
        is_app_supported_bool := coalesce((v_context_organization.data->>'IS_APP_SUPPORTED')::boolean,false);

        -- If the occasion is not open, enforce access restrictions
        -- BUT bypass this check if is_app_supported_bool is FALSE.
        IF is_open_bool = FALSE AND is_app_supported_bool = TRUE THEN
            IF NOT public.context_private_access_rule(is_editor_view_on_occasion_bool,
               public.can_read_orders(occasionId),public.get_is_editor_on_unit(occasion_unit)) THEN
                RETURN jsonb_build_object(
                    'code', 403,
                    'message', 'Access forbidden',
                    'link', occasion_link,
                    'unit_user', COALESCE(to_jsonb(unit_user)::jsonb, NULL)
                );
            END IF;
        END IF;

        -- If the occasion user record is not found and the user is authenticated, add the user to the occasion
        IF occasion_user IS NULL AND current_user_id IS NOT NULL AND NOT public.is_demo_occasion(occasionId) THEN
            IF is_app_supported_bool IS TRUE
               OR public.unit_discovery_rule(unit_user.is_editor,unit_user.is_manager,unit_user.is_editor_view) THEN
                PERFORM add_user_to_occasion(occasionId, current_user_id);
                v_membership_added := true;

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

    -- Request-local facts for this projection only. Writers independently
    -- reauthorize against the live registry; this is never a permission cache.
    SELECT coalesce(array_agg(demo.unit_id),'{}'::bigint[]) INTO v_demo_unit_ids
      FROM public.demo_unit_ids_internal() demo;

    -- Fetch list of bank account IDs where the user is an admin
    SELECT array_agg(m.bank_account),jsonb_object_agg(m.bank_account,
      CASE WHEN public.bank_account_write_rule(m.is_admin,managed.bank_account IS NOT NULL,protected.bank_account IS NOT NULL)
        THEN public.bank_context_capabilities(true,true,false)
        ELSE public.bank_context_capabilities(false,false,false) END)
      INTO bank_account_ids,bank_capabilities
    FROM eshop.bank_account_users m
    LEFT JOIN (SELECT DISTINCT link.bank_account FROM eshop.unit_bank_accounts link
      JOIN public.unit_users membership ON membership.unit=link.unit
      WHERE membership."user"=current_user_id AND membership.is_manager
        AND NOT membership.unit=ANY(v_demo_unit_ids)) managed
      ON managed.bank_account=m.bank_account
    LEFT JOIN (SELECT DISTINCT bank_account FROM public.demo_occasions) protected
      ON protected.bank_account=m.bank_account
    WHERE m."user"=current_user_id AND m.is_admin=true;

    -- Fetch full occasion details as a JSON object if an occasion is set
    IF occasionId IS NOT NULL THEN
        IF v_membership_added THEN
            SELECT to_jsonb(o) INTO occasion_json FROM public.occasions o WHERE o.id=occasionId;
        ELSE
            occasion_json := to_jsonb(v_context_occasion);
        END IF;
    ELSE
        occasion_json := '{}'::jsonb;
    END IF;

    -- Fetch full unit details as a JSON object
    IF occasion_unit IS NOT NULL AND unit_json IS NULL THEN
        SELECT jsonb_build_object('id', u.id, 'title', u.title, 'data', u.data)
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
        IF public.occasion_list_read_rule(is_editor_view_on_occasion_bool,
          current_user_id IS NOT NULL AND public.get_is_editor_on_unit(occasion_unit)) THEN
            -- If user is an editor or unit editor, get all occasions for the unit
            SELECT jsonb_agg(jsonb_build_object('id', o.id, 'title', o.title, 'link', o.link, 'start_time', o.start_time, 'end_time', o.end_time) ORDER BY o.start_time DESC)
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
            SELECT jsonb_agg(
                jsonb_build_object(
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
                 AND public.occasion_staff_navigation_rule(ou.is_manager,ou.is_editor,ou.is_editor_view,ou.is_editor_order,ou.is_editor_order_view)
                 ORDER BY o.start_time DESC
                 LIMIT 100
            ) o;
        END IF;
    END IF;

    -- Fetch units for the user based on unit rights or occasion rights
    SELECT jsonb_agg(jsonb_build_object('id', u.id, 'title', u.title) ORDER BY u.title)
    INTO user_units_json
    FROM public.units u
    WHERE u.organization = org_id AND (
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
            AND public.occasion_staff_navigation_rule(ou.is_manager,ou.is_editor,ou.is_editor_view,ou.is_editor_order,ou.is_editor_order_view)
        )
    );

    -- Fetch user information along with associated units and occasions
    SELECT to_jsonb(ui)::jsonb || jsonb_build_object(
            'units', COALESCE(user_units_json, '[]'::jsonb),
            'occasions', COALESCE(user_occasions_json, '[]'::jsonb)
          )
      INTO user_info_json
    FROM public.user_info ui
    WHERE ui.id = current_user_id;

    -- Fetch organization info
    org_json := CASE WHEN v_context_organization.id IS NOT NULL THEN jsonb_build_object(
        'title', v_context_organization.title,
        'APP_NAME', v_context_organization.data->>'APP_NAME',
        'PLATFORMS', v_context_organization.data->'PLATFORMS',
        'DEFAULT_URL', v_context_organization.data->>'DEFAULT_URL',
        'DEFAULT_LANGUAGE', v_context_organization.data->>'DEFAULT_LANGUAGE',
        'IS_REGISTRATION_ENABLED', (v_context_organization.data->>'IS_REGISTRATION_ENABLED')::boolean,
        'IS_UNIT_CREATION_ENABLED', (v_context_organization.data->>'IS_UNIT_CREATION_ENABLED')::boolean,
        'IS_APP_SUPPORTED', (v_context_organization.data->>'IS_APP_SUPPORTED')::boolean,
        'DEFAULT_UNIT', (v_context_organization.data->>'DEFAULT_UNIT')::int,
        'REPRESENTATIVE_OCCASION', (v_context_organization.data->>'REPRESENTATIVE_OCCASION')::int
    ) ELSE NULL END;

    -- Fetch the user's groups for the specific occasion
    IF occasionId IS NOT NULL THEN
        user_groups_json := public.get_user_groups_for_context_internal_v1(occasionId,
          public.active_membership(occasion_user.is_editor,v_demo),
          public.readable_membership(occasion_user.is_editor_view,v_demo,v_demo_read),NOT v_demo);
    END IF;

    RETURN jsonb_build_object(
        'code', 200,
        'is_admin', is_admin_bool,
        'capabilities', public.get_context_capabilities_v1(occasionId,occasion_user,unit_user,is_admin_bool,
          v_demo,coalesce(COALESCE(occasion_unit,default_unit)=ANY(v_demo_unit_ids),false),v_demo_read,
          coalesce(jsonb_array_length(user_units_json),0)>0,
          EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(user_units_json,'[]'::jsonb)) listed
            WHERE (listed->>'id')::bigint=occasion_unit),
          public.reception_enabled(occasion_json->'features')) || public.organization_context_capabilities(v_organization_admin),
        'demo_read_only', v_demo_read,
        'occasion_user', COALESCE(to_jsonb(occasion_user)::jsonb, NULL),
        'unit_user', COALESCE(to_jsonb(unit_user)::jsonb, NULL),
        'occasion', COALESCE(occasion_json, '{}'::jsonb),
        'unit', COALESCE(unit_json, '{}'::jsonb),
        'bank_accounts_admin', COALESCE(bank_account_ids, '{}'),
        'bank_capabilities',coalesce(bank_capabilities,'{}'::jsonb),
        'user_info', COALESCE(user_info_json, '{}'::jsonb),
        'organization', COALESCE(org_json::jsonb, '{}'::jsonb),
        'groups', COALESCE(user_groups_json, '{}'::jsonb)
    );
END;
$$;
