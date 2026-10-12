-- Auth metadata is visible only to the identity or an administrator of its real scope.
CREATE OR REPLACE FUNCTION public.get_can_view_user_auth(p_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
    SELECT public.is_service_role() OR (
        auth.uid() IS NOT NULL AND (
            auth.uid() = p_user_id
            OR EXISTS (
                SELECT 1 FROM public.user_info target
                JOIN public.organization_users actor ON actor.organization = target.organization
                WHERE target.id = p_user_id AND actor."user" = auth.uid() AND actor.is_admin IS TRUE
            )
            OR EXISTS (
                SELECT 1 FROM public.unit_users target
                JOIN public.unit_users actor ON actor.unit = target.unit
                WHERE target."user" = p_user_id AND actor."user" = auth.uid()
                  AND (actor.is_manager IS TRUE OR actor.is_editor IS TRUE OR actor.is_editor_view IS TRUE)
            )
            OR EXISTS (
                SELECT 1 FROM public.occasion_users target
                JOIN public.occasion_users actor ON actor.occasion = target.occasion
                WHERE target."user" = p_user_id AND actor."user" = auth.uid()
                  AND (actor.is_manager IS TRUE OR actor.is_editor IS TRUE OR actor.is_editor_view IS TRUE)
            )
        )
    );
$$;
REVOKE ALL ON FUNCTION public.get_can_view_user_auth(uuid) FROM PUBLIC, anon, authenticated;
