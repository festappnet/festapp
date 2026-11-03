-- Private allocator: the lock and MAX must use separate statement snapshots.
CREATE OR REPLACE FUNCTION public.next_order_sequence(p_occasion bigint)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE candidate bigint;
BEGIN
 IF p_occasion IS NULL THEN RAISE EXCEPTION 'order_sequence requires occasion'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('festapp:order-sequence:' || p_occasion::text, 0));
 SELECT COALESCE(MAX(order_sequence), 0) + 1 INTO candidate FROM eshop.orders WHERE occasion=p_occasion;
 RETURN candidate;
END;
$$;
ALTER FUNCTION public.next_order_sequence(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.next_order_sequence(bigint) FROM PUBLIC, anon, authenticated, service_role;
