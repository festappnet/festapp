-- Private read boundary. RPC execution is service-only; owners may call it from
-- already authorized command facades. Invoker RLS/privileges remain in force.
CREATE OR REPLACE FUNCTION public.read_order_identity(p_order bigint, p_occasion bigint, p_organization bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = public, extensions AS $$
BEGIN
    RETURN (SELECT o.order_symbol FROM eshop.orders o
        JOIN public.occasions oc ON oc.id=o.occasion
        WHERE o.id=p_order AND o.occasion=p_occasion AND oc.organization=p_organization);
END;
$$;
ALTER FUNCTION public.read_order_identity(bigint,bigint,bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.read_order_identity(bigint,bigint,bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_order_identity(bigint,bigint,bigint) TO service_role;
