CREATE OR REPLACE FUNCTION public.check_is_scan_password_reset_authorized(
    p_occasion_id bigint
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    IF auth.role() IS NOT DISTINCT FROM 'service_role' THEN
        RETURN;
    END IF;

    IF auth.uid() IS NULL OR NOT EXISTS (
        SELECT 1
          FROM public.occasions o
         WHERE o.id = p_occasion_id
           AND (
               EXISTS (
                   SELECT 1
                     FROM public.occasion_users ou
                    WHERE ou.occasion = o.id
                      AND ou."user" = auth.uid()
                      AND (ou.is_editor IS TRUE OR ou.is_manager IS TRUE)
               )
               OR EXISTS (
                   SELECT 1
                     FROM public.unit_users uu
                    WHERE uu.unit = o.unit
                      AND uu."user" = auth.uid()
                      AND (uu.is_editor IS TRUE OR uu.is_manager IS TRUE)
               )
               OR EXISTS (
                   SELECT 1
                     FROM public.organization_users org_u
                    WHERE org_u.organization = o.organization
                      AND org_u."user" = auth.uid()
                      AND org_u.is_admin IS TRUE
               )
           )
    ) THEN
        RAISE EXCEPTION 'Only an editor or manager may reset a password.'
          USING ERRCODE = '42501';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.check_is_scan_password_reset_authorized(bigint)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_is_scan_password_reset_authorized(bigint)
  TO service_role;

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

    IF scan_code != v_expected_scan_code THEN
        RETURN jsonb_build_object('code', 401, 'message', 'Invalid scan code.');
    END IF;

    BEGIN
        PERFORM public.check_is_scan_password_reset_authorized(v_occasion_id);
    EXCEPTION
        WHEN insufficient_privilege THEN
            RETURN jsonb_build_object(
                'code', 403,
                'message', 'Only an editor or manager may reset a password.'
            );
    END;

    SELECT "user" INTO v_target_user_id
    FROM public.occasion_users
    WHERE ticket = ticket_id;

    IF v_target_user_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'No user found associated with this ticket.');
    END IF;

    v_has_elevated_privileges := FALSE;

    SELECT EXISTS (
        SELECT 1 FROM public.organization_users
        WHERE "user" = v_target_user_id AND is_admin = TRUE
    ) INTO v_has_elevated_privileges;

    IF NOT v_has_elevated_privileges THEN
        SELECT EXISTS (
            SELECT 1 FROM public.unit_users
            WHERE "user" = v_target_user_id
            AND (is_manager = TRUE OR is_editor = TRUE OR is_editor_view = TRUE)
        ) INTO v_has_elevated_privileges;
    END IF;

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
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reset_password_via_scan(bigint, text, text)
  TO authenticated, service_role;
