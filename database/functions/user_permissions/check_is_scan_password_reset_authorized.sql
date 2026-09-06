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
