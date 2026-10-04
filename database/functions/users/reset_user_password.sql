CREATE OR REPLACE FUNCTION reset_user_password(p_user_id uuid, p_password text)
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

    IF NOT public.get_can_reset_user_password(p_user_id) THEN
        RAISE EXCEPTION '%',jsonb_build_object('code',4030,'message','Permission denied. You do not have the required privileges to reset this user''s password.')::text;
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
