CREATE OR REPLACE FUNCTION public.can_read_sale_opening_subscribers(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce(public.can_read_participant_contacts(p_occasion),false);
$$;
REVOKE ALL ON FUNCTION public.can_read_sale_opening_subscribers(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_sale_opening_subscribers(bigint) TO authenticated,service_role;
