DO $$
DECLARE
    v_org_id bigint;
    v_unit_id bigint;
    v_occasion_id bigint;
    v_form_id bigint;
    v_form_key uuid;
    v_product_type_id bigint;
    v_product_deposit_id bigint;
    v_product_nodep_id bigint;
    v_spot_1_id bigint;
    v_spot_2_id bigint;
    v_acc_id bigint;
    v_secret_id bigint;
    v_hidden_id bigint;
    v_occ_start_time timestamptz;
    v_input_data jsonb;
    v_result jsonb;
    v_order_id bigint;
    v_payment_info_id bigint;
    v_transaction_id bigint;
    v_order_state text;
    v_paid numeric;
    v_deposit_amount numeric;
    v_amount numeric;
    v_report jsonb;
    v_report_user uuid;
BEGIN
    -- ==================================================================
    -- Setup: Two products - one with deposit, one without
    -- ==================================================================
    INSERT INTO public.organizations (title) VALUES ('Test Org MixCart') RETURNING id INTO v_org_id;
    INSERT INTO public.units (title, organization) VALUES ('Test Unit MixCart', v_org_id) RETURNING id INTO v_unit_id;
    INSERT INTO eshop.secrets (secret) VALUES ('test_secret_mixcart') RETURNING id INTO v_secret_id;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type)
    VALUES ('Test Bank MixCart', ARRAY['CZK'], v_secret_id, 'FIO') RETURNING id INTO v_acc_id;
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_acc_id, 1);
    INSERT INTO public.occasions_hidden (secret) VALUES ('scan_secret_mixcart') RETURNING id INTO v_hidden_id;

    v_occ_start_time := NOW() + interval '30 days';
    INSERT INTO public.occasions (
        title, unit, link, start_time, end_time, organization,
        data, features, occasion_hidden
    ) VALUES (
        'Test Occasion MixCart', v_unit_id,
        'test-occ-scheduled-' || floor(random()*100000)::text,
        v_occ_start_time, v_occ_start_time + interval '1 day', v_org_id,
        NULL,
        '[{"code": "deposit", "is_enabled": true, "deposit_deadline_days": 7}, {"code": "form", "is_enabled": true, "reminder_is_enabled": true, "reminder_interval_seconds": 259200}]'::jsonb,
        v_hidden_id
    ) RETURNING id INTO v_occasion_id;

    INSERT INTO public.forms (title, occasion, is_open)
    VALUES ('Test Form MixCart', v_occasion_id, true) RETURNING id, key INTO v_form_id, v_form_key;
    INSERT INTO eshop.product_types (title, occasion, type)
    VALUES ('Test PT MixCart', v_occasion_id, 'spot') RETURNING id INTO v_product_type_id;
    INSERT INTO public.form_fields (form, product_type) VALUES (v_form_id, v_product_type_id);

    -- Product A: price 1000, deposit 500
    INSERT INTO eshop.products (title, product_type, currency_code, price, is_hidden, occasion, data)
    VALUES ('Product Deposit MixCart', v_product_type_id, 'CZK', 1000, false, v_occasion_id, '{"deposit": {"amount": 500}}'::jsonb)
    RETURNING id INTO v_product_deposit_id;

    -- Product B: price 800, no deposit
    INSERT INTO eshop.products (title, product_type, currency_code, price, is_hidden, occasion, data)
    VALUES ('Product NoDep MixCart', v_product_type_id, 'CZK', 800, false, v_occasion_id, NULL)
    RETURNING id INTO v_product_nodep_id;

    -- Create spots for each product
    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot Mix 1', v_product_deposit_id, v_occasion_id, gen_random_uuid()) RETURNING id INTO v_spot_1_id;
    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot Mix 2', v_product_nodep_id, v_occasion_id, gen_random_uuid()) RETURNING id INTO v_spot_2_id;

    -- ==================================================================
    -- Step 1: Create mixed-cart order (deposit + non-deposit products)
    -- Note: create_ticket_order validates secret against the first spot only.
    -- We create two separate orders to test the mixed-cart scenario since
    -- each spot has its own secret and the function uses input_data->>'secret'.
    -- ==================================================================

    -- Real checkout with a stale public-form price supplied by the client.
    UPDATE eshop.spots SET product=v_product_deposit_id WHERE id=v_spot_2_id;
    v_input_data := jsonb_build_object('form',v_form_key,'email','before@example.com',
      'secret',(SELECT secret FROM eshop.spots WHERE id=v_spot_1_id),
      'ticket',jsonb_build_array(jsonb_build_object('spot',v_spot_1_id,'price',1000)));
    v_result := public.create_ticket_order(v_input_data);
    PERFORM assert_eq((v_result->>'code')::int,200,'Order before scheduled change');
    v_order_id := (v_result->'order'->>'id')::bigint;
    INSERT INTO eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion)
      VALUES('products.price',v_product_deposit_id,'1200',now()-interval '1 minute',v_occasion_id);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM public.apply_planned_changes();
    PERFORM assert_eq((SELECT price FROM eshop.products WHERE id=v_product_deposit_id),1200::numeric,'Scheduled current price');
    v_input_data := jsonb_build_object('form',v_form_key,'email','after@example.com',
      'secret',(SELECT secret FROM eshop.spots WHERE id=v_spot_2_id),
      'ticket',jsonb_build_array(jsonb_build_object('spot',v_spot_2_id,'price',1000)));
    v_result := public.create_ticket_order(v_input_data);
    PERFORM assert_eq((v_result->>'code')::int,200,'Stale public form checkout succeeds with server price');
    PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=(v_result->'order'->>'id')::bigint),1200::numeric,'New order uses server price');
    PERFORM assert_eq((SELECT amount FROM eshop.payment_info WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=(v_result->'order'->>'id')::bigint)),1200::numeric,'New payment uses server price');
    PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=v_order_id),1000::numeric,'Existing order price stays fixed');
    PERFORM assert_eq((SELECT amount FROM eshop.payment_info WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=v_order_id)),1000::numeric,'Existing payment stays fixed');
    PERFORM assert_eq((SELECT price FROM eshop.orders_history WHERE "order"=v_order_id ORDER BY id LIMIT 1),1000::numeric,'Existing history stays fixed');
END $$;
