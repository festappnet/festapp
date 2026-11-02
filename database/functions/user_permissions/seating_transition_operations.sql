CREATE OR REPLACE FUNCTION public.can_read_seating_status(p_occasion bigint)
RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce(public.can_author_forms(p_occasion) OR public.can_read_orders(p_occasion),false)
$$;
CREATE OR REPLACE FUNCTION public.can_assign_existing_admissions(p_occasion bigint)
RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND coalesce(public.can_read_orders(p_occasion) AND public.can_write_orders(p_occasion),false)
$$;
REVOKE ALL ON FUNCTION public.can_read_seating_status(bigint),public.can_assign_existing_admissions(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_seating_status(bigint),public.can_assign_existing_admissions(bigint) TO authenticated,service_role;
