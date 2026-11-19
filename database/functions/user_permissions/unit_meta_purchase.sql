CREATE OR REPLACE FUNCTION public.can_manage_unit_meta_purchase(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND NOT public.is_demo_unit(p_unit) AND coalesce((SELECT
 public.can_manage_organization_settings(u.organization) FROM public.units u WHERE u.id=p_unit),false);
$$;
REVOKE ALL ON FUNCTION public.can_manage_unit_meta_purchase(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_unit_meta_purchase(bigint) TO authenticated;

