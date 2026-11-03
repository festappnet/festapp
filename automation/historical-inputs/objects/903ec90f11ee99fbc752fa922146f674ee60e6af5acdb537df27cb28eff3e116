CREATE OR REPLACE FUNCTION public.get_can_use_reception(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.occasions o
    WHERE o.id=p_occasion
      AND jsonb_path_exists(COALESCE(o.features,'[]'::jsonb),
        '$[*] ? (@.code == "reception" && @.is_enabled == true)')
  ) AND (
    public.get_is_receptionist_on_occasion(p_occasion)
    OR public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)
  );
$$;

REVOKE ALL ON FUNCTION public.get_can_use_reception(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_can_use_reception(bigint) TO authenticated, service_role;
