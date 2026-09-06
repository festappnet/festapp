-- Correct the caller-side restriction from the preceding migration. Knowing
-- the occasion scan code remains sufficient to invoke this support workflow;
-- the protected boundary is the privilege level of the target account.
DROP FUNCTION IF EXISTS public.check_is_scan_password_reset_authorized(bigint);

CREATE OR REPLACE FUNCTION public.check_is_scan_password_reset_target_allowed(
    p_target_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    IF p_target_user_id IS NULL OR EXISTS (
        SELECT 1
          FROM public.organization_users org_u
         WHERE org_u."user" = p_target_user_id
           AND org_u.is_admin IS TRUE
    ) OR EXISTS (
        SELECT 1
          FROM public.unit_users uu
         WHERE uu."user" = p_target_user_id
           AND (
               uu.is_manager IS TRUE
               OR uu.is_editor IS TRUE
               OR uu.is_editor_view IS TRUE
           )
    ) OR EXISTS (
        SELECT 1
          FROM public.occasion_users ou
         WHERE ou."user" = p_target_user_id
           AND (
               ou.is_manager IS TRUE
               OR ou.is_editor IS TRUE
               OR ou.is_editor_view IS TRUE
               OR ou.is_editor_order IS TRUE
               OR ou.is_editor_order_view IS TRUE
               OR ou.is_approver IS TRUE
               OR coalesce(
                   (to_jsonb(ou)->>'is_cleaning_crew')::boolean,
                   false
               )
               OR coalesce(
                   (to_jsonb(ou)->>'is_receptionist')::boolean,
                   false
               )
           )
    ) OR EXISTS (
        SELECT 1
          FROM public.user_groups ug
         WHERE ug."user" = p_target_user_id
           AND ug.is_admin IS TRUE
    ) THEN
        RAISE EXCEPTION 'Privileged users cannot have their password reset via scan.'
          USING ERRCODE = '42501';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.check_is_scan_password_reset_target_allowed(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_is_scan_password_reset_target_allowed(uuid)
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
