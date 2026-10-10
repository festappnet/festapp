-- Domain commands authorize callers before invoking these private guards.
-- Lock the order through the write so cancellation cannot race with an edit.
CREATE OR REPLACE FUNCTION public.check_order_is_mutable(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE v_state text;
BEGIN
  SELECT state INTO v_state FROM eshop.orders WHERE id=p_order FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  IF v_state='storno' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED: Cancelled orders are read-only' USING ERRCODE='55000';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.check_ticket_is_mutable(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE v_order bigint; v_state text;
BEGIN
  FOR v_order IN SELECT DISTINCT opt."order" FROM eshop.order_product_ticket opt
    WHERE opt.ticket=p_ticket ORDER BY opt."order" LOOP
    PERFORM public.check_order_is_mutable(v_order);
  END LOOP;
  SELECT state INTO v_state FROM eshop.tickets WHERE id=p_ticket FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'TICKET_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  IF v_state='storno' THEN
    RAISE EXCEPTION 'TICKET_CANCELLED: Cancelled tickets are read-only' USING ERRCODE='55000';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.check_payment_info_is_mutable(p_payment bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE v_order bigint;
BEGIN
  FOR v_order IN SELECT id FROM eshop.orders WHERE payment_info=p_payment ORDER BY id LOOP
    PERFORM public.check_order_is_mutable(v_order);
  END LOOP;
END $$;

REVOKE ALL ON FUNCTION public.check_order_is_mutable(bigint),
  public.check_ticket_is_mutable(bigint),public.check_payment_info_is_mutable(bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.check_order_is_mutable(bigint),
  public.check_ticket_is_mutable(bigint),public.check_payment_info_is_mutable(bigint)
  TO service_role;
