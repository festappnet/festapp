-- Private invariant owners. Callers authorize and hold existing domain locks.
CREATE OR REPLACE FUNCTION public.check_batch_ticket_print_immutable_internal(p_tickets bigint[])
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM eshop.ticket_batch_items i JOIN eshop.tickets t ON t.id=i.ticket_id
 WHERE i.ticket_id=ANY(p_tickets) AND t.state<>'storno') THEN
  RAISE EXCEPTION 'BATCH_TICKET_PRINT_IMMUTABLE' USING ERRCODE='55000'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.check_batch_product_allocation_immutable_internal(p_products bigint[])
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY(
  SELECT DISTINCT ticket FROM eshop.order_product_ticket WHERE product=ANY(p_products)));
END $$;
CREATE OR REPLACE FUNCTION public.check_batch_order_delete_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM eshop.ticket_batches WHERE stock_order_id=p_order)
 OR EXISTS(SELECT 1 FROM eshop.ticket_batch_items WHERE sale_order_id=p_order) THEN
  RAISE EXCEPTION 'BATCH_ORDER_HISTORY_REQUIRED' USING ERRCODE='55000'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_batch_ticket_print_immutable_internal(bigint[]),
 public.check_batch_product_allocation_immutable_internal(bigint[]),public.check_batch_order_delete_internal(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
-- Admin batch creation acquires all selected holds atomically under the existing
-- form/product locks. It does not raise the public buyer's hold limit of 20.
CREATE OR REPLACE FUNCTION public.hold_ticket_batch_spots_internal(p_form bigint,p_spots bigint[],p_secret uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms;
BEGIN
 IF cardinality(p_spots)=0 THEN RETURN; END IF;
 IF p_secret IS NULL OR cardinality(p_spots)>200 THEN RAISE EXCEPTION 'BATCH_SPOT_HOLD_REQUIRED'; END IF;
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form;
 PERFORM 1 FROM eshop.spots WHERE id=ANY(p_spots) ORDER BY id FOR UPDATE;
 IF (SELECT count(*) FROM eshop.spots WHERE id=ANY(p_spots) AND blueprint=f.blueprint AND occasion=f.occasion
  AND order_product_ticket IS NULL AND (secret IS NULL OR secret=p_secret OR secret_expiration_time<=clock_timestamp()))<>cardinality(p_spots) THEN
  RAISE EXCEPTION 'BATCH_SPOT_UNAVAILABLE'; END IF;
 UPDATE eshop.spots SET secret=p_secret,secret_expiration_time=clock_timestamp()+interval '2 minutes'
 WHERE id=ANY(p_spots) AND (secret IS DISTINCT FROM p_secret OR secret_expiration_time<=clock_timestamp());
END $$;
REVOKE ALL ON FUNCTION public.hold_ticket_batch_spots_internal(bigint,bigint[],uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.check_batch_blueprint_print_immutable_internal(p_blueprint bigint,p_input jsonb)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings binding JOIN eshop.blueprints b ON b.id=binding.blueprint
 JOIN eshop.spots s ON s.id=binding.spot JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket
 JOIN eshop.ticket_batch_items i ON i.ticket_id=x.ticket JOIN eshop.tickets t ON t.id=i.ticket_id
 WHERE b.id=p_blueprint AND t.state<>'storno' AND
 (SELECT n->>'label' FROM jsonb_array_elements(b.layout->'nodes') n WHERE n->>'id'=binding.group_node::text)
 IS DISTINCT FROM
 (SELECT n->>'label' FROM jsonb_array_elements(p_input->'nodes') n WHERE n->>'id'=binding.group_node::text)) THEN
  RAISE EXCEPTION 'BATCH_TICKET_PRINT_IMMUTABLE' USING ERRCODE='55000'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_batch_blueprint_print_immutable_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
