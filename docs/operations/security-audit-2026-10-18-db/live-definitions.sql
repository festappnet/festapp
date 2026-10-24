-- Audit snapshot only. Do not apply these historical definitions.
-- Read from the verified canonical database in BEGIN READ ONLY.

-- SHA-256: c1583d07c83faf3178c0a0172c1aba7acd543cd5e81457750b422bf0894fe16a
CREATE OR REPLACE FUNCTION public.set_user_password(usr uuid, oc bigint, password text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  declare
  encrypted_pw text;
BEGIN
    IF (SELECT get_is_manager_on_occasion(oc)) <> TRUE AND (SELECT get_is_admin_on_occasion(oc)) <> TRUE THEN
        RETURN NULL;
    END IF;

    IF (select get_exists_on_occasion_user(usr, oc)) <> TRUE THEN
       RETURN NULL;
    END IF;

    encrypted_pw := crypt(password, gen_salt('bf'));

    UPDATE auth.users
    SET encrypted_password = encrypted_pw
    WHERE auth.users.id = usr;
    RETURN usr;
END;
$function$

-- SHA-256: 88f4d54791df62ac4ec93c7e147ab6c259d1314c4f3b70aca58e7ec75aca34e9
CREATE OR REPLACE FUNCTION public.create_user_in_organization_with_data(org bigint, email text, password text, data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    is_registration_enabled BOOLEAN;
    usr uuid;
    encrypted_pw text;
    user_meta_data jsonb := '{}';
    _key   text;
    _value text;
    trimmed_data jsonb := '{}';
    original_email text;
BEGIN
    -- Trim and lower the email input
    original_email := lower(trim(email));

    -- Add organization prefix to the email for auth tables
    email := format('%s+%s', org, original_email);

    -- Retrieve IS_REGISTRATION_ENABLED value from organizations.data JSON
    SELECT (organizations.data->>'IS_REGISTRATION_ENABLED')::boolean
      INTO is_registration_enabled
    FROM organizations
    WHERE id = org;

    -- Check if registration is enabled OR if the caller is a manager on any occasion
    -- OR if the caller is an editor on at least one unit associated with an occasion in this organization.


    -- Trim all values in the data JSONB object and build a new trimmed_data JSONB object
    FOR _key, _value IN
        SELECT key, value FROM jsonb_each_text(data)
    LOOP
        IF _value IS NOT NULL THEN
            trimmed_data := jsonb_set(trimmed_data, array[_key], to_jsonb(trim(_value)), true);
        ELSE
            trimmed_data := jsonb_set(trimmed_data, array[_key], 'null'::jsonb, true);
        END IF;
    END LOOP;

    usr := gen_random_uuid();
    encrypted_pw := crypt(password, gen_salt('bf'));

    -- Insert into auth.users with the email prefixed with organization
    INSERT INTO auth.users
      (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
    VALUES
      ('00000000-0000-0000-0000-000000000000', usr, 'authenticated', 'authenticated', email, encrypted_pw, now(), NULL, NULL,
      '{"provider":"email","providers":["email"]}', user_meta_data, now(), now(), '', '', '', '');

    -- Insert into auth.identities with the email prefixed with organization
    INSERT INTO auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    VALUES
      (gen_random_uuid(), usr, usr, format('{"sub":"%s","email":"%s"}', usr::text, email)::jsonb, 'email', NULL, now(), now());

    -- Insert into user_info with the original email (without prefix)
    INSERT INTO user_info (id, email_readonly, name, surname, sex, data, organization)
    VALUES (usr, original_email, COALESCE(trimmed_data->>'name', ''), COALESCE(trimmed_data->>'surname', ''), COALESCE(trimmed_data->>'sex', ''), trimmed_data, org);

    RETURN usr;
END;
$function$

-- SHA-256: cce00958af561ea2f5473e05810458a42bdd8bc9b1a1ad82ba2829bc36b06fed
CREATE OR REPLACE FUNCTION public.get_is_manager_on_any_occasion()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT COALESCE((
    SELECT true
    FROM occasion_users
    WHERE "user" = auth.uid() AND is_manager = true
    LIMIT 1
  ), false);
$function$

-- SHA-256: 17b3a33b6955b2ccec2be85bc840f6f8dafcf7bc700e97bec43a89829500cb18
CREATE OR REPLACE FUNCTION public.get_can_reset_user_password(p_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_current_user_id uuid:=auth.uid();v_has_permission boolean:=false;
v_is_unit_manager_path boolean;v_is_occasion_manager_path boolean;v_target_has_elevated_privileges boolean;v_target_is_org_admin boolean;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_user_id) THEN RETURN false; END IF;
    -- Priority 1: Self-Reset. A user can always change their own password.
    IF v_current_user_id = p_user_id THEN
        v_has_permission := TRUE;
    END IF;

    -- Priority 2: Organization admin for a user belonging to their organization.
    -- A merged user may have a different home organization in user_info while
    -- participating in this organization's occasion or unit.
    IF NOT v_has_permission THEN
        SELECT EXISTS (
            SELECT 1
            FROM public.organization_users cou
            WHERE cou."user" = v_current_user_id
              AND cou.is_admin = TRUE
              AND (
                  EXISTS (
                      SELECT 1 FROM public.user_info tui
                      WHERE tui.id = p_user_id
                        AND tui.organization = cou.organization
                  )
                  OR EXISTS (
                      SELECT 1 FROM public.occasion_users tou
                      JOIN public.occasions o ON o.id = tou.occasion
                      WHERE tou."user" = p_user_id
                        AND o.organization = cou.organization
                  )
                  OR EXISTS (
                      SELECT 1 FROM public.unit_users tu
                      JOIN public.units u ON u.id = tu.unit
                      WHERE tu."user" = p_user_id
                        AND u.organization = cou.organization
                  )
              )
        ) INTO v_has_permission;
    END IF;

    -- Priority 3: Unit Manager Path (with new negative check).
    IF NOT v_has_permission THEN
        -- Step 3a: Check if the current user has Unit Manager rights over the target user.
        WITH target_user_units AS (
            SELECT unit AS unit_id FROM public.unit_users WHERE "user" = p_user_id
            UNION
            SELECT o.unit AS unit_id FROM public.occasion_users ou JOIN public.occasions o ON ou.occasion = o.id WHERE ou."user" = p_user_id
        )
        SELECT EXISTS (
            SELECT 1
            FROM public.unit_users uu
            JOIN target_user_units tuu ON uu.unit = tuu.unit_id
            WHERE uu."user" = v_current_user_id AND uu.is_manager = TRUE
        ) INTO v_is_unit_manager_path;

        IF v_is_unit_manager_path THEN
            -- Step 3b: **NEW NEGATIVE CHECK**. A Unit Manager cannot change an Org Admin's password.
            SELECT EXISTS (
                SELECT 1 FROM public.organization_users
                WHERE "user" = p_user_id AND is_admin = TRUE
            ) INTO v_target_is_org_admin;

            -- Grant permission only if the target user is NOT an Organization Admin.
            IF NOT v_target_is_org_admin THEN
                v_has_permission := TRUE;
            END IF;
        END IF;
    END IF;

    -- Priority 4: Unit editors can manage ordinary users in their unit, but
    -- cannot reset credentials of users with elevated roles anywhere.
    IF NOT v_has_permission THEN
        SELECT EXISTS (
            SELECT 1 FROM public.unit_users editor_uu
            WHERE editor_uu."user" = v_current_user_id
              AND editor_uu.is_editor = TRUE
              AND (
                  EXISTS (
                      SELECT 1 FROM public.unit_users target_uu
                      WHERE target_uu."user" = p_user_id
                        AND target_uu.unit = editor_uu.unit
                  )
                  OR EXISTS (
                      SELECT 1 FROM public.occasion_users target_ou
                      JOIN public.occasions o ON o.id = target_ou.occasion
                      WHERE target_ou."user" = p_user_id
                        AND o.unit = editor_uu.unit
                  )
              )
        )
        AND NOT EXISTS (
            SELECT 1 FROM public.organization_users target_org
            WHERE target_org."user" = p_user_id AND target_org.is_admin = TRUE
        )
        AND NOT EXISTS (
            SELECT 1 FROM public.unit_users target_unit
            WHERE target_unit."user" = p_user_id
              AND (target_unit.is_manager OR target_unit.is_editor OR target_unit.is_editor_view)
        )
        AND NOT EXISTS (
            SELECT 1 FROM public.occasion_users target_occasion
            WHERE target_occasion."user" = p_user_id
              AND (target_occasion.is_manager OR target_occasion.is_editor
                   OR target_occasion.is_editor_view OR target_occasion.is_editor_order
                   OR target_occasion.is_editor_order_view)
        ) INTO v_has_permission;
    END IF;

    -- Priority 5: Occasion Manager Path (with expanded security check).
    IF NOT v_has_permission THEN
        -- Step 4a: Check if a direct manager->user link exists on any single occasion.
        SELECT EXISTS (
          SELECT 1 FROM public.occasion_users AS manager_ou
          JOIN public.occasion_users AS target_ou ON manager_ou.occasion = target_ou.occasion
          WHERE manager_ou."user" = v_current_user_id
            AND manager_ou.is_manager = TRUE
            AND target_ou."user" = p_user_id
        ) INTO v_is_occasion_manager_path;

        IF v_is_occasion_manager_path THEN
            -- Step 4b: EXPANDED NEGATIVE CHECK. Target must not have any elevated privileges.
            SELECT EXISTS (
              SELECT 1 FROM public.unit_users
              WHERE "user" = p_user_id AND (is_manager = TRUE OR is_editor = TRUE OR is_editor_view = TRUE)
            ) INTO v_target_has_elevated_privileges;

            IF NOT v_target_has_elevated_privileges THEN
                SELECT EXISTS (
                    SELECT 1 FROM public.organization_users
                    WHERE "user" = p_user_id AND is_admin = TRUE
                ) INTO v_target_has_elevated_privileges;
            END IF;

            IF NOT v_target_has_elevated_privileges THEN
                v_has_permission := TRUE;
            END IF;
        END IF;
    END IF;

    -- Final permission enforcement.
 RETURN v_has_permission;
END $function$
