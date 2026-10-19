-- SQL work is deliberately rolled back after capturing the authoritative result.
-- The existing financial owner is executed; preview maintains no alternate maths.
CREATE OR REPLACE FUNCTION public.preview_blueprint_swap(p_spot_1 bigint,p_spot_2 bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ids bigint[]; order_ids bigint[]; before_orders jsonb; sides jsonb; result jsonb; occ bigint;
BEGIN
 SELECT min(occasion) INTO occ FROM eshop.spots WHERE id IN(p_spot_1,p_spot_2);
 IF occ IS NULL THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 IF public.get_is_editor_order_on_occasion(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 ids:=public.blueprint_selection_unit_spots_internal(p_spot_1)||public.blueprint_selection_unit_spots_internal(p_spot_2);
 SELECT array_agg(DISTINCT opt."order") INTO order_ids FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket WHERE s.id=ANY(ids);
 PERFORM public.lock_order_capacity_scope_internal(order_ids);
 SELECT coalesce(jsonb_object_agg(id::text,price),'{}') INTO before_orders FROM eshop.orders WHERE id=ANY(order_ids);
 SELECT coalesce(jsonb_agg(jsonb_build_object('spotId',s.id,'title',s.title,'orderId',o.id,'ticketId',opt.ticket,
  'customer',jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email')) ORDER BY s.id),'[]')
 INTO sides FROM eshop.spots s LEFT JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket LEFT JOIN eshop.orders o ON o.id=opt."order" WHERE s.id=ANY(ids);
 BEGIN
  PERFORM public.swap_spot_tickets_internal_v1(p_spot_1,p_spot_2);
  SELECT jsonb_build_object('code',200,'spotIds',to_jsonb(ids),'sides',sides,'orders',coalesce(jsonb_agg(jsonb_build_object(
   'orderId',id,'beforeAmount',(before_orders->>id::text)::numeric,'afterAmount',price,
   'delta',price-(before_orders->>id::text)::numeric,'currencyCode',currency_code) ORDER BY id),'[]')) INTO result FROM eshop.orders WHERE id=ANY(order_ids);
  RAISE SQLSTATE 'BP001' USING MESSAGE='rollback successful swap preview';
 EXCEPTION WHEN SQLSTATE 'BP001' THEN NULL;
 WHEN OTHERS THEN result:=jsonb_build_object('code',409,'reason',SQLERRM,'issues',jsonb_build_array(jsonb_build_object('reason',SQLERRM)));
 END;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.preview_blueprint_swap(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.preview_blueprint_swap(bigint,bigint) TO authenticated;
