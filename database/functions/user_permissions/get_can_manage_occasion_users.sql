CREATE OR REPLACE FUNCTION public.get_can_manage_occasion_users(
    p_occasion_id bigint
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_unit_id bigint;
BEGIN
    SELECT o.unit
      INTO v_unit_id
      FROM public.occasions o
     WHERE o.id = p_occasion_id;

    IF NOT FOUND OR auth.uid() IS NULL THEN
        RETURN false;
    END IF;

    RETURN public.get_is_manager_on_occasion(p_occasion_id)
        OR public.get_is_admin_on_occasion(p_occasion_id)
        OR (
            v_unit_id IS NOT NULL
            AND public.get_is_editor_on_unit(v_unit_id)
        );
END;
$$;

REVOKE ALL ON FUNCTION public.get_can_manage_occasion_users(bigint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_can_manage_occasion_users(bigint)
  TO authenticated;
