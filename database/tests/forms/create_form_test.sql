-- Test: create_form
-- Goal: Verify that create_form function asserts uniqueness, creates form, default fields, and product.
-- Every new form owns a fresh primary 'spot' group; it never shares another form's stock (#960).

DO $$
DECLARE
    v_actor uuid;
    v_org_id bigint;
    v_unit_id bigint;
    v_occasion_id bigint;
    v_form_json jsonb;
    v_form_id bigint;
    v_field_count int;
    v_product_count int;
    v_first_type bigint;
    v_first_products jsonb;
    v_orphan_type bigint;
    v_second_json jsonb;
    v_second_form_id bigint;
    v_second_type bigint;
    v_first_product bigint;
    v_second_product bigint;
    v_checkout_order bigint;
    v_checkout jsonb;
    v_result jsonb;
BEGIN
    -- 1. Setup Isolated Data
    -- Create temporary Org/Unit/Occasion to avoid polluting real data (e.g. Occasion 1)
    INSERT INTO public.organizations (title) VALUES ('Temp Test Org Form') RETURNING id INTO v_org_id;
    INSERT INTO public.units (organization, title) VALUES (v_org_id, 'Temp Test Unit Form') RETURNING id INTO v_unit_id;
    INSERT INTO public.occasions (unit, organization, title, link, start_time, end_time) 
    VALUES (v_unit_id, v_org_id, 'Temp Occasion Form', 'temp-occasion-form-' || floor(random()*100000)::text, now(), now() + interval '1 day') 
    RETURNING id INTO v_occasion_id;

    PERFORM public.create_user_for_test('create-form-manager','create-form-manager@example.invalid');
    v_actor:=public.get_user_id('create-form-manager');
    INSERT INTO public.unit_users(unit,"user",is_editor,is_manager) VALUES(v_unit_id,v_actor,true,true);
    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);

    -- 2. Execute: Create Form
    SELECT create_form(v_occasion_id, 'test-form-link-unique-' || floor(random()*100000)::text, 'Test Form Title') 
    INTO v_form_json;

    -- 3. Verify: Form Created
    v_form_id := (v_form_json->>'id')::bigint;
    PERFORM assert_not_null(v_form_id, 'Form ID should be returned');
    PERFORM assert_eq((v_form_json->>'link')::text, (v_form_json->>'link')::text, 'Link should match'); 
    PERFORM assert_true(NOT (v_form_json->'data' ? 'communication_tone'),
        'New form should inherit the unit tone, not snapshot it');
    PERFORM assert_eq(public.get_effective_form_data(v_form_id)->>'communication_tone',
        'formal', 'A new unit without a tone should default to formal');

    UPDATE public.units SET data = jsonb_build_object('communication_tone', 'informal')
    WHERE id = v_unit_id;
    PERFORM assert_eq(public.get_effective_form_data(v_form_id)->>'communication_tone',
        'informal', 'An inherited form should follow a later unit change');

    UPDATE public.forms SET data = data || '{"communication_tone":"formal"}'::jsonb
    WHERE id = v_form_id;
    PERFORM assert_eq(public.get_effective_form_data(v_form_id)->>'communication_tone',
        'formal', 'An explicit form setting should override its unit');

    UPDATE public.forms SET data = data - 'communication_tone'
    WHERE id = v_form_id;
    PERFORM assert_eq(public.get_effective_form_data(v_form_id)->>'communication_tone',
        'informal', 'Removing the override should resume inheritance');
    
    -- 4. Verify: Default Fields Created (email, ticket, spot)
    SELECT count(*) INTO v_field_count FROM public.form_fields WHERE form = v_form_id;
    PERFORM assert_eq(v_field_count, 3, 'Should create 3 default fields');

    -- 5. Verify: Spot Product Created
    SELECT count(*) INTO v_product_count 
    FROM eshop.products p 
    JOIN eshop.product_types pt ON p.product_type = pt.id 
    WHERE pt.occasion = v_occasion_id AND pt.type = 'spot';
    
    PERFORM assert_true(v_product_count >= 1, 'Spot product should exist');

    -- 6. First form in an empty occasion: exactly one primary group with one starter variant.
    SELECT ff.product_type INTO v_first_type FROM public.form_fields ff
    WHERE ff.form = v_form_id AND ff.type = 'product_type' AND ff.is_ticket_field;
    PERFORM assert_not_null(v_first_type, 'First form binds its primary group');
    PERFORM assert_eq((SELECT count(*) FROM eshop.product_types WHERE occasion = v_occasion_id AND type = 'spot'),
        1::bigint, 'First form creates one primary group');
    PERFORM assert_eq((SELECT jsonb_agg(jsonb_build_array(title, price, currency_code)) FROM eshop.products
        WHERE product_type = v_first_type), '[["Variant 1", 100, "CZK"]]'::jsonb, 'First form gets the starter variant');

    -- Emulate a live offer: a renamed, capacity-limited variant, plus an unrelated empty spot group.
    UPDATE eshop.products SET title = 'Live admission', price = 250, maximum = 40 WHERE product_type = v_first_type;
    SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) INTO v_first_products FROM eshop.products p WHERE p.product_type = v_first_type;
    INSERT INTO eshop.product_types(title, type, occasion) VALUES ('Orphan', 'spot', v_occasion_id)
    RETURNING id INTO v_orphan_type;

    -- 7. A second form in the same occasion owns a fresh group and starter variant.
    SELECT create_form(v_occasion_id, 'test-form-second-' || floor(random()*100000)::text, 'Second Form')
    INTO v_second_json;
    v_second_form_id := (v_second_json->>'id')::bigint;
    SELECT ff.product_type INTO v_second_type FROM public.form_fields ff
    WHERE ff.form = v_second_form_id AND ff.type = 'product_type' AND ff.is_ticket_field;
    PERFORM assert_not_null(v_second_type, 'Second form binds its primary group');
    PERFORM assert_true(v_second_type NOT IN (v_first_type, v_orphan_type),
        'Second form must not reuse an existing spot group');
    PERFORM assert_eq((SELECT jsonb_build_array(title, type, occasion) FROM eshop.product_types WHERE id = v_second_type),
        jsonb_build_array('Spot', 'spot', v_occasion_id), 'Second form group uses the canonical defaults');
    PERFORM assert_eq((SELECT jsonb_agg(jsonb_build_array(title, price, currency_code, occasion)) FROM eshop.products
        WHERE product_type = v_second_type), jsonb_build_array(jsonb_build_array('Variant 1', 100, 'CZK', v_occasion_id)),
        'Second form gets its own starter variant');

    -- 8. Existing offers stay untouched.
    PERFORM assert_eq((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM eshop.products p WHERE p.product_type = v_first_type),
        v_first_products, 'First form products, price and capacity stay unchanged');
    PERFORM assert_eq((SELECT ff.product_type FROM public.form_fields ff
        WHERE ff.form = v_form_id AND ff.type = 'product_type' AND ff.is_ticket_field), v_first_type,
        'First form keeps its own primary group');
    PERFORM assert_false(EXISTS(SELECT 1 FROM public.form_fields WHERE form = v_second_form_id AND product_type = v_first_type),
        'Second form has no field bound to the first form group');
    PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.products WHERE product_type = v_orphan_type),
        'An unrelated empty spot group is neither adopted nor filled');
    PERFORM assert_eq((SELECT count(*) FROM eshop.product_types WHERE occasion = v_occasion_id AND type = 'spot'),
        3::bigint, 'Each form creation adds exactly one primary group');

    -- Exercise checkout against both forms' independently created variants.
    SELECT id INTO STRICT v_first_product FROM eshop.products WHERE product_type = v_first_type;
    UPDATE eshop.products SET price = 0 WHERE product_type = v_second_type RETURNING id INTO v_second_product;
    UPDATE public.forms SET is_open = true WHERE id = v_second_form_id;
    v_checkout_order := public.allocate_ticket_order_identity_internal(v_second_form_id);
    v_checkout := jsonb_build_object(
        'form', v_second_json->>'key', 'secret', gen_random_uuid(), 'email', 'new-form@example.invalid',
        'fields', '[]'::jsonb,
        'ticket', jsonb_build_array(jsonb_build_object('fields',
            jsonb_build_array(jsonb_build_object('product_type', v_first_product)))));
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', 'anon', true);
    v_result := public.finalize_ticket_order_internal_v1(v_checkout_order, v_checkout);
    PERFORM assert_eq(v_result->>'errorCode', 'PRODUCT_SCOPE_MISMATCH',
        'A checkout cannot select the other form''s live variant: '||v_result::text);
    v_checkout := jsonb_set(v_checkout, '{ticket,0,fields,0,product_type}', to_jsonb(v_second_product));
    v_result := public.finalize_ticket_order_internal_v1(v_checkout_order, v_checkout);
    PERFORM assert_eq(v_result->>'code', '200', 'Checkout can sell its own variant: '||v_result::text);
    PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.order_product_ticket
        WHERE "order" = v_checkout_order AND product = v_second_product),
        'The new order has the new form''s variant');
    PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.order_product_ticket
        WHERE product = v_first_product), 'The original live stock stays untouched');

    -- ROLLBACK handles cleanup, but using isolated IDs prevents leak if commit happens accidentally
END;
$$ LANGUAGE plpgsql;
