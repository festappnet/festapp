CREATE OR REPLACE FUNCTION public.get_products_and_types_for_edit(occasion_link text)
RETURNS json LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  product_types json;
  products json;
  inventory_pools_data json;
  inventory_contexts_data json;
  product_inventory_contexts_data json;
  forms_data json;
  occ_id bigint;
BEGIN
  -- Resolve occasion_id from the provided occasion_link
  SELECT id
    INTO occ_id
  FROM public.occasions
  WHERE link = occasion_link
    AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());

  -- If the occasion link is invalid, raise an exception.
  IF occ_id IS NULL THEN
    RAISE EXCEPTION 'Occasion not found for link: %', occasion_link;
  END IF;

  -- Verify if the current user is an editor for the order's occasion
  IF NOT get_is_editor_order_view_on_occasion(occ_id) THEN
      RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to view this.');
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
  WHERE pt.occasion = occ_id;

  -- Fetch all products for the given occasion, including form IDs
  SELECT json_agg(
           json_build_object(
             'id', p.id,
             'title', p.title,
             'description', p.description,
             'short_title', p.data->>'short_title',
             'product_type', p.product_type,
             'data', p.data,
             'price', p.price,
             'currency_code', p.currency_code,
             'is_hidden', p.is_hidden,
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
           )
         )
    INTO products
  FROM eshop.products p
  WHERE p.product_type IN (
    SELECT pt.id
    FROM eshop.product_types pt
    WHERE pt.occasion = occ_id
  );

  -- Fetch all inventory pools for the occasion
  SELECT json_agg(ip.*)
  INTO inventory_pools_data
  FROM public.inventory_pools ip
  WHERE ip.occasion = occ_id;

  -- Fetch all inventory contexts for the occasion
  SELECT json_agg(ic.*)
  INTO inventory_contexts_data
  FROM public.inventory_contexts ic
  JOIN public.inventory_pools ip ON ic.inventory_pool = ip.id
  WHERE ip.occasion = occ_id;

  -- Fetch all links between products and inventory contexts for the occasion
  SELECT json_agg(pic.*)
  INTO product_inventory_contexts_data
  FROM eshop.product_inventory_contexts pic
  JOIN eshop.products p ON pic.product = p.id
  JOIN eshop.product_types pt ON p.product_type = pt.id
  WHERE pt.occasion = occ_id;

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
  WHERE f.occasion = occ_id;

  RETURN json_build_object(
    'product_types', COALESCE(product_types, '[]'::json),
    'products', COALESCE(products, '[]'::json),
    'inventory_pools', COALESCE(inventory_pools_data, '[]'::json),
    'inventory_contexts', COALESCE(inventory_contexts_data, '[]'::json),
    'product_inventory_contexts', COALESCE(product_inventory_contexts_data, '[]'::json),
    'forms', COALESCE(forms_data, '[]'::json)
  );
END;
$$;
