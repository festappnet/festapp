-- External role-named RPC retained for previously shipped clients and SQL
-- integrations. Remove only after that public contract is explicitly retired.
-- All operation callers use can_write_orders; this adapter owns no policy.
CREATE OR REPLACE FUNCTION public.get_is_editor_order_on_occasion(oc bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.can_write_orders(oc);
$$;
