-- Temporary owner-only residual repair; contract removes this function.
CREATE OR REPLACE FUNCTION public.backfill_order_sequences(p_occasion bigint)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE candidate bigint; item record; repaired bigint := 0;
BEGIN
 candidate := public.next_order_sequence(p_occasion);
 FOR item IN SELECT id FROM eshop.orders WHERE occasion=p_occasion AND order_sequence IS NULL ORDER BY created_at,id FOR UPDATE LOOP
  UPDATE eshop.orders SET order_sequence=candidate WHERE id=item.id;
  candidate := candidate + 1;
  repaired := repaired + 1;
 END LOOP;
 RETURN repaired;
END;
$$;
ALTER FUNCTION public.backfill_order_sequences(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.backfill_order_sequences(bigint) FROM PUBLIC, anon, authenticated, service_role;
