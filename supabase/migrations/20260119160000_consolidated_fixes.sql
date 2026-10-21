-- Consolidated migration for recent changes
-- Includes:
-- 1. Unit creation localization and restriction
-- 2. Organization admin access RPCs
-- 3. get_app_config_v217 with fixed unit switching logic
-- 4. Fix for duplicate create_user_from_registration function

DROP FUNCTION IF EXISTS create_user_from_registration(bigint, text, text, jsonb, text);

-- 1. create_user_from_registration with localized default
CREATE OR REPLACE FUNCTION create_user_from_registration(
    org bigint, 
    email text, 
    password text, 
    data jsonb,
    unit_title text DEFAULT 'Moje akce'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    is_registration_enabled BOOLEAN;
    new_user_id uuid;
    v_new_unit_id bigint;
BEGIN
    -- Retrieve IS_REGISTRATION_ENABLED value from organizations.data JSON
    SELECT (organizations.data->>'IS_REGISTRATION_ENABLED')::boolean
      INTO is_registration_enabled
    FROM organizations
    WHERE id = org;

    -- CHECK: If registration is enabled OR if the caller is a manager/editor
    IF NOT is_registration_enabled AND NOT (
           get_is_manager_on_any_occasion()
           OR EXISTS (
               SELECT 1
               FROM occasions o
               WHERE o.organization = org
               AND get_is_editor_on_unit(o.unit)
           )
       ) THEN
        RETURN jsonb_build_object('code', 403, 'error', 'Registration is disabled for this organization');
    END IF;

    -- Call the PURE function to create the user
    new_user_id := create_user_in_organization_with_data_pure(org, email, password, data);

    INSERT INTO public.units (title, organization, data)
    VALUES (
        unit_title, 
        org,
        jsonb_build_object(
            'reply_to', lower(trim(email)),
            'timezone', 'Europe/Prague'
        )
    )
    RETURNING id INTO v_new_unit_id;

    INSERT INTO public.unit_users (unit, "user", is_manager, is_editor, is_editor_view)
    VALUES (v_new_unit_id, new_user_id, true, true, true);

    RETURN jsonb_build_object('code', 200, 'id', new_user_id);
END;
$$;

-- Drop the old 4-argument version to resolve ambiguity
DROP FUNCTION IF EXISTS create_user_from_registration(bigint, text, text, jsonb);

-- 2. create_unit_and_assign_manager (Manual Creation)
DROP FUNCTION IF EXISTS create_unit_and_assign_manager(text);
CREATE OR REPLACE FUNCTION create_unit_and_assign_manager(
  title text
) RETURNS jsonb
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_org_id bigint;
  v_email text;
  v_new_unit_id bigint;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('code', 401, 'message', 'Unauthorized');
  END IF;

  SELECT organization, email_readonly 
  INTO v_org_id, v_email
  FROM public.user_info 
  WHERE id = v_user_id;

  IF v_org_id IS NULL THEN
     RETURN jsonb_build_object('code', 404, 'message', 'User info or organization not found');
  END IF;

  -- Check if unit creation is enabled for organization
  DECLARE
      v_is_enabled boolean;
  BEGIN
      SELECT (data->>'IS_UNIT_CREATION_ENABLED')::boolean 
      INTO v_is_enabled
      FROM public.organizations 
      WHERE id = v_org_id;
      
      IF v_is_enabled IS NOT TRUE THEN
          RETURN jsonb_build_object('code', 403, 'message', 'Unit creation is disabled for this organization');
      END IF;
  END;

  INSERT INTO public.units (title, organization, data)
  VALUES (
    title, 
    v_org_id,
    jsonb_build_object(
        'reply_to', lower(trim(COALESCE(v_email, ''))),
        'timezone', 'Europe/Prague'
    )
  )
  RETURNING id INTO v_new_unit_id;

  INSERT INTO public.unit_users (unit, "user", is_manager, is_editor, is_editor_view)
  VALUES (v_new_unit_id, v_user_id, true, true, true);

  RETURN jsonb_build_object(
    'code', 200, 
    'message', 'Unit created successfully', 
    'data', jsonb_build_object('id', v_new_unit_id)
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- 3. Organization Admin RPCs

DROP FUNCTION IF EXISTS check_is_admin_of_organization(bigint);

CREATE OR REPLACE FUNCTION check_is_admin_of_organization(organization_id bigint)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM organization_users
    WHERE "user" = auth.uid()
      AND organization = organization_id
      AND is_admin = true
  );
END;
$$;

DROP FUNCTION IF EXISTS get_organization_admin(bigint);
CREATE OR REPLACE FUNCTION get_organization_admin(organization_id bigint)
RETURNS SETOF organizations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Verify admin status
  IF EXISTS (
    SELECT 1
    FROM organization_users
    WHERE "user" = auth.uid()
      AND organization = organization_id
      AND is_admin = true
  ) THEN
    -- Return the organization record
    RETURN QUERY SELECT * FROM organizations WHERE id = organization_id;
  ELSE
    -- Raise distinct exception or return nothing
    RAISE EXCEPTION 'Access Denied: User is not an admin of this organization.';
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS update_organization_admin(bigint, text, jsonb);
CREATE OR REPLACE FUNCTION update_organization_admin(
  organization_id bigint,
  title text,
  data jsonb
)
RETURNS SETOF organizations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Verify admin status
  IF EXISTS (
    SELECT 1
    FROM organization_users
    WHERE "user" = auth.uid()
      AND organization = organization_id
      AND is_admin = true
  ) THEN
    -- Update the organization record
    RETURN QUERY
    UPDATE organizations
    SET 
      title = COALESCE(update_organization_admin.title, organizations.title),
      data = organizations.data || update_organization_admin.data
    WHERE id = organization_id
    RETURNING *;
  ELSE
    RAISE EXCEPTION 'Access Denied: User is not an admin of this organization.';
  END IF;
END;
$$;

-- 4. get_app_config_v217 (FIXED logic)

DROP FUNCTION IF EXISTS get_app_config_v217(jsonb);

CREATE OR REPLACE FUNCTION get_app_config_v217(
    data_in jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    org_id bigint := (data_in->>'organization')::bigint;
    link_txt text := data_in->>'link';
    form_link text := data_in->>'form_link';
    unit_id bigint := (data_in->>'unit_id')::bigint;
    platform_info jsonb := data_in->'platform';
    platform_name text := platform_info->>'platform';
    occasionId bigint;
    default_unit bigint;
    is_open_bool BOOLEAN;
    is_app_supported_bool BOOLEAN := FALSE;
    occasion_user occasion_users%rowtype;
    unit_user unit_users%rowtype;
    is_admin_bool BOOLEAN;
    occasion_link text;
    version_recommended text;
    version_link text;
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
        SELECT forms.occasion, occasions.link
          INTO occasionId, occasion_link
        FROM forms
        JOIN occasions ON forms.occasion = occasions.id
        WHERE forms.link = form_link
          AND occasions.organization = org_id;
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

    -- Retrieve version_recommended and version_link
    SELECT
        item->>'prompt',
        item->>'link'
    INTO
        version_recommended,
        version_link
    FROM
        public.organizations,
        jsonb_array_elements(data->'PLATFORMS') AS item
    WHERE
        id = org_id AND item->>'platform' = platform_name
    LIMIT 1;

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
                    'version_recommended', version_recommended,
                    'version_link', version_link,
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
        -- If no occasion is set, use default_unit as context
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
        -- If occasion_unit is NULL here but unit_json is NOT NULL, we should preserve it!
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
            'occasions', user_occasions_json
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
        'version_recommended', version_recommended,
        'version_link', version_link,
        'bank_accounts_admin', COALESCE(bank_account_ids, '{}'),
        'user_info', COALESCE(user_info_json, '{}'::jsonb),
        'organization', COALESCE(org_json::jsonb, '{}'::jsonb),
        'groups', COALESCE(user_groups_json, '{}'::jsonb)
    );
END;
$function$;
