-- Page unused authoring choices through the same metadata owners as the UI.
-- Shared editor-choice projections. NULL IDs is an explicit full UI metadata
-- request; an empty array is an empty product page, never a request for all rows.
CREATE OR REPLACE FUNCTION public.get_product_type_rows_internal(p_occasion bigint,p_ids bigint[] DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',pt.id,'type',pt.type,'title',pt.title) ORDER BY pt.id),'[]')
 FROM eshop.product_types pt WHERE pt.occasion=p_occasion AND (p_ids IS NULL OR pt.id=ANY(p_ids))
$$;
REVOKE ALL ON FUNCTION public.get_product_type_rows_internal(bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_product_context_rows_internal(p_occasion bigint,p_ids bigint[] DEFAULT NULL,p_editor boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg((CASE WHEN p_editor THEN to_jsonb(ic) ELSE jsonb_build_object(
  'id',ic.id,'title',ic.title,'inventory_pool',ic.inventory_pool,'block_date',ic.block_date) END)
  ||jsonb_build_object('pool_title',ip.title,'pool_type',ip.type) ORDER BY ic.id),'[]')
 FROM public.inventory_contexts ic JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
 WHERE ip.occasion=p_occasion AND (p_ids IS NULL OR ic.id=ANY(p_ids))
$$;
REVOKE ALL ON FUNCTION public.get_product_context_rows_internal(bigint,bigint[],boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_product_catalog_options(p_occasion bigint,p_organization bigint,p_unit bigint,p_kind text,
 p_after bigint DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ids bigint[];next_id bigint;rows jsonb;
BEGIN
 IF p_kind IS NULL OR p_kind NOT IN ('product_types','inventory_contexts') OR p_limit IS NULL OR p_limit<1 OR p_limit>100
  OR p_after IS NOT NULL AND p_after<1 THEN RAISE invalid_parameter_value USING MESSAGE='invalid product option page'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 IF p_kind='product_types' THEN
  SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]) INTO ids FROM (
   SELECT id FROM eshop.product_types WHERE occasion=p_occasion AND (p_after IS NULL OR id>p_after)
   ORDER BY id LIMIT p_limit+1) selected;
 ELSE
  SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]) INTO ids FROM (
   SELECT ic.id FROM public.inventory_contexts ic JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
   WHERE ip.occasion=p_occasion AND (p_after IS NULL OR ic.id>p_after) ORDER BY ic.id LIMIT p_limit+1) selected;
 END IF;
 IF cardinality(ids)>p_limit THEN ids:=ids[1:p_limit];next_id:=ids[p_limit]; END IF;
 IF p_kind='product_types' THEN rows:=public.get_product_type_rows_internal(p_occasion,ids);
 ELSE rows:=public.get_product_context_rows_internal(p_occasion,ids); END IF;
 IF octet_length(rows::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='product option page exceeds payload limit; use a smaller limit'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 RETURN jsonb_build_object('occasionId',p_occasion,'kind',p_kind,'options',rows,'nextCursor',next_id,'readAt',statement_timestamp());
END $$;
REVOKE ALL ON FUNCTION public.get_product_catalog_options(bigint,bigint,bigint,text,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_product_catalog_options(bigint,bigint,bigint,text,bigint,integer) TO authenticated;

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
        WHERE pt.occasion=occ_id AND p.occasion=occ_id AND (p_after IS NULL OR p.id>p_after)
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

  product_types:=public.get_product_type_rows_internal(occ_id,
    CASE WHEN p_limit IS NULL THEN NULL ELSE ARRAY(SELECT product_type FROM eshop.products WHERE id=ANY(selected_ids)) END)::json;

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
               SELECT COALESCE(json_agg(DISTINCT ff.form ORDER BY ff.form), '[]'::json)
               FROM public.form_fields ff JOIN public.forms f ON f.id=ff.form
               WHERE ff.product_type = p.product_type AND f.occasion=occ_id
             ),
             -- These are product-ticket relationship rows, never unique people
             -- or order counts. Preserve historical all-state ordered_count.
             'ordered_count', sales.ordered_count,
             'paid_count', sales.paid_count,
             'sent_count', sales.sent_count,
             'purchased_count', sales.purchased_count
           ) ORDER BY p.id
         )
    INTO products
  FROM eshop.products p
  CROSS JOIN LATERAL (
    SELECT count(*) ordered_count,
      count(*) FILTER(WHERE o.state='paid') paid_count,
      count(*) FILTER(WHERE o.state='sent') sent_count,
      count(*) FILTER(WHERE o.state IN ('paid','sent')) purchased_count
    FROM eshop.order_product_ticket opt LEFT JOIN eshop.orders o ON o.id=opt."order"
    WHERE opt.product=p.id
  ) sales
  WHERE p.id=ANY(selected_ids);

  -- Fetch all inventory pools for the occasion
  SELECT json_agg(ip.*)
  INTO inventory_pools_data
  FROM public.inventory_pools ip
  WHERE ip.occasion = occ_id AND p_limit IS NULL;

  inventory_contexts_data:=public.get_product_context_rows_internal(occ_id,
    CASE WHEN p_limit IS NULL THEN NULL ELSE ARRAY(SELECT inventory_context FROM eshop.product_inventory_contexts WHERE product=ANY(selected_ids)) END,
    p_limit IS NULL)::json;

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
             'title', f.title
           )::jsonb || CASE WHEN p_limit IS NULL THEN jsonb_build_object('link',f.link) ELSE '{}'::jsonb END
         )
    INTO forms_data
  FROM public.forms f
  WHERE f.occasion = occ_id AND (p_limit IS NULL OR EXISTS(
    SELECT 1 FROM public.form_fields ff JOIN eshop.products p ON p.product_type=ff.product_type
    WHERE ff.form=f.id AND p.id=ANY(selected_ids)));
  IF p_limit IS NOT NULL AND json_array_length(coalesce(forms_data,'[]'::json))>1000 THEN
    RAISE program_limit_exceeded USING MESSAGE='form references exceed catalog page contract';
  END IF;

  RETURN json_build_object(
    'server_time', clock_timestamp(),
    'nextCursor',next_id,
    'price_waves', CASE WHEN p_limit IS NULL THEN public.get_product_price_waves_internal(occ_id)->'waves' ELSE '[]'::jsonb END,
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
