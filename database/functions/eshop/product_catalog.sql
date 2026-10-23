-- Shared UI/MCP boundary. Existing product commands remain the sole owners of
-- business rules, receipts, inventory recalculation and sync publication.
CREATE OR REPLACE FUNCTION public.check_product_catalog_scope_internal(
 p_occasion bigint,p_organization bigint,p_unit bigint,p_write boolean,p_lock boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF p_lock THEN
  PERFORM 1 FROM public.occasions o JOIN public.user_info ui ON ui.id=auth.uid() AND ui.organization=o.organization
   WHERE o.id=p_occasion AND o.organization=p_organization AND (p_unit IS NULL OR o.unit=p_unit) FOR SHARE OF o;
 ELSE
  PERFORM 1 FROM public.occasions o JOIN public.user_info ui ON ui.id=auth.uid() AND ui.organization=o.organization
   WHERE o.id=p_occasion AND o.organization=p_organization AND (p_unit IS NULL OR o.unit=p_unit);
 END IF;
 IF NOT FOUND OR public.can_read_orders(p_occasion) IS DISTINCT FROM TRUE
  OR (p_write AND public.can_write_orders(p_occasion) IS DISTINCT FROM TRUE) THEN
  RAISE insufficient_privilege USING MESSAGE='product context unavailable';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_product_catalog_scope_internal(bigint,bigint,bigint,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_product_catalog(p_organization bigint,p_occasion bigint DEFAULT NULL,
 p_unit bigint DEFAULT NULL,p_occasion_link text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint:=p_occasion; result jsonb;
BEGIN
 IF p_occasion_link IS NOT NULL THEN
  oc:=public.resolve_occasion_link_internal(p_occasion_link);
  IF p_occasion IS NOT NULL AND oc IS DISTINCT FROM p_occasion THEN
   RAISE insufficient_privilege USING MESSAGE='product context unavailable'; END IF;
 END IF;
 PERFORM public.check_product_catalog_scope_internal(oc,p_organization,p_unit,false,true);
 result:=jsonb_build_object('occasionId',oc,'catalog',public.get_product_catalog_data_internal(oc));
 PERFORM public.check_product_catalog_scope_internal(oc,p_organization,p_unit,false,true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_product_catalog(bigint,bigint,bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_product_catalog(bigint,bigint,bigint,text) TO authenticated;

-- Bounded read mode of the same catalog owner. Keep the four-argument
-- editor API for released clients; no overload with ambiguous defaults.
CREATE OR REPLACE FUNCTION public.get_product_catalog_page(p_organization bigint,p_occasion bigint,
 p_unit bigint DEFAULT NULL,p_after bigint DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE catalog jsonb;
BEGIN
 IF p_limit IS NULL OR p_limit<1 OR p_limit>100 OR p_after IS NOT NULL AND p_after<1 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid catalog page';
 END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 catalog:=public.get_product_catalog_data_internal(p_occasion,p_after,p_limit)::jsonb;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 RETURN jsonb_build_object('occasionId',p_occasion,'nextCursor',catalog->'nextCursor','catalog',
   catalog-ARRAY['nextCursor','server_time','price_waves','inventory_pools']);
END $$;
REVOKE ALL ON FUNCTION public.get_product_catalog_page(bigint,bigint,bigint,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_product_catalog_page(bigint,bigint,bigint,bigint,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.manage_product(p_occasion bigint,p_organization bigint,p_unit bigint,
 p_action text,p_product jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint; product_id bigint; receipt_name text; result jsonb;
BEGIN
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true);
 IF p_action IS NULL OR p_action NOT IN ('save','delete','contexts') OR p_product IS NULL
  OR jsonb_typeof(p_product)<>'object' OR octet_length(p_product::text)>524288 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid product command'; END IF;
 product_id:=NULLIF(p_product->>'id','')::bigint;
 receipt_name:=CASE p_action WHEN 'save' THEN 'inventory.product.save' WHEN 'delete' THEN 'inventory.product.delete' ELSE 'inventory.product.contexts' END;
 -- Retained receipt is the authoritative occasion after a successful deletion.
 SELECT occasion INTO oc FROM public.client_mutation_receipts
  WHERE command_id=p_command_id AND actor_id=auth.uid() AND command_name=receipt_name;
 IF NOT FOUND THEN
  IF product_id IS NOT NULL THEN SELECT p.occasion INTO oc FROM eshop.products p WHERE p.id=product_id;
  ELSIF p_action='save' THEN SELECT pt.occasion INTO oc FROM eshop.product_types pt WHERE pt.id=(p_product->>'product_type')::bigint;
  END IF;
 END IF;
 IF oc IS DISTINCT FROM p_occasion OR (p_product->>'occasion' IS NOT NULL AND (p_product->>'occasion')::bigint IS DISTINCT FROM p_occasion)
  OR (p_product->>'product_type' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.product_types pt WHERE pt.id=(p_product->>'product_type')::bigint AND pt.occasion=p_occasion)) THEN
  RAISE insufficient_privilege USING MESSAGE='product unavailable'; END IF;
 IF product_id IS NOT NULL AND (p_product->>'expected_aggregate_version' IS NULL
   OR (p_product->>'expected_aggregate_version')::bigint<0) THEN
  RAISE invalid_parameter_value USING MESSAGE='original product version required'; END IF;
 IF p_action='save' THEN
  result:=public.update_product_client_sync_v1(p_product,p_command_id);
 ELSIF p_action='delete' THEN
  result:=public.delete_product_client_sync_v1(product_id,p_command_id,(p_product->>'expected_aggregate_version')::bigint);
 ELSE
  result:=public.update_product_inventory_contexts_client_sync_v1(product_id,
   jsonb_build_object('expected_aggregate_version',p_product->'expected_aggregate_version','contexts',p_product->'inventory_contexts'),p_command_id);
 END IF;
 -- Validate and lock the live tenant/organizer after domain locking, including
 -- receipt replay. A concurrent move or rights change rolls back ALL effects.
 -- Do not acquire organizer locks before the canonical receipt/order locks.
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.manage_product(bigint,bigint,bigint,text,jsonb,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_product(bigint,bigint,bigint,text,jsonb,uuid) TO authenticated;
