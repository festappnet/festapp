-- The unversioned historical JSON facades previously retained an old separate
-- cancellation implementation. Keep their result shape, route through the same
-- authorized receipt-bearing domain command as the current _221 facade.
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_storno(order_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.storno_order_client_sync_v1(order_id,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',200,'message','Order and all associated tickets successfully cancelled',
  'order_id',order_id,'tickets_updated',(SELECT jsonb_agg(ticket) FROM eshop.order_product_ticket WHERE "order"=order_id));
END $$;
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_storno_ws(order_id bigint)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.update_order_and_tickets_to_storno(order_id);
$$;
REVOKE ALL ON FUNCTION public.update_order_and_tickets_to_storno(bigint),public.update_order_and_tickets_to_storno_ws(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_order_and_tickets_to_storno(bigint),public.update_order_and_tickets_to_storno_ws(bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.storno_tickets_bulk_internal_v1(bigint[]),public.update_order_and_tickets_to_storno_ws_internal_v1(bigint),public.delete_order_internal_v1(bigint) FROM service_role;
