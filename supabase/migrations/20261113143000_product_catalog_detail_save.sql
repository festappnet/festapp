-- Catalog details remain editable on existing seated forms; every save advances its version.
-- Source: database/functions/eshop/update_product.sql

CREATE OR REPLACE FUNCTION public.update_product_internal_v1(p_input JSONB)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_product_id BIGINT;
  v_occasion_id BIGINT;
  v_product_type_id BIGINT;
  v_existing_price NUMERIC;
  v_input_price NUMERIC;
  v_effective_price NUMERIC;
  v_input_deposit NUMERIC;
  v_existing_hidden boolean;
  v_existing_type bigint;
  v_primary_forms bigint[];
  v_primary_form bigint;
BEGIN
  -- Extract product id from the input JSON
  v_product_id := (p_input->>'id')::BIGINT;

  -- Try to find the product to determine if we are updating or creating.
  -- This also gets the *current* occasion for the permission check on UPDATE.
  IF v_product_id IS NOT NULL THEN
    SELECT pt.occasion, p.price, p.is_hidden, p.product_type
    INTO v_occasion_id, v_existing_price, v_existing_hidden, v_existing_type
    FROM eshop.products p
    JOIN eshop.product_types pt ON p.product_type = pt.id
    WHERE p.id = v_product_id FOR UPDATE OF p;
  END IF;

  -- CASE 1: Product was found (v_product_id was not null and existed)
  IF FOUND THEN
    -- We are UPDATING.

    -- Ensure the caller has permission to edit this product's *current* occasion.
    -- This function is expected to raise an exception on failure.
    PERFORM public.check_is_editor_order_on_occasion(v_occasion_id);

    SELECT coalesce(array_agg(DISTINCT ff.form),'{}'::bigint[]) INTO v_primary_forms
    FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type
    JOIN eshop.products p ON p.product_type=pt.id
    WHERE p.id=v_product_id AND pt.type='spot';

    -- VALIDATION: deposit amount must be less than effective price (input price overrides existing)
    v_input_price := NULLIF(p_input->>'price', '')::NUMERIC;
    v_effective_price := COALESCE(v_input_price, v_existing_price);
    v_input_deposit := NULLIF(p_input->'data'->'deposit'->>'amount', '')::NUMERIC;
    IF v_input_deposit IS NOT NULL AND v_input_deposit > 0
       AND v_effective_price IS NOT NULL AND v_input_deposit >= v_effective_price THEN
      RAISE EXCEPTION '%', jsonb_build_object(
          'code', 'DEPOSIT_AMOUNT_TOO_HIGH',
          'message', 'Deposit amount (' || v_input_deposit || ') must be less than price (' || v_effective_price || ').'
      )::text;
    END IF;

    PERFORM public.validate_product_price_update(v_product_id,v_effective_price,
      COALESCE(p_input->'data',(SELECT data FROM eshop.products WHERE id=v_product_id)),
      COALESCE(p_input->>'currency_code',(SELECT currency_code FROM eshop.products WHERE id=v_product_id)));
    -- A product with schedules cannot silently move to another occasion/type.
    IF EXISTS (SELECT 1 FROM eshop.planned_changes WHERE subject_id=v_product_id
      AND change_type IN('products.price','products.is_hidden') AND NOT applied) AND (
      NULLIF(p_input->>'occasion','')::bigint IS DISTINCT FROM v_occasion_id AND p_input->>'occasion' IS NOT NULL
      OR NULLIF(p_input->>'product_type','')::bigint IS DISTINCT FROM
        (SELECT product_type FROM eshop.products WHERE id=v_product_id) AND p_input->>'product_type' IS NOT NULL
    ) THEN RAISE EXCEPTION 'CANCEL_PRICE_CHANGES_BEFORE_PRODUCT_MOVE'; END IF;

    IF p_input->>'product_type' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.product_types WHERE id=(p_input->>'product_type')::bigint AND occasion=v_occasion_id) THEN RAISE EXCEPTION 'Product type occasion mismatch'; END IF;
    IF p_input->>'occasion' IS NOT NULL AND (p_input->>'occasion')::bigint<>v_occasion_id THEN RAISE EXCEPTION 'Product occasion cannot change'; END IF;
    -- Update only the fields that are provided in the input JSON.
    -- COALESCE is used to keep the existing value if a new one isn't provided.
    -- NULLIF is added to safely handle empty strings '' during casting.
    PERFORM 1 FROM public.occasions WHERE id=v_occasion_id FOR UPDATE;
    IF p_input ? 'product_type' AND NULLIF(p_input->>'product_type','')::bigint IS DISTINCT FROM (SELECT product_type FROM eshop.products WHERE id=v_product_id)
      AND EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE product=v_product_id)
    THEN RAISE EXCEPTION 'Purchased product type cannot change'; END IF;
    IF nullif(p_input->>'maximum','')::integer>0 AND
      nullif(p_input->>'maximum','')::integer<(SELECT count(*) FROM eshop.order_product_ticket WHERE product=v_product_id) THEN
      RAISE EXCEPTION 'PRODUCT_CAPACITY_BELOW_COMMITTED'; END IF;
    UPDATE eshop.products p
    SET
      occasion      = COALESCE(NULLIF(p_input->>'occasion', '')::BIGINT, p.occasion),
      title         = COALESCE(p_input->>'title',         p.title),
      description   = COALESCE(p_input->>'description',   p.description),
      price         = COALESCE(NULLIF(p_input->>'price', '')::NUMERIC, p.price),
      currency_code = COALESCE(p_input->>'currency_code', p.currency_code),
      data          = COALESCE(p_input->'data',           p.data),
      product_type  = COALESCE(NULLIF(p_input->>'product_type', '')::BIGINT, p.product_type),
      "order"       = COALESCE(NULLIF(p_input->>'order', '')::INT,  p."order"),
      maximum       = COALESCE(NULLIF(p_input->>'maximum', '')::INT, p.maximum),
      is_hidden     = COALESCE(NULLIF(p_input->>'is_hidden', '')::BOOLEAN, p.is_hidden),
      updated_at    = NOW()
    WHERE p.id = v_product_id;

    -- Catalog details do not change form structure. Older seated forms may
    -- retain a hidden catalog field; only visibility/type edits can remove
    -- their primary offer and need the structural guard.
    IF COALESCE(NULLIF(p_input->>'is_hidden','')::boolean,v_existing_hidden)
         IS DISTINCT FROM v_existing_hidden
      OR COALESCE(NULLIF(p_input->>'product_type','')::bigint,v_existing_type)
         IS DISTINCT FROM v_existing_type THEN
      FOREACH v_primary_form IN ARRAY v_primary_forms LOOP
        PERFORM public.assert_form_primary_products_internal(v_primary_form);
      END LOOP;
    END IF;

    -- Return the ID of the updated product on success.
    IF p_input ? 'inventory_contexts' THEN
      PERFORM public.update_product_inventory_contexts_internal_v1(v_product_id,p_input->'inventory_contexts');
    END IF;
    IF NOT (p_input ? 'inventory_contexts') THEN
      PERFORM public.advance_ticketing_authoring_version_internal_v1('product',v_occasion_id,v_product_id);
    END IF;
    PERFORM public.notification_center_product_capacity_internal(v_product_id);
    PERFORM public.enqueue_wallet_scope_internal(v_occasion_id);
    RETURN v_product_id;

  -- CASE 2: Product was NOT found (v_product_id was NULL or was an ID that doesn't exist)
  ELSE
    -- We are CREATING, as per the request.

    -- 1. Get the product_type from the JSON.
    v_product_type_id := (p_input->>'product_type')::BIGINT;

    -- 2. Validate product_type is provided (it's required for creation).
    IF v_product_type_id IS NULL THEN
      RAISE EXCEPTION '%', jsonb_build_object(
          'code', 'PRD422',
          'message', 'Field "product_type" is required when creating a new product.'
      )::text;
    END IF;

    -- 3. Find the occasion for the *new* product_type to check permissions.
    SELECT occasion
    INTO v_occasion_id
    FROM eshop.product_types
    WHERE id = v_product_type_id;

    -- 4. Handle invalid product_type.
    IF NOT FOUND THEN
      RAISE EXCEPTION '%', jsonb_build_object(
          'code', 'PTY404',
          'message', 'Product type with ID ' || v_product_type_id || ' not found.'
      )::text;
    END IF;

    -- 5. Ensure the caller has permission to create a product on this occasion.
    PERFORM public.check_is_editor_order_on_occasion(v_occasion_id);

    -- 6. VALIDATION: deposit amount must be less than price (both from input on CREATE)
    v_input_price := NULLIF(p_input->>'price', '')::NUMERIC;
    v_input_deposit := NULLIF(p_input->'data'->'deposit'->>'amount', '')::NUMERIC;
    IF v_input_deposit IS NOT NULL AND v_input_deposit > 0
       AND v_input_price IS NOT NULL AND v_input_deposit >= v_input_price THEN
      RAISE EXCEPTION '%', jsonb_build_object(
          'code', 'DEPOSIT_AMOUNT_TOO_HIGH',
          'message', 'Deposit amount (' || v_input_deposit || ') must be less than price (' || v_input_price || ').'
      )::text;
    END IF;

    PERFORM public.validate_product_price(v_input_price,p_input->'data',p_input->>'currency_code');

    -- 7. Insert the new product.
    -- We ignore the `id` from the JSON (v_product_id) and let the sequence generate a new one.
    -- We use NULLIF to safely cast potentially empty strings.
    INSERT INTO eshop.products (
      occasion,
      title,
      description,
      price,
      currency_code,
      data,
      product_type,
      "order",
      maximum,
      is_hidden
      -- created_at and updated_at are assumed to have defaults (e.g., NOW())
    )
    VALUES (
      v_occasion_id,
      p_input->>'title',
      p_input->>'description',
      NULLIF(p_input->>'price', '')::NUMERIC,
      p_input->>'currency_code',
      p_input->'data',
      v_product_type_id, -- We already extracted and validated this
      NULLIF(p_input->>'order', '')::INT,
      NULLIF(p_input->>'maximum', '')::INT,
      -- Default to 'false' if is_hidden is not provided on create
      COALESCE(NULLIF(p_input->>'is_hidden', '')::BOOLEAN, false)
    )
    RETURNING id INTO v_product_id; -- Get the newly created ID

    -- Return the ID of the newly created product.
    IF p_input ? 'inventory_contexts' THEN
      PERFORM public.update_product_inventory_contexts_internal_v1(v_product_id,p_input->'inventory_contexts');
    END IF;
    IF NOT (p_input ? 'inventory_contexts') THEN
      PERFORM public.advance_ticketing_authoring_version_internal_v1('product',v_occasion_id,v_product_id);
    END IF;
    PERFORM public.notification_center_product_capacity_internal(v_product_id);
    PERFORM public.enqueue_wallet_scope_internal(v_occasion_id);
    RETURN v_product_id;

  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.update_product_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.update_product(p_input jsonb)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 RETURN (public.update_product_client_sync_v1(p_input,extensions.gen_random_uuid())->'data'->>'productId')::bigint;
END $$;
REVOKE ALL ON FUNCTION public.update_product(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_product(jsonb) TO authenticated;

-- Source: database/functions/eshop/update_product_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.update_product_client_sync_v1(p_product jsonb, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_product bigint; v_occasion bigint;
  v_begin jsonb; v_hash text; v_users uuid[]; v_version bigint; v_expected bigint;
BEGIN
  IF p_product IS NULL OR jsonb_typeof(p_product)<>'object'
    OR octet_length(p_product::text)>524288 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid product aggregate'; END IF;
  v_product:=NULLIF(p_product->>'id','')::bigint;
  SELECT occasion INTO v_occasion FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=v_actor AND command_name='inventory.product.save';
  IF NOT FOUND THEN
  IF v_product IS NOT NULL THEN
    SELECT p.occasion INTO v_occasion FROM eshop.products p WHERE p.id=v_product;
  ELSE
    SELECT pt.occasion INTO v_occasion FROM eshop.product_types pt
      WHERE pt.id=NULLIF(p_product->>'product_type','')::bigint;
  END IF;
  END IF;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.can_write_orders(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  IF jsonb_typeof(p_product->'inventory_contexts')='array' THEN
    p_product:=jsonb_set(p_product,'{inventory_contexts}',coalesce((SELECT jsonb_agg(c ORDER BY (c->>'inventory_context_id')::bigint)
      FROM jsonb_array_elements(p_product->'inventory_contexts') c),'[]')); END IF;
  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_occasion]);
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'product',p_product)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.product.save',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_product IS NOT NULL THEN
    SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
    FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
      ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
    WHERE opt.product=v_product;
  ELSE v_users:='{}'::uuid[]; END IF;
  -- Context replacement recalculates allocations: acquire the same outer order
  -- parents before saving a product, never product then order in this command.
  PERFORM public.lock_primary_product_forms_internal(v_product);
  PERFORM public.lock_product_order_dependencies_internal_v1(v_product);
  IF v_product IS NOT NULL THEN
    PERFORM 1 FROM eshop.products WHERE id=v_product AND occasion=v_occasion FOR UPDATE;
    SELECT coalesce(v.version,0) INTO v_version FROM (SELECT 1) seed
    LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='product'
    AND v.scope_type='occasion' AND v.scope_id=v_occasion AND v.aggregate_id=v_product::text;
    -- Released scalar facades may omit this control until their explicit upgrade gate.
    v_expected:=CASE WHEN p_product ? 'expected_aggregate_version'
      THEN (p_product->>'expected_aggregate_version')::bigint ELSE v_version END;
    IF v_expected IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
        jsonb_build_object('productId',v_product,'aggregate_version',v_version)); END IF;
  ELSIF p_product->>'expected_aggregate_version' IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new product cannot have expected version';
  END IF;
  v_product:=public.update_product_internal_v1(p_product-'expected_aggregate_version');
  -- Replacing unchanged contexts is a no-op, but saving catalog details must
  -- still invalidate the original editor snapshot and return a numeric version.
  IF coalesce((SELECT version FROM public.client_aggregate_versions
    WHERE aggregate_type='product' AND scope_type='occasion'
      AND scope_id=v_occasion AND aggregate_id=v_product::text),0)=coalesce(v_version,0) THEN
    PERFORM public.advance_ticketing_authoring_version_internal_v1('product',v_occasion,v_product);
  END IF;
  PERFORM public.assert_form_seating_source_internal(id) FROM public.forms WHERE occasion=v_occasion;
  SELECT version INTO v_version FROM public.client_aggregate_versions WHERE aggregate_type='product'
    AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id=v_product::text;
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.product.save',jsonb_build_array(jsonb_build_object(
      'entityType','product','entityId',v_product,'operation',
      CASE WHEN p_product->>'id' IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_product->>'title',240),'changedFields',jsonb_build_array(
        'configuration','contexts'))),v_users,jsonb_build_object('productId',v_product,'aggregate_version',v_version));
END; $function$;
REVOKE ALL ON FUNCTION public.update_product_client_sync_v1(jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_product_client_sync_v1(jsonb,uuid) TO authenticated;
