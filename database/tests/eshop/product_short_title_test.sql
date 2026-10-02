
-- Test: Product Short Title Persistence
-- Verifies that the 'short_title' field in the product 'data' JSONB column
-- is correctly saved via 'update_product' and retrieved via 'get_products_and_types_for_edit'.

DO $$
DECLARE
    v_org_id bigint;
    v_unit_id bigint;
    v_occasion_id bigint;
    v_user_id uuid;
    v_product_type_id bigint;
    v_product_id bigint;
    v_result_id bigint;
    v_products_json json;
    v_product_record json;
    v_short_title text;
    v_occasion_link text := 'test-occ-' || gen_random_uuid();
    v_new_short_title text := 'My Short Title';
    v_updated_short_title text := 'Updated Short Title';
BEGIN
    -- 1. Setup: Create Hierarchy & User context
    
    -- 1. Setup: Create Hierarchy
    -- Mocking Permission Functions to bypass Auth/User dependencies
    
    -- Insert Org
    INSERT INTO public.organizations (title) VALUES ('Persistence Test Org') RETURNING id INTO v_org_id;
    
    -- Insert Unit
    INSERT INTO public.units (organization, title) VALUES (v_org_id, 'Persistence Test Unit') RETURNING id INTO v_unit_id;
    
    -- Insert Occasion
    INSERT INTO public.occasions (organization, unit, title, link, start_time, end_time, is_hidden)
    VALUES (v_org_id, v_unit_id, 'Persistence Test Occasion', v_occasion_link, now(), now() + interval '1 day', false)
    RETURNING id INTO v_occasion_id;

    PERFORM create_user_for_test('short_title_editor', 'short-title@test.local');
    v_user_id := get_user_id('short_title_editor');
    UPDATE public.user_info SET organization = v_org_id WHERE id = v_user_id;
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);
    INSERT INTO public.occasion_users (
        occasion, "user", is_editor_order, is_editor_order_view
    ) VALUES (v_occasion_id, v_user_id, true, true);


    -- 2. CREATE Product Type
    INSERT INTO eshop.product_types (occasion, title, type)
    VALUES (v_occasion_id, 'Test Type', 'other')
    RETURNING id INTO v_product_type_id;


    -- 3. TEST CREATION: Create a Product with short_title in 'data'
    -- Using update_product which handles both create (if ID null) and update.
    
    SELECT public.update_product(
        jsonb_build_object(
            'product_type', v_product_type_id,
            'title', 'Original Title',
            'price', 100,
            'currency_code', 'CZK',
            'is_hidden', false,
            'data', jsonb_build_object('short_title', v_new_short_title)
        )
    ) INTO v_product_id;

    PERFORM assert_not_null(v_product_id, 'Product ID should be returned after creation');

    -- Verify directly in table
    SELECT data->>'short_title' INTO v_short_title FROM eshop.products WHERE id = v_product_id;
    PERFORM assert_eq(v_short_title, v_new_short_title, 'Short title should be persisted on creation');


    -- 4. TEST UPDATE: Update the short_title
    SELECT public.update_product(
        jsonb_build_object(
            'id', v_product_id,
            'data', jsonb_build_object('short_title', v_updated_short_title)
        )
    ) INTO v_result_id;
    
    PERFORM assert_eq(v_result_id, v_product_id, 'Product ID should match on update');

    -- Verify directly in table
    SELECT data->>'short_title' INTO v_short_title FROM eshop.products WHERE id = v_product_id;
    PERFORM assert_eq(v_short_title, v_updated_short_title, 'Short title should be updated');


    -- 5. TEST RETRIEVAL: Use the frontend RPC
    SELECT public.get_products_and_types_for_edit(v_occasion_link) INTO v_products_json;
    
    -- Extract the product from the JSON response
    -- The response structure is { products: [ ... ] }
    -- We need to find our product in the array.
    
    -- We can use jsonb_path_query or simply extract the specific element if we know it's the only one.
    -- Since we created a fresh occasion, it should be the only product.
    
    v_product_record := (v_products_json->'products')->0;
    
    PERFORM assert_not_null(v_product_record::text, 'Product should be found in RPC response');
    PERFORM assert_eq((v_product_record->>'id')::bigint, v_product_id, 'Returned product ID should match');
    PERFORM assert_eq(v_product_record->>'short_title', v_updated_short_title, 'RPC should return the correct short_title');


    -- Cleanup (Optional, verifying that dependent deletes work or just leaving it for rollback)
    -- Rollback provided by test runner handles cleanup.

END $$;
