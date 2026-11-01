-- One parent-before-child lock owner. Financial seat commands include the
-- complete order-product closure; existing inventory callers keep their scope.
CREATE OR REPLACE FUNCTION public.lock_spot_assignment_scope_internal(
 p_spots bigint[],p_resources bigint[],p_financial boolean,p_products bigint[],p_preserve_print boolean,p_source_orders bigint[],p_source_items bigint[])
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE before_spots jsonb;after_spots jsonb;before_resources jsonb;after_resources jsonb;
 resource_ids bigint[];v_orders bigint[];v_order_products bigint[]:=coalesce(p_products,'{}');
BEGIN
 IF p_financial IS NULL OR p_preserve_print IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='assignment lock mode required'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_array(s.id,s.occasion,s.product,s.blueprint,s.inventory_context,s.resource,s.resource_slot,s.order_product_ticket) ORDER BY s.id),'[]')
 INTO before_spots FROM eshop.spots s WHERE s.id=ANY(p_spots);
 SELECT ARRAY(SELECT DISTINCT id FROM (
  SELECT unnest(p_resources) id UNION SELECT s.resource FROM eshop.spots s WHERE s.id=ANY(p_spots)
  UNION SELECT rs.resource FROM public.resource_slots rs JOIN eshop.spots s ON s.resource_slot=rs.id WHERE s.id=ANY(p_spots)) r WHERE id IS NOT NULL)
 INTO resource_ids;
 SELECT coalesce(jsonb_agg(jsonb_build_array(r.id,r.inventory_pool) ORDER BY r.id),'[]') INTO before_resources FROM public.resources r WHERE r.id=ANY(resource_ids);
 SELECT ARRAY(SELECT DISTINCT i."order" FROM eshop.order_product_ticket i JOIN eshop.spots s ON s.order_product_ticket=i.id WHERE s.id=ANY(p_spots) UNION SELECT unnest(coalesce(p_source_orders,'{}'::bigint[])) UNION SELECT "order" FROM eshop.order_product_ticket WHERE id=ANY(p_source_items) ORDER BY 1) INTO v_orders;
 PERFORM public.lock_order_capacity_scope_internal(v_orders);
 IF p_financial THEN
  IF v_orders IS DISTINCT FROM ARRAY(SELECT DISTINCT i."order" FROM eshop.order_product_ticket i JOIN eshop.spots s ON s.order_product_ticket=i.id WHERE s.id=ANY(p_spots) UNION SELECT unnest(coalesce(p_source_orders,'{}'::bigint[])) UNION SELECT "order" FROM eshop.order_product_ticket WHERE id=ANY(p_source_items) ORDER BY 1) THEN
   RAISE serialization_failure USING MESSAGE='assignment order parents changed; retry the same command'; END IF;
  SELECT ARRAY(SELECT product FROM eshop.order_product_ticket WHERE "order"=ANY(v_orders) AND product IS NOT NULL UNION SELECT unnest(coalesce(p_products,'{}'::bigint[])) ORDER BY 1) INTO v_order_products;
 END IF;
 -- Union every affected product before taking any blueprint/inventory child.
 PERFORM 1 FROM eshop.products WHERE id IN(
  SELECT product FROM eshop.spots WHERE id=ANY(p_spots) UNION SELECT unnest(v_order_products)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.blueprints WHERE id IN(
  SELECT blueprint FROM eshop.spots WHERE id=ANY(p_spots)
  UNION SELECT blueprint FROM public.forms WHERE p_financial AND id IN(SELECT form FROM eshop.orders WHERE id=ANY(v_orders))
  UNION SELECT blueprint FROM eshop.spots WHERE product=ANY(v_order_products)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN(
  SELECT inventory_pool FROM public.resources WHERE id=ANY(resource_ids)
  UNION SELECT c.inventory_pool FROM public.inventory_contexts c JOIN eshop.spots s ON s.inventory_context=c.id WHERE s.id=ANY(p_spots)
  UNION SELECT c.inventory_pool FROM public.inventory_contexts c JOIN eshop.product_inventory_contexts pc ON pc.inventory_context=c.id WHERE pc.product=ANY(v_order_products)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.resources WHERE id=ANY(resource_ids) ORDER BY id FOR UPDATE;
 SELECT coalesce(jsonb_agg(jsonb_build_array(r.id,r.inventory_pool) ORDER BY r.id),'[]') INTO after_resources FROM public.resources r WHERE r.id=ANY(resource_ids);
 IF before_resources IS DISTINCT FROM after_resources THEN RAISE serialization_failure USING MESSAGE='resource parent changed; retry the same command'; END IF;
 IF p_financial THEN
  PERFORM 1 FROM public.inventory_contexts WHERE id IN(
   SELECT inventory_context FROM eshop.product_inventory_contexts WHERE product=ANY(v_order_products)
   UNION SELECT inventory_context FROM eshop.spots WHERE id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 END IF;
 PERFORM 1 FROM public.resource_slots WHERE resource=ANY(resource_ids) ORDER BY id FOR UPDATE;
 IF p_financial THEN
  PERFORM 1 FROM eshop.payment_info WHERE id IN(SELECT payment_info FROM eshop.orders WHERE id=ANY(v_orders)) ORDER BY id FOR UPDATE;
 END IF;
 PERFORM 1 FROM eshop.spots WHERE id=ANY(p_spots) ORDER BY id FOR UPDATE;
 IF p_financial THEN
  PERFORM 1 FROM eshop.tickets WHERE id IN(SELECT i.ticket FROM eshop.order_product_ticket i JOIN eshop.spots s ON s.order_product_ticket=i.id WHERE s.id=ANY(p_spots) UNION SELECT ticket FROM eshop.order_product_ticket WHERE id=ANY(p_source_items)) ORDER BY id FOR UPDATE;
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_array(s.id,s.occasion,s.product,s.blueprint,s.inventory_context,s.resource,s.resource_slot,s.order_product_ticket) ORDER BY s.id),'[]')
 INTO after_spots FROM eshop.spots s WHERE s.id=ANY(p_spots);
 IF p_preserve_print THEN PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY(SELECT x.ticket FROM eshop.spots s
 JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE s.id=ANY(p_spots))); END IF;
 IF before_spots IS DISTINCT FROM after_spots THEN RAISE serialization_failure USING MESSAGE='spot parent changed; retry the same command'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.lock_spot_assignment_scope_internal(bigint[],bigint[],boolean,bigint[],boolean,bigint[],bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- Existing callers share the same explicit source-parent implementation.
CREATE OR REPLACE FUNCTION public.lock_spot_assignment_scope_internal(p_spots bigint[],p_resources bigint[],p_financial boolean,p_products bigint[],p_preserve_print boolean)
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.lock_spot_assignment_scope_internal(p_spots,p_resources,p_financial,p_products,p_preserve_print,'{}'::bigint[],'{}'::bigint[])
$$;
REVOKE ALL ON FUNCTION public.lock_spot_assignment_scope_internal(bigint[],bigint[],boolean,bigint[],boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Print-content mutations preserve the guard. Canonical cancellation may void
-- the admission identity without changing any printed content.
CREATE OR REPLACE FUNCTION public.lock_spot_assignment_scope_internal(p_spots bigint[],p_resources bigint[],p_financial boolean,p_products bigint[])
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.lock_spot_assignment_scope_internal(p_spots,p_resources,p_financial,p_products,true)
$$;
REVOKE ALL ON FUNCTION public.lock_spot_assignment_scope_internal(bigint[],bigint[],boolean,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- Existing callers retain their arity; the product closure has one lock owner.
CREATE OR REPLACE FUNCTION public.lock_spot_assignment_scope_internal(p_spots bigint[],p_resources bigint[],p_financial boolean)
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.lock_spot_assignment_scope_internal(p_spots,p_resources,p_financial,'{}'::bigint[])
$$;
REVOKE ALL ON FUNCTION public.lock_spot_assignment_scope_internal(bigint[],bigint[],boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Existing private SQL callers retain their arity, not a second implementation.
CREATE OR REPLACE FUNCTION public.lock_spot_assignment_scope_internal_v1(p_spots bigint[],p_resources bigint[] DEFAULT '{}')
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.lock_spot_assignment_scope_internal(p_spots,p_resources,false)
$$;
REVOKE ALL ON FUNCTION public.lock_spot_assignment_scope_internal_v1(bigint[],bigint[]) FROM PUBLIC,anon,authenticated,service_role;
