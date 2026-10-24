-- Keep seat product visibility changes out of price waves until seat availability supports them.
CREATE OR REPLACE FUNCTION public.save_product_wave_target(
  p_wave_id bigint,p_product_id bigint,p_expected_wave_revision bigint,p_price numeric,p_is_hidden boolean,
  p_expected_price_revision bigint DEFAULT NULL,p_expected_visibility_revision bigint DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_wave eshop.product_price_waves%ROWTYPE; v_product eshop.products%ROWTYPE;
  v_price eshop.planned_changes%ROWTYPE; v_visibility eshop.planned_changes%ROWTYPE;
BEGIN
  SELECT * INTO STRICT v_wave FROM eshop.product_price_waves WHERE id=p_wave_id FOR UPDATE;
  PERFORM public.check_product_wave_editor(v_wave.occasion);
  IF v_wave.revision IS DISTINCT FROM p_expected_wave_revision THEN RAISE serialization_failure USING MESSAGE='PRICE_CHANGE_CONFLICT'; END IF;
  IF v_wave.change_time<=clock_timestamp() THEN RAISE invalid_parameter_value USING MESSAGE='FUTURE_TIME_REQUIRED'; END IF;
  SELECT * INTO STRICT v_product FROM eshop.products WHERE id=p_product_id FOR UPDATE;
  IF v_product.occasion IS DISTINCT FROM v_wave.occasion OR NOT EXISTS(
    SELECT 1 FROM eshop.product_types WHERE id=v_product.product_type AND occasion=v_wave.occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='PRODUCT_OCCASION_MISMATCH'; END IF;
  IF v_wave.change_time<=clock_timestamp() THEN RAISE invalid_parameter_value USING MESSAGE='FUTURE_TIME_REQUIRED'; END IF;
  -- Lock in the same subject/plan order as the executor and single-product editor.
  PERFORM 1 FROM eshop.planned_changes WHERE subject_id=p_product_id AND wave_id=p_wave_id
    AND NOT applied ORDER BY id FOR UPDATE;
  SELECT * INTO v_price FROM eshop.planned_changes WHERE subject_id=p_product_id
    AND wave_id=p_wave_id AND change_type='products.price' AND NOT applied;
  SELECT * INTO v_visibility FROM eshop.planned_changes WHERE subject_id=p_product_id
    AND wave_id=p_wave_id AND change_type='products.is_hidden' AND NOT applied;
  IF v_price.revision IS DISTINCT FROM p_expected_price_revision OR
    v_visibility.revision IS DISTINCT FROM p_expected_visibility_revision THEN
    RAISE serialization_failure USING MESSAGE='PRICE_CHANGE_CONFLICT'; END IF;
  -- Seat products must not become unorderable while seats remain selectable.
  -- Keep an existing target on a price-only save; NULL explicitly cancels it.
  IF p_is_hidden IS NOT NULL AND EXISTS (
    SELECT 1 FROM eshop.spots s WHERE s.product=p_product_id AND s.occasion=v_wave.occasion
  ) AND (v_visibility.id IS NULL OR v_visibility.new_value IS DISTINCT FROM p_is_hidden::text) THEN
    RAISE invalid_parameter_value USING MESSAGE='BLUEPRINT_PRODUCT_VISIBILITY_NOT_SUPPORTED';
  END IF;
  IF EXISTS(SELECT 1 FROM eshop.planned_changes WHERE subject_id=p_product_id
    AND change_time=v_wave.change_time AND NOT applied AND wave_id IS DISTINCT FROM p_wave_id
    AND ((change_type='products.price' AND p_price IS NOT NULL) OR
         (change_type='products.is_hidden' AND p_is_hidden IS NOT NULL))) THEN
    RAISE serialization_failure USING MESSAGE='PRICE_CHANGE_CONFLICT'; END IF;
  IF p_price IS NOT NULL THEN
    PERFORM public.validate_product_price(p_price,v_product.data,v_product.currency_code);
    IF v_price.id IS NULL THEN
      INSERT INTO eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion,wave_id)
        VALUES('products.price',p_product_id,p_price::text,v_wave.change_time,v_wave.occasion,p_wave_id);
    ELSE
      UPDATE eshop.planned_changes SET new_value=p_price::text,failed_at=NULL,failure_code=NULL,revision=revision+1 WHERE id=v_price.id;
    END IF;
  ELSIF v_price.id IS NOT NULL THEN DELETE FROM eshop.planned_changes WHERE id=v_price.id;
  END IF;
  IF p_is_hidden IS NOT NULL THEN
    IF v_visibility.id IS NULL THEN
      INSERT INTO eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion,wave_id)
        VALUES('products.is_hidden',p_product_id,p_is_hidden::text,v_wave.change_time,v_wave.occasion,p_wave_id);
    ELSE
      UPDATE eshop.planned_changes SET new_value=p_is_hidden::text,failed_at=NULL,failure_code=NULL,revision=revision+1 WHERE id=v_visibility.id;
    END IF;
  ELSIF v_visibility.id IS NOT NULL THEN DELETE FROM eshop.planned_changes WHERE id=v_visibility.id;
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.save_product_wave_target(bigint,bigint,bigint,numeric,boolean,bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_product_wave_target(bigint,bigint,bigint,numeric,boolean,bigint,bigint) TO authenticated;


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
  WHERE id = public.resolve_occasion_link_internal(occasion_link)
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
    'server_time', clock_timestamp(),
    'price_waves', (SELECT COALESCE(json_agg(w ORDER BY w.change_time,w.id),'[]'::json)
      FROM eshop.product_price_waves w WHERE w.occasion=occ_id AND (w.change_time>clock_timestamp() OR
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

REVOKE ALL ON FUNCTION public.get_products_and_types_for_edit(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_products_and_types_for_edit(text) TO authenticated;
