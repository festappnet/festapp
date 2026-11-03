CREATE OR REPLACE FUNCTION public.get_is_receptionist_on_occasion(oc bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT COALESCE((SELECT ou.is_receptionist
    FROM public.occasion_users ou
    WHERE ou."user"=auth.uid() AND ou.occasion=oc),false);
$$;

REVOKE ALL ON FUNCTION public.get_is_receptionist_on_occasion(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_is_receptionist_on_occasion(bigint) TO authenticated, service_role;
