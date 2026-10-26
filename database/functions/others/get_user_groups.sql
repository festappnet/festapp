DROP FUNCTION IF EXISTS public.get_user_groups(BIGINT);

CREATE OR REPLACE FUNCTION public.get_user_groups(p_occasion_id BIGINT)
RETURNS JSONB
SET search_path = public, extensions AS $$
DECLARE
    -- Retrieve the user ID from the authentication context
    current_user_id UUID := auth.uid();
BEGIN
 RETURN public.get_user_groups_for_context_internal_v1(p_occasion_id,
   public.get_is_editor_on_occasion(p_occasion_id),public.get_is_editor_view_on_occasion(p_occasion_id),
   NOT public.is_demo_occasion(p_occasion_id));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
