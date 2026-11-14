CREATE OR REPLACE FUNCTION public.can_manage_webhooks(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.can_read_orders(p_occasion) AND public.can_write_orders(p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_manage_webhooks(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_manage_webhooks(bigint) TO authenticated;

