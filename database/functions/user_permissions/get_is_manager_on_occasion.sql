CREATE OR REPLACE FUNCTION public.get_is_manager_on_occasion(oc bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
 SELECT public.active_membership(
   (SELECT m.is_manager FROM public.occasion_users m WHERE m."user"=auth.uid() AND m.occasion=oc),
   public.is_demo_occasion(oc));
$$;
REVOKE ALL ON FUNCTION public.get_is_manager_on_occasion(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_is_manager_on_occasion(bigint) TO anon,authenticated,service_role;
