-- Shared catalog projection and bounded server-side keysets.
-- One projection for the complete UI bundle and bounded product pages.
-- Internal only: callers own tenant/permission checks. NULL limit is the
-- explicit complete editor mode; pages use ID keysets, not a collection snapshot.
CREATE OR REPLACE FUNCTION public.get_product_catalog_data_internal(
 p_occasion bigint,p_after bigint DEFAULT NULL,p_limit integer DEFAULT NULL)
RETURNS json LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE
  product_types json;
  products json;
  inventory_pools_data json;
  inventory_contexts_data json;
  product_inventory_contexts_data json;
  forms_data json;
  occ_id bigint := p_occasion;
  selected_ids bigint[];
  next_id bigint;
BEGIN
  IF p_limit IS NOT NULL AND (p_limit<1 OR p_limit>100) OR p_after IS NOT NULL AND p_after<1 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid catalog page';
  END IF;
  SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]) INTO selected_ids
  FROM (SELECT p.id FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
        WHERE pt.occasion=occ_id AND (p_after IS NULL OR p.id>p_after)
        ORDER BY p.id LIMIT CASE WHEN p_limit IS NULL THEN NULL ELSE p_limit+1 END) selected;
  IF cardinality(selected_ids)>p_limit THEN
    selected_ids:=selected_ids[1:p_limit];
    next_id:=selected_ids[p_limit];
  END IF;
  -- A page must never silently truncate inventory assignments. The existing
  -- product DTO supports up to 1000 assignments per product.
  IF p_limit IS NOT NULL AND EXISTS(SELECT 1 FROM eshop.product_inventory_contexts
       WHERE product=ANY(selected_ids) GROUP BY product HAVING count(*)>1000) THEN
    RAISE program_limit_exceeded USING MESSAGE='product inventory assignments exceed catalog page contract';
  END IF;

