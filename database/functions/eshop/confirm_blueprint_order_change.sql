CREATE OR REPLACE FUNCTION public.confirm_blueprint_order_change_internal_v1(p_spot_ids bigint[],p_input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE analysis jsonb;details jsonb;tickets bigint[];occ bigint;
BEGIN
 PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.spots WHERE id=ANY(p_spot_ids)));
 PERFORM public.check_blueprint_selection_units_internal(p_spot_ids);
 SELECT occasion INTO occ FROM eshop.spots WHERE id=p_spot_ids[1];
 IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.check_occasion_writable(occ);
 IF EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(p_spot_ids) AND secret IS NOT NULL
  AND secret_expiration_time>clock_timestamp() AND secret IS DISTINCT FROM (p_input_data->>'secret')::uuid) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_SEAT_PROTECTED'; END IF;
 analysis:=public.analyze_new_order_spots(p_spot_ids);
 details:=public.blueprint_order_input_internal(p_spot_ids,p_input_data,analysis);
 IF p_input_data->>'payment_method'='stripe' OR EXISTS(
  SELECT 1 FROM eshop.spots s JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket
  JOIN eshop.orders o ON o.id=i."order" JOIN eshop.payment_info p ON p.id=o.payment_info
  WHERE s.id=ANY(p_spot_ids) AND p.payment_method='stripe') THEN RAISE EXCEPTION 'STRIPE_REPLACEMENT_UNSUPPORTED'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT x."order" FROM eshop.spots s
  JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE s.id=ANY(p_spot_ids)));
 PERFORM 1 FROM eshop.spots WHERE id=ANY(p_spot_ids) ORDER BY id FOR UPDATE;
 PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY(SELECT x.ticket FROM eshop.spots s
  JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE s.id=ANY(p_spot_ids)));
 SELECT array_agg((e->>'ticket_id')::bigint) INTO tickets FROM jsonb_array_elements(analysis->'conflicts') e
 WHERE e->>'ticket_id' IS NOT NULL;
 IF coalesce(cardinality(tickets),0)>0 THEN PERFORM public.storno_tickets_bulk_internal_v1(tickets); END IF;
 UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL WHERE id=ANY(p_spot_ids);
 IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 RETURN jsonb_build_object('success',true,'message','Storno performed. Ready to create new order.','orderDetails',details);
EXCEPTION WHEN OTHERS THEN
 RETURN jsonb_build_object('success',false,'message',SQLERRM);
END $$;
REVOKE ALL ON FUNCTION public.confirm_blueprint_order_change_internal_v1(bigint[],jsonb) FROM PUBLIC,anon,authenticated,service_role;
