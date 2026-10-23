-- External role-named RPC retained for previously shipped clients and SQL
-- integrations. Remove only after that public contract is explicitly retired.
-- All operation callers use can_read_orders; this adapter owns no policy.
CREATE OR REPLACE FUNCTION public.get_is_editor_order_view_on_occasion(oc bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.can_read_orders(oc);
$$;
REVOKE ALL ON FUNCTION public.get_is_editor_order_view_on_occasion(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_is_editor_order_view_on_occasion(bigint) TO anon,authenticated,service_role;
