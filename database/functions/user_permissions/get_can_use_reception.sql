CREATE OR REPLACE FUNCTION public.get_can_use_reception(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.reception_use_rule(coalesce((SELECT public.reception_enabled(o.features)
    FROM public.occasions o WHERE o.id=p_occasion),false),
    public.get_is_receptionist_on_occasion(p_occasion),
    public.get_is_manager_on_occasion(p_occasion),public.get_is_admin_on_occasion(p_occasion));
$$;

REVOKE ALL ON FUNCTION public.get_can_use_reception(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_can_use_reception(bigint) TO authenticated, service_role;
