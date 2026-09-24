-- Align password reset permissions with the users administration roles and
-- merged cross-organization memberships.
CREATE OR REPLACE FUNCTION public.reset_user_password(p_user_id uuid, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_current_user_id uuid := auth.uid();
  v_has_permission boolean := false;
  v_encrypted_pw text;
  v_is_unit_manager_path boolean;
  v_is_occasion_manager_path boolean;
  v_target_has_elevated_privileges boolean;
  v_target_is_org_admin boolean;
BEGIN
    -- =================================================================
    -- 1. INPUT VALIDATION
    -- =================================================================
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION '%',
            jsonb_build_object('code', 4000, 'message', 'Input data is invalid: User ID is missing')::text;
    END IF;

    IF p_password IS NULL OR trim(p_password) = '' THEN
        RAISE EXCEPTION '%',
            jsonb_build_object('code', 4000, 'message', 'Input data is invalid: Password cannot be empty')::text;
    END IF;

    -- =================================================================
    -- 2. USER EXISTENCE CHECK
    -- =================================================================
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
        RAISE EXCEPTION '%',
            jsonb_build_object('code', 4040, 'message', 'User not found')::text;
    END IF;


    -- =================================================================
    -- 3. PERMISSION CHECKS (HIERARCHICAL LOGIC)
    -- =================================================================
    -- The function checks for permissions in a specific, prioritized order.

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
    IF NOT v_has_permission THEN
         RAISE EXCEPTION '%',
            jsonb_build_object('code', 4030, 'message', 'Permission denied. You do not have the required privileges to reset this user''s password.')::text;
    END IF;


    -- =================================================================
    -- 4. PASSWORD UPDATE
    -- =================================================================
    v_encrypted_pw := crypt(p_password, gen_salt('bf'));

    UPDATE auth.users
    SET encrypted_password = v_encrypted_pw
    WHERE auth.users.id = p_user_id;

    -- =================================================================
    -- 5. SUCCESS RESPONSE
    -- =================================================================
    RETURN jsonb_build_object('code', 200, 'message', 'Password has been successfully updated.');

EXCEPTION
    WHEN OTHERS THEN
        RETURN CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::jsonb
            ELSE jsonb_build_object('code', 5000, 'message', SQLERRM)
        END;
END;
$$;