-- Fetch all product types for the given occasion
  SELECT json_agg(
           json_build_object(
             'id', pt.id,
             'type', pt.type,
             'title', pt.title
           )
         )
    INTO product_types
  FROM eshop.product_types pt
  WHERE pt.occasion = occ_id AND (p_limit IS NULL OR pt.id IN (SELECT product_type FROM eshop.products WHERE id=ANY(selected_ids)));

  -- Fetch all products for the given occasion, including form IDs
  SELECT json_agg(
           json_build_object(
             'id', p.id,
            'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='product' AND scope_type='occasion' AND scope_id=p.occasion AND aggregate_id=p.id::text),0),
             'title', p.title,
             'description', p.description,
             'short_title', p.data->>'short_title',
             'product_type', p.product_type,
             'data', p.data,
             'price', p.price,
             'price_changes', (SELECT COALESCE(json_agg(pc ORDER BY pc.change_time,pc.id),'[]'::json)
               FROM eshop.planned_changes pc WHERE pc.subject_id=p.id AND pc.change_type='products.price' AND NOT pc.applied),
             'visibility_changes', (SELECT COALESCE(json_agg(pc ORDER BY pc.change_time,pc.id),'[]'::json)
               FROM eshop.planned_changes pc WHERE pc.subject_id=p.id AND pc.change_type='products.is_hidden' AND NOT pc.applied),
             'currency_code', p.currency_code,
             'is_hidden', p.is_hidden,
             'is_used_in_blueprint', EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product=p.id AND s.occasion=occ_id),
             'order', p."order",
             'maximum', p.maximum,
             'form_ids', (
               SELECT COALESCE(json_agg(DISTINCT ff.form), '[]'::json)
               FROM public.form_fields ff
               WHERE ff.product_type = p.product_type
             ),
             'ordered_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               WHERE opt.product = p.id
             ),
             'paid_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               JOIN eshop.orders o ON o.id = opt.order
               WHERE opt.product = p.id
                 AND o.state = 'paid'
             ),
             'sent_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               JOIN eshop.orders o ON o.id = opt.order
               WHERE opt.product = p.id
                 AND o.state = 'sent'
             )
           ) ORDER BY p.id
         )
    INTO products
  FROM eshop.products p
  WHERE p.id=ANY(selected_ids);

  -- Fetch all inventory pools for the occasion
  SELECT json_agg(ip.*)
  INTO inventory_pools_data
  FROM public.inventory_pools ip
  WHERE ip.occasion = occ_id AND p_limit IS NULL;

  -- Fetch all inventory contexts for the occasion
  SELECT json_agg(ic.*)
  INTO inventory_contexts_data
  FROM public.inventory_contexts ic
  JOIN public.inventory_pools ip ON ic.inventory_pool = ip.id
  WHERE ip.occasion = occ_id AND (p_limit IS NULL OR ic.id IN (
    SELECT inventory_context FROM eshop.product_inventory_contexts WHERE product=ANY(selected_ids)));

  -- Fetch all links between products and inventory contexts for the occasion
  SELECT json_agg(pic.*)
  INTO product_inventory_contexts_data
  FROM eshop.product_inventory_contexts pic
  JOIN eshop.products p ON pic.product = p.id
  JOIN eshop.product_types pt ON p.product_type = pt.id
  WHERE pt.occasion = occ_id AND p.id=ANY(selected_ids);

  -- Fetch only the id, title, and link for each form associated with the occasion
  SELECT json_agg(
           json_build_object(
             'id', f.id,
             'title', f.title,
             'link', f.link
           )
         )
    INTO forms_data
  FROM public.forms f
  WHERE f.occasion = occ_id AND p_limit IS NULL;

  RETURN json_build_object(
    'server_time', clock_timestamp(),
    'nextCursor',next_id,
    'price_waves', (SELECT COALESCE(json_agg(w ORDER BY w.change_time,w.id),'[]'::json)
      FROM eshop.product_price_waves w WHERE p_limit IS NULL AND w.occasion=occ_id AND (w.change_time>clock_timestamp() OR
        EXISTS(SELECT 1 FROM eshop.planned_changes pc WHERE pc.wave_id=w.id AND NOT pc.applied))),
    'product_types', COALESCE(product_types, '[]'::json),
    'products', COALESCE(products, '[]'::json),
    'inventory_pools', COALESCE(inventory_pools_data, '[]'::json),
    'inventory_contexts', COALESCE(inventory_contexts_data, '[]'::json),
    'product_inventory_contexts', COALESCE(product_inventory_contexts_data, '[]'::json),
    'forms', COALESCE(forms_data, '[]'::json)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_product_catalog_data_internal(bigint,bigint,integer) FROM PUBLIC,anon,authenticated,service_role;

-- Public compatibility entry used by released editor clients. Remove only once
-- supported clients use get_product_catalog exclusively. No second projection.
CREATE OR REPLACE FUNCTION public.get_products_and_types_for_edit(occasion_link text)
RETURNS json LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE oc bigint;
BEGIN
 SELECT id INTO oc FROM public.occasions
 WHERE id=public.resolve_occasion_link_internal(occasion_link)
 AND organization=(SELECT ui.organization FROM public.user_info ui WHERE ui.id=auth.uid());
 IF oc IS NULL THEN RAISE EXCEPTION 'Occasion not found for link: %',occasion_link; END IF;
 IF public.can_read_orders(oc) IS DISTINCT FROM TRUE THEN
  RETURN json_build_object('code',403,'message','User is not authorized to view this.');
 END IF;
 RETURN public.get_product_catalog_data_internal(oc);
END $$;
REVOKE ALL ON FUNCTION public.get_products_and_types_for_edit(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_products_and_types_for_edit(text) TO authenticated;

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
DECLARE oc bigint:=p_occasion;
BEGIN
 IF p_occasion_link IS NOT NULL THEN
  oc:=public.resolve_occasion_link_internal(p_occasion_link);
  IF p_occasion IS NOT NULL AND oc IS DISTINCT FROM p_occasion THEN
   RAISE insufficient_privilege USING MESSAGE='product context unavailable'; END IF;
 END IF;
 PERFORM public.check_product_catalog_scope_internal(oc,p_organization,p_unit,false,true);
 RETURN jsonb_build_object('occasionId',oc,'catalog',public.get_product_catalog_data_internal(oc));
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
 RETURN jsonb_build_object('occasionId',p_occasion,'nextCursor',catalog->'nextCursor','catalog',
   catalog-ARRAY['nextCursor','server_time','price_waves','inventory_pools','forms']);
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
