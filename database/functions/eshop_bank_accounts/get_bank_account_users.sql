-- Removing the historical default requires recreation; preserve both exact signatures.
DROP FUNCTION IF EXISTS public.get_bank_account_users(bigint, bigint);

CREATE OR REPLACE FUNCTION public.get_bank_account_users(
    p_bank_account_id bigint,
    p_unit_id bigint
)
RETURNS TABLE (
    user_id uuid,
    email text,
    name text,
    surname text,
    is_admin boolean,
    is_support boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_org_id bigint;
BEGIN
    -- A unit context is meaningful only for an actual account link.
    IF p_unit_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM eshop.unit_bank_accounts link
        WHERE link.unit = p_unit_id AND link.bank_account = p_bank_account_id
    ) THEN
        RAISE insufficient_privilege USING MESSAGE = 'Bank account is not linked to this unit';
    END IF;
    IF NOT public.is_service_role() AND NOT (
        EXISTS (
            SELECT 1 FROM eshop.bank_account_users actor
            WHERE actor.bank_account = p_bank_account_id AND actor."user" = auth.uid()
              AND (actor.is_admin IS TRUE OR actor.is_support IS TRUE)
        ) OR (p_unit_id IS NOT NULL AND public.get_is_manager_on_unit(p_unit_id) IS TRUE)
    ) THEN
        RAISE insufficient_privilege USING MESSAGE = 'Bank account access denied';
    END IF;
    -- If unit context is provided, find the organization
    IF p_unit_id IS NOT NULL THEN
        SELECT organization INTO v_org_id FROM public.units WHERE id = p_unit_id;
    END IF;

    RETURN QUERY
    SELECT
        u.id,
        u.email_readonly,
        u.name,
        u.surname,
        bau.is_admin,
        bau.is_support
    FROM eshop.bank_account_users bau
    JOIN public.user_info u ON bau."user" = u.id
    LEFT JOIN public.organization_users ou ON u.id = ou."user" AND (v_org_id IS NULL OR ou.organization = v_org_id)
    WHERE bau.bank_account = p_bank_account_id
      AND (v_org_id IS NULL OR ou.is_hidden IS NOT TRUE);
END;
$$;

-- Preserve the historical overload without an ambiguous default argument.
CREATE OR REPLACE FUNCTION public.get_bank_account_users(p_bank_account_id bigint)
RETURNS TABLE (user_id uuid, email text, name text, surname text, is_admin boolean, is_support boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
    SELECT * FROM public.get_bank_account_users(p_bank_account_id, NULL::bigint);
$$;
REVOKE ALL ON FUNCTION public.get_bank_account_users(bigint, bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_bank_account_users(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_bank_account_users(bigint, bigint) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_account_users(bigint) TO authenticated, service_role;
