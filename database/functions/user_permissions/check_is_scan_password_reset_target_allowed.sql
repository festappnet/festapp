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
