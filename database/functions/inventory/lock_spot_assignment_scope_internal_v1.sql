-- Capture the parent set before locks; a changed hierarchy requires the same
-- command to retry rather than acquiring a new parent after its children.
CREATE OR REPLACE FUNCTION public.lock_spot_assignment_scope_internal_v1(p_spots bigint[],p_resources bigint[] DEFAULT '{}')
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE before_spots jsonb; after_spots jsonb; before_resources jsonb; after_resources jsonb; resource_ids bigint[];
BEGIN
 SELECT coalesce(jsonb_agg(jsonb_build_array(s.id,s.occasion,s.product,s.blueprint,s.inventory_context,s.resource,s.resource_slot,s.order_product_ticket) ORDER BY s.id),'[]')
 INTO before_spots FROM eshop.spots s WHERE s.id=ANY(p_spots);
 SELECT ARRAY(SELECT DISTINCT id FROM (
  SELECT unnest(p_resources) id UNION SELECT s.resource FROM eshop.spots s WHERE s.id=ANY(p_spots)
  UNION SELECT rs.resource FROM public.resource_slots rs JOIN eshop.spots s ON s.resource_slot=rs.id WHERE s.id=ANY(p_spots)) r WHERE id IS NOT NULL)
 INTO resource_ids;
 SELECT coalesce(jsonb_agg(jsonb_build_array(r.id,r.inventory_pool) ORDER BY r.id),'[]') INTO before_resources FROM public.resources r WHERE r.id=ANY(resource_ids);
 PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT opt."order" FROM eshop.order_product_ticket opt JOIN eshop.spots s ON s.order_product_ticket=opt.id WHERE s.id=ANY(p_spots)));
 PERFORM 1 FROM eshop.products WHERE id IN(SELECT product FROM eshop.spots WHERE id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.blueprints WHERE id IN(SELECT blueprint FROM eshop.spots WHERE id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN(
  SELECT inventory_pool FROM public.resources WHERE id=ANY(resource_ids)
  UNION SELECT c.inventory_pool FROM public.inventory_contexts c JOIN eshop.spots s ON s.inventory_context=c.id WHERE s.id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.resources WHERE id=ANY(resource_ids) ORDER BY id FOR UPDATE;
 SELECT coalesce(jsonb_agg(jsonb_build_array(r.id,r.inventory_pool) ORDER BY r.id),'[]') INTO after_resources FROM public.resources r WHERE r.id=ANY(resource_ids);
 IF before_resources IS DISTINCT FROM after_resources THEN RAISE serialization_failure USING MESSAGE='resource parent changed; retry the same command'; END IF;
 PERFORM 1 FROM public.resource_slots WHERE resource=ANY(resource_ids) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.spots WHERE id=ANY(p_spots) ORDER BY id FOR UPDATE;
 SELECT coalesce(jsonb_agg(jsonb_build_array(s.id,s.occasion,s.product,s.blueprint,s.inventory_context,s.resource,s.resource_slot,s.order_product_ticket) ORDER BY s.id),'[]')
 INTO after_spots FROM eshop.spots s WHERE s.id=ANY(p_spots);
 PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY(SELECT x.ticket FROM eshop.spots s
 JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE s.id=ANY(p_spots)));
 IF before_spots IS DISTINCT FROM after_spots THEN RAISE serialization_failure USING MESSAGE='spot parent changed; retry the same command'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.lock_spot_assignment_scope_internal_v1(bigint[],bigint[]) FROM PUBLIC,anon,authenticated,service_role;
