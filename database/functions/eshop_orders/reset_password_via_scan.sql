CREATE OR REPLACE FUNCTION public.reset_password_via_scan(
    ticket_id bigint,
    password text,
    scan_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id bigint;
    v_expected_scan_code text;
    v_target_user_id uuid;
    v_target_email text;
    v_encrypted_pw text;
    v_has_elevated_privileges boolean;
BEGIN
    -- =================================================================
    -- 1. INPUT VALIDATION
    -- =================================================================
    IF ticket_id IS NULL THEN
         RETURN jsonb_build_object('code', 400, 'message', 'Ticket ID is missing.');
    END IF;

    IF password IS NULL OR trim(password) = '' THEN
         RETURN jsonb_build_object('code', 400, 'message', 'Password cannot be empty.');
    END IF;

    -- =================================================================
    -- 2. VALIDATE TICKET AND SCAN CODE
    -- =================================================================

    -- Get Occasion ID from Ticket
    SELECT occasion INTO v_occasion_id
    FROM eshop.tickets
    WHERE id = ticket_id;

    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Ticket not found or no occasion assigned.');
    END IF;

    -- Get Expected Scan Code (Secret) from Occasions Hidden
    SELECT oh.secret INTO v_expected_scan_code
    FROM public.occasions_hidden oh
    JOIN public.occasions o ON o.occasion_hidden = oh.id
    WHERE o.id = v_occasion_id
    LIMIT 1;

    IF v_expected_scan_code IS NULL THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Scan code not defined for this occasion.');
    END IF;

    -- Verify Code Matches
    IF scan_code != v_expected_scan_code THEN
        RETURN jsonb_build_object('code', 401, 'message', 'Invalid scan code.');
    END IF;

    -- The shared scan code alone is not an account-recovery credential.
    BEGIN
        PERFORM public.check_is_scan_password_reset_authorized(v_occasion_id);
    EXCEPTION
        WHEN insufficient_privilege THEN
            RETURN jsonb_build_object(
                'code', 403,
                'message', 'Only an editor or manager may reset a password.'
            );
    END;

    -- =================================================================
    -- 3. IDENTIFY TARGET USER
    -- =================================================================

    -- Find the user attached to this ticket via occasion_users
    SELECT "user" INTO v_target_user_id
    FROM public.occasion_users
    WHERE ticket = ticket_id;

    IF v_target_user_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'No user found associated with this ticket.');
    END IF;

    -- =================================================================
    -- 4. SECURITY CHECK: PREVENT RESET FOR PRIVILEGED USERS
    -- =================================================================
    v_has_elevated_privileges := FALSE;

    -- Check 4a: Is Organization Admin?
    SELECT EXISTS (
        SELECT 1 FROM public.organization_users
        WHERE "user" = v_target_user_id AND is_admin = TRUE
    ) INTO v_has_elevated_privileges;

    -- Check 4b: Is Unit Manager/Editor?
    IF NOT v_has_elevated_privileges THEN
        SELECT EXISTS (
            SELECT 1 FROM public.unit_users
            WHERE "user" = v_target_user_id
            AND (is_manager = TRUE OR is_editor = TRUE OR is_editor_view = TRUE)
        ) INTO v_has_elevated_privileges;
    END IF;

    -- Check 4c: Is Occasion Manager/Editor?
    IF NOT v_has_elevated_privileges THEN
        SELECT EXISTS (
            SELECT 1 FROM public.occasion_users
            WHERE "user" = v_target_user_id
            AND (is_manager = TRUE OR is_editor = TRUE OR is_editor_view = TRUE)
        ) INTO v_has_elevated_privileges;
    END IF;

    IF v_has_elevated_privileges THEN
        RETURN jsonb_build_object('code', 403, 'message', 'Security Restriction: Cannot reset password for users with administrative or management privileges via scan.');
    END IF;

    -- =================================================================
    -- 5. PERFORM PASSWORD RESET
    -- =================================================================

    -- Generate encrypted password
    v_encrypted_pw := crypt(password, gen_salt('bf'));

    -- Update auth.users
    UPDATE auth.users
    SET encrypted_password = v_encrypted_pw
    WHERE id = v_target_user_id
    RETURNING email INTO v_target_email;

    IF v_target_email IS NULL THEN
         -- Fallback if email wasn't returned (unlikely if ID exists)
         RETURN jsonb_build_object('code', 500, 'message', 'Password updated, but failed to retrieve email.');
    END IF;

    -- =================================================================
    -- 6. SUCCESS RESPONSE
    -- =================================================================
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Password successfully reset.',
        'email', v_target_email
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'code', 500,
            'message', 'An unexpected error occurred.',
            'detail', SQLERRM
        );
END;
$$;

REVOKE ALL ON FUNCTION public.reset_password_via_scan(bigint, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reset_password_via_scan(bigint, text, text)
  TO authenticated, service_role;
