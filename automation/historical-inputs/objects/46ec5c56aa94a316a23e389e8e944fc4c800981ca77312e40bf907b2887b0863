CREATE OR REPLACE FUNCTION public.allocate_user_sign_in_email(
    p_organization bigint,
    p_delivery_email text
)
RETURNS text
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_delivery_email text := lower(btrim(p_delivery_email));
    v_local_part text;
    v_domain_part text;
    v_candidate text;
    v_suffix integer := 0;
BEGIN
    IF v_delivery_email IS NULL OR v_delivery_email = ''
       OR position('@' IN v_delivery_email) <= 1 THEN
        RAISE EXCEPTION 'INVALID_DELIVERY_EMAIL';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'user-sign-in-email:' || p_organization::text, 0
        )
    );

    v_local_part := split_part(v_delivery_email, '@', 1);
    v_domain_part := substring(v_delivery_email FROM position('@' IN v_delivery_email) + 1);

    LOOP
        v_candidate := CASE WHEN v_suffix = 0 THEN v_delivery_email
            ELSE v_local_part || '+' || v_suffix::text || '@' || v_domain_part END;
        EXIT WHEN NOT EXISTS (
            SELECT 1 FROM public.user_info ui
             WHERE ui.organization = p_organization
               AND lower(btrim(ui.email_readonly)) = v_candidate
        );
        v_suffix := v_suffix + 1;
    END LOOP;

    RETURN v_candidate;
END;
$$;

REVOKE ALL ON FUNCTION public.allocate_user_sign_in_email(bigint, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.allocate_user_sign_in_email(bigint, text) FROM anon;
REVOKE ALL ON FUNCTION public.allocate_user_sign_in_email(bigint, text) FROM authenticated;
REVOKE ALL ON FUNCTION public.allocate_user_sign_in_email(bigint, text) FROM service_role;
