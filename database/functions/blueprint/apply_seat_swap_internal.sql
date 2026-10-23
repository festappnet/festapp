-- Validate only entities actually participating in this swap before locking
-- their parents, then again once the complete assignment closure is locked.
CREATE OR REPLACE FUNCTION public.check_blueprint_swap_scope_internal(p_occasion bigint,p_spots bigint[])
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF (SELECT count(*) FROM eshop.spots WHERE id=ANY(p_spots) AND occasion=p_occasion)<>cardinality(p_spots)
  OR EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprints b ON b.id=s.blueprint
   LEFT JOIN eshop.products p ON p.id=s.product LEFT JOIN eshop.product_types pt ON pt.id=p.product_type
   LEFT JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket
   LEFT JOIN eshop.orders o ON o.id=i."order" LEFT JOIN eshop.tickets t ON t.id=i.ticket
   WHERE s.id=ANY(p_spots) AND (
    (s.blueprint IS NOT NULL AND b.occasion IS DISTINCT FROM p_occasion)
    OR (s.product IS NOT NULL AND (p.occasion IS DISTINCT FROM p_occasion OR pt.occasion IS DISTINCT FROM p_occasion))
    OR (s.order_product_ticket IS NOT NULL AND (o.occasion IS DISTINCT FROM p_occasion OR t.occasion IS DISTINCT FROM p_occasion)))) THEN
  RAISE insufficient_privilege USING MESSAGE='swap assignment scope unavailable'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_blueprint_swap_scope_internal(bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- Capture the actual financial owner's effects, never a second price calculation.
-- Preview callers roll this work back; confirmed command callers retain it only
-- when its digest matches the effects previously approved by the operator.
CREATE OR REPLACE FUNCTION public.apply_blueprint_seat_swap_internal(p_first bigint,p_second bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE occ bigint; left_ids bigint[];right_ids bigint[];ids bigint[];v_order_ids bigint[];
 before_orders jsonb;sides jsonb;revisions jsonb;effects jsonb;facts jsonb;result jsonb;i integer;
BEGIN
 SELECT min(occasion) INTO occ FROM eshop.spots WHERE id IN(p_first,p_second);
 IF p_first IS NULL OR p_second IS NULL OR p_first=p_second OR occ IS NULL
  OR (SELECT count(*) FROM eshop.spots WHERE id IN(p_first,p_second) AND occasion=occ)<>2
  OR public.can_write_orders(occ) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.check_occasion_writable(occ);
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 left_ids:=public.blueprint_selection_unit_spots_internal(p_first);
 right_ids:=public.blueprint_selection_unit_spots_internal(p_second);
 IF cardinality(left_ids)<>cardinality(right_ids) OR left_ids && right_ids THEN
  RAISE EXCEPTION 'BLUEPRINT_UNIT_SIZE_MISMATCH'; END IF;
 ids:=left_ids||right_ids;
 PERFORM public.check_blueprint_swap_scope_internal(occ,ids);
 PERFORM public.lock_spot_assignment_scope_internal(ids,'{}'::bigint[],true);
 PERFORM public.check_blueprint_swap_scope_internal(occ,ids);
 -- Ticket rows are locked before rechecking used atomic-unit members.
 PERFORM public.check_blueprint_selection_units_internal(ids);
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'revision',layout_revision) ORDER BY id),'[]')
 INTO revisions FROM eshop.blueprints WHERE id IN(SELECT blueprint FROM eshop.spots WHERE id=ANY(ids));
 SELECT array_agg(DISTINCT i."order") INTO v_order_ids FROM eshop.spots s
 JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket WHERE s.id=ANY(ids);
 IF EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprint_seat_bindings b ON b.spot=s.id
  WHERE s.id=ANY(ids) AND (b.blocked OR s.product IS NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp()))) THEN
  RAISE EXCEPTION 'BLUEPRINT_SEAT_PROTECTED'; END IF;
 before_orders:=public.order_payment_snapshot_internal(v_order_ids);
 WITH lifecycle AS MATERIALIZED (SELECT id,state FROM public.blueprint_spot_facts_internal(occ,ids))
 SELECT coalesce(jsonb_agg(jsonb_build_object('spotId',s.id,'title',s.title,'state',lifecycle.state,'productId',s.product,
  'productTitle',p.title,'orderId',o.id,'ticketId',i.ticket,
  'customer',jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email')) ORDER BY s.id),'[]'),
 coalesce(jsonb_agg(jsonb_build_object('spot',s.id,'blueprint',s.blueprint,'item',i.id,'ticketState',t.state,
  'product',s.product,'price',p.price,'currency',p.currency_code) ORDER BY s.id),'[]')
 INTO sides,facts FROM eshop.spots s LEFT JOIN eshop.products p ON p.id=s.product
 LEFT JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket LEFT JOIN eshop.tickets t ON t.id=i.ticket
 LEFT JOIN eshop.orders o ON o.id=i."order" LEFT JOIN lifecycle ON lifecycle.id=s.id WHERE s.id=ANY(ids);
 FOR i IN 1..cardinality(left_ids) LOOP PERFORM public.apply_blueprint_seat_pair_locked_internal(left_ids[i],right_ids[i]); END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('orderId',id,
  'beforeAmount',(before_orders->id::text->>'amount')::numeric,'afterAmount',price,
  'delta',price-(before_orders->id::text->>'amount')::numeric,'currencyCode',currency_code,
  'beforeState',before_orders->id::text->>'state','afterState',state) ORDER BY id),'[]')
 INTO effects FROM eshop.orders WHERE id=ANY(v_order_ids);
 result:=jsonb_build_object('code',200,'spotIds',to_jsonb(ids),'sourceSpotIds',left_ids,'targetSpotIds',right_ids,
  'blueprints',revisions,'sides',sides,'orders',effects);
 RETURN result||jsonb_build_object('confirmationHash',encode(extensions.digest(convert_to(
  jsonb_build_object('first',p_first,'second',p_second,'result',result,'facts',facts,'beforeOrders',before_orders)::text,'UTF8'),'sha256'),'hex'));
END $$;
REVOKE ALL ON FUNCTION public.apply_blueprint_seat_swap_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
