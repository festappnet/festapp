CREATE OR REPLACE FUNCTION public.update_product_inventory_contexts_internal_v1(p_product_id bigint, p_contexts jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_occasion_id BIGINT;
  v_order_id BIGINT;
BEGIN
    -- Get the occasion ID from the product that is being modified.
    SELECT pt.occasion INTO v_occasion_id
    FROM eshop.products p
    JOIN eshop.product_types pt ON p.product_type = pt.id
    WHERE p.id = p_product_id;

    -- If the product is not found, raise an error.
    IF NOT FOUND THEN
        RAISE EXCEPTION '%', jsonb_build_object(
            'code', 'PI404',
            'message', 'Product with ID ' || p_product_id || ' not found.'
        )::text;
    END IF;

    -- Permission check. This function is expected to throw on failure.
    PERFORM public.check_is_editor_order_on_occasion(v_occasion_id);

    -- Every caller, including aggregate saves, uses this validation owner.
    IF p_contexts IS NULL OR jsonb_typeof(p_contexts) IS DISTINCT FROM 'array'
      OR jsonb_array_length(p_contexts)>1000 OR octet_length(p_contexts::text)>1048576
      OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_contexts) c
        LEFT JOIN public.inventory_contexts ic ON ic.id=(c->>'inventory_context_id')::bigint
        LEFT JOIN public.inventory_pools pool ON pool.id=ic.inventory_pool
        WHERE pool.occasion IS DISTINCT FROM v_occasion_id OR (c->>'quantity')::integer IS NULL
          OR (c->>'quantity')::integer<0
          OR EXISTS(SELECT 1 FROM jsonb_object_keys(c) k WHERE k NOT IN ('inventory_context_id','quantity')))
      OR (SELECT count(*) FROM jsonb_array_elements(p_contexts))<>
        (SELECT count(DISTINCT (c->>'inventory_context_id')::bigint) FROM jsonb_array_elements(p_contexts) c)
    THEN RAISE invalid_parameter_value USING MESSAGE='invalid or foreign inventory contexts'; END IF;
    PERFORM public.lock_product_order_dependencies_internal_v1(p_product_id);
    PERFORM 1 FROM eshop.products WHERE id=p_product_id FOR UPDATE;
    PERFORM 1 FROM public.inventory_pools WHERE id IN(SELECT inventory_pool FROM public.inventory_contexts WHERE id IN
      (SELECT inventory_context FROM eshop.product_inventory_contexts WHERE product=p_product_id UNION SELECT (x->>'inventory_context_id')::bigint FROM jsonb_array_elements(p_contexts) x)) ORDER BY id FOR UPDATE;
    PERFORM 1 FROM public.inventory_contexts WHERE id IN
      (SELECT inventory_context FROM eshop.product_inventory_contexts WHERE product=p_product_id UNION SELECT (x->>'inventory_context_id')::bigint FROM jsonb_array_elements(p_contexts) x) ORDER BY id FOR UPDATE;
    IF coalesce((SELECT jsonb_agg(jsonb_build_object('inventory_context_id',inventory_context,'quantity',quantity) ORDER BY inventory_context)
      FROM eshop.product_inventory_contexts WHERE product=p_product_id),'[]') =
      coalesce((SELECT jsonb_agg(x ORDER BY (x->>'inventory_context_id')::bigint) FROM jsonb_array_elements(p_contexts) x),'[]') THEN RETURN; END IF;
    PERFORM public.check_batch_product_allocation_immutable_internal(ARRAY[p_product_id]);
    -- If permission check passes, proceed with the update.
    -- First, remove all existing inventory context associations.
    DELETE FROM eshop.product_inventory_contexts
    WHERE product = p_product_id;

    -- Then, insert the new associations from the provided JSON array.
    IF jsonb_array_length(p_contexts) > 0 THEN
      INSERT INTO eshop.product_inventory_contexts (product, inventory_context, quantity)
      SELECT
        p_product_id,
        (context ->> 'inventory_context_id')::bigint,
        (context ->> 'quantity')::integer
      FROM jsonb_array_elements(p_contexts) AS context;
    END IF;


    -- After updating the product's context associations, re-run allocations
    -- for all orders that contain this product.
    FOR v_order_id IN
      SELECT DISTINCT opt."order"
      FROM eshop.order_product_ticket opt
      WHERE opt.product = p_product_id ORDER BY opt."order"
    LOOP
      -- This will re-evaluate spot allocations for each affected order.
      PERFORM apply_allocations(v_order_id);
    END LOOP;

    PERFORM public.advance_ticketing_authoring_version_internal_v1('product',v_occasion_id,p_product_id);

END;
$$;
REVOKE ALL ON FUNCTION public.update_product_inventory_contexts_internal_v1(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.update_product_inventory_contexts(p_product_id bigint,p_contexts jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.update_product_inventory_contexts_client_sync_v1(p_product_id,p_contexts,extensions.gen_random_uuid());
END $$;
REVOKE ALL ON FUNCTION public.update_product_inventory_contexts(bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_product_inventory_contexts(bigint,jsonb) TO authenticated;
