
-- Test: Get Form For Edit Short Title Persistence
-- Verifies that the 'get_form_for_edit' RPC correctly returns the 'data' column (containing 'short_title') for products.

DO $$
DECLARE
    v_actor uuid;
    v_actor_alias text := 'form-short-title-' || gen_random_uuid();
    v_org_id bigint;
    v_unit_id bigint;
    v_occasion_id bigint;
    v_form_id bigint;
    v_product_type_id bigint;
    v_product_id bigint;
    v_response jsonb;
    v_products_json jsonb;
    v_product_record jsonb;
    v_form_link text := 'test-form-' || gen_random_uuid();
    v_occasion_link text := 'test-occ-form-' || gen_random_uuid();
    v_short_title text := 'Form Editor Short Title';
BEGIN
    -- 1. Setup: Create Hierarchy & User context
    
    -- Insert Org
    INSERT INTO public.organizations (title) VALUES ('Form Test Org') RETURNING id INTO v_org_id;
    
    -- Insert Unit
    INSERT INTO public.units (organization, title) VALUES (v_org_id, 'Form Test Unit') RETURNING id INTO v_unit_id;
    
    -- Insert Occasion
    INSERT INTO public.occasions (organization, unit, title, link, start_time, end_time, is_hidden)
    VALUES (v_org_id, v_unit_id, 'Form Test Occasion', v_occasion_link, now(), now() + interval '1 day', false)
    RETURNING id INTO v_occasion_id;

    PERFORM public.create_user_for_test(v_actor_alias,v_actor_alias||'@example.invalid');
    v_actor:=public.get_user_id(v_actor_alias);
    UPDATE public.user_info SET organization=v_org_id WHERE id=v_actor;
    INSERT INTO public.occasion_users(occasion,"user",is_editor_view,is_editor_order_view)
    VALUES(v_occasion_id,v_actor,true,true);
    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);

    -- Insert Form
    INSERT INTO public.forms (occasion, title, link, is_open)
    VALUES (v_occasion_id, 'Test Form', v_form_link, true)
    RETURNING id INTO v_form_id;
    PERFORM public.reserve_public_link_internal('form',v_form_id,v_form_link,true);

    -- 2. CREATE Product Type
    INSERT INTO eshop.product_types (occasion, title, type)
    VALUES (v_occasion_id, 'Test Type', 'other')
    RETURNING id INTO v_product_type_id;

    -- 3. CREATE Product with short_title
    INSERT INTO eshop.products (
        occasion, title, price, currency_code, product_type, data, is_hidden
    ) VALUES (
        v_occasion_id, 'Test Product', 100, 'CZK', v_product_type_id, jsonb_build_object('short_title', v_short_title), false
    ) RETURNING id INTO v_product_id;

    -- 4. TEST RETRIEVAL via get_form_for_edit
    v_response := public.get_form_for_edit(v_form_link);
    
    -- Check response code
    PERFORM assert_eq((v_response->>'code')::int, 200, 'Response code should be 200');
    
    -- Extract products
    v_products_json := v_response->'data'->'products';
    
    -- Check if we found the product
    PERFORM assert_eq(jsonb_array_length(v_products_json), 1, 'Should find 1 product');
    
    v_product_record := v_products_json->0;
    
    -- Verify "data" field exists and contains short_title
    -- Note: We check if `data` is present.
    IF (v_product_record->'data') IS NULL THEN
        RAISE EXCEPTION 'Product JSON is missing the "data" field: %', v_product_record;
    END IF;
    
    PERFORM assert_eq(v_product_record->'data'->>'short_title', v_short_title, 'Short title should be returned in data');

END $$;
