DROP FUNCTION IF EXISTS public.update_product(JSONB);

CREATE OR REPLACE FUNCTION public.update_product(p_input JSONB)
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
BEGIN
  -- Extract product id from the input JSON
  v_product_id := (p_input->>'id')::BIGINT;

  -- Try to find the product to determine if we are updating or creating.
  -- This also gets the *current* occasion for the permission check on UPDATE.
  IF v_product_id IS NOT NULL THEN
    SELECT pt.occasion, p.price
    INTO v_occasion_id, v_existing_price
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
      AND change_type='products.price' AND NOT applied) AND (
      NULLIF(p_input->>'occasion','')::bigint IS DISTINCT FROM v_occasion_id AND p_input->>'occasion' IS NOT NULL
      OR NULLIF(p_input->>'product_type','')::bigint IS DISTINCT FROM
        (SELECT product_type FROM eshop.products WHERE id=v_product_id) AND p_input->>'product_type' IS NOT NULL
    ) THEN RAISE EXCEPTION 'CANCEL_PRICE_CHANGES_BEFORE_PRODUCT_MOVE'; END IF;

    -- Update only the fields that are provided in the input JSON.
    -- COALESCE is used to keep the existing value if a new one isn't provided.
    -- NULLIF is added to safely handle empty strings '' during casting.
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

    -- Return the ID of the updated product on success.
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
    RETURN v_product_id;

  END IF;
END;
$$;