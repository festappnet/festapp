-- Temporary owner-only migration function, removed by the contract migration.
CREATE OR REPLACE FUNCTION public.backfill_order_symbols(p_ids bigint[])
RETURNS TABLE(order_id bigint, order_symbol text)
LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_id bigint; v_symbol text; v_constraint text; v_done boolean;
BEGIN
    FOREACH v_id IN ARRAY p_ids LOOP
        PERFORM 1 FROM eshop.orders o WHERE o.id=v_id AND o.order_symbol IS NULL FOR UPDATE;
        IF NOT FOUND THEN CONTINUE; END IF;
        v_done := false;
        FOR attempt IN 1..10 LOOP
            BEGIN
                v_symbol := public.generate_order_symbol();
                UPDATE eshop.orders o SET order_symbol=v_symbol WHERE o.id=v_id AND o.order_symbol IS NULL;
                v_done := true;
                EXIT;
            EXCEPTION WHEN unique_violation THEN
                GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
                IF v_constraint <> 'orders_order_symbol_key' THEN RAISE; END IF;
                RAISE LOG 'order_symbol_backfill_collision attempt=%', attempt;
            END;
        END LOOP;
        IF NOT v_done THEN RAISE EXCEPTION 'order_symbol_backfill_exhausted'; END IF;
        order_id := v_id; order_symbol := v_symbol; RETURN NEXT;
    END LOOP;
END;
$$;
ALTER FUNCTION public.backfill_order_symbols(bigint[]) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.backfill_order_symbols(bigint[]) FROM PUBLIC, anon, authenticated, service_role;
