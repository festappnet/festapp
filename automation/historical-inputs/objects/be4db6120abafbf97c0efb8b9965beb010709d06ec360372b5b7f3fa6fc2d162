-- PostgreSQL comparisons with NULL do not evaluate to TRUE. Use a NULL-safe
-- comparison so an anonymous caller cannot bypass the shared scan-code check.
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
BEGIN
    IF ticket_id IS NULL THEN
         RETURN jsonb_build_object('code', 400, 'message', 'Ticket ID is missing.');
    END IF;

    IF password IS NULL OR trim(password) = '' THEN
         RETURN jsonb_build_object('code', 400, 'message', 'Password cannot be empty.');
    END IF;

    SELECT occasion INTO v_occasion_id
    FROM eshop.tickets
    WHERE id = ticket_id;

    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Ticket not found or no occasion assigned.');
    END IF;

    SELECT oh.secret INTO v_expected_scan_code
    FROM public.occasions_hidden oh
    JOIN public.occasions o ON o.occasion_hidden = oh.id
    WHERE o.id = v_occasion_id
    LIMIT 1;

    IF v_expected_scan_code IS NULL THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Scan code not defined for this occasion.');
    END IF;

    IF scan_code IS DISTINCT FROM v_expected_scan_code THEN
        RETURN jsonb_build_object('code', 401, 'message', 'Invalid scan code.');
    END IF;

    SELECT "user" INTO v_target_user_id
    FROM public.occasion_users
    WHERE ticket = ticket_id;

    IF v_target_user_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'No user found associated with this ticket.');
    END IF;

    BEGIN
        PERFORM public.check_is_scan_password_reset_target_allowed(
            v_target_user_id
        );
    EXCEPTION
        WHEN insufficient_privilege THEN
            RETURN jsonb_build_object(
                'code', 403,
                'message', 'Security Restriction: Cannot reset password for privileged users via scan.'
            );
    END;

    v_encrypted_pw := crypt(password, gen_salt('bf'));

    UPDATE auth.users
    SET encrypted_password = v_encrypted_pw
    WHERE id = v_target_user_id
    RETURNING email INTO v_target_email;

    IF v_target_email IS NULL THEN
         RETURN jsonb_build_object('code', 500, 'message', 'Password updated, but failed to retrieve email.');
    END IF;

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
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reset_password_via_scan(bigint, text, text)
  TO anon, authenticated, service_role;
