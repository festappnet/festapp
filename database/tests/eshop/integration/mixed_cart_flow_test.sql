-- Test: Mixed cart integration test with report verification
-- Goal: Validate deposit + full-price products in one order, financial report deposit/remaining split
-- Plan: 04-02, Task 1
-- Runner: node web_client/scripts/run_integration_tests.js mixed_cart_flow

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
        'test-occ-mixcart-' || floor(random()*100000)::text,
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

    -- Order 1: Deposit product (1000, deposit 500)
    v_input_data := jsonb_build_object(
        'form', v_form_key, 'email', 'test-mixcart-1@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_1_id),
        'ticket', jsonb_build_array(jsonb_build_object('spot', v_spot_1_id))
    );
    SELECT create_ticket_order(v_input_data) INTO v_result;
    PERFORM assert_eq((v_result->>'code')::int, 200, 'Step 1a: Deposit order creation should succeed');
    v_order_id := (v_result->'order'->>'id')::bigint;
    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id = v_order_id;
    SELECT amount, deposit_amount INTO v_amount, v_deposit_amount FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_eq(v_amount, 1000::numeric, 'Step 1a: amount should be 1000');
    PERFORM assert_eq(v_deposit_amount, 500::numeric, 'Step 1a: deposit_amount should be 500');

    -- Order 2: Non-deposit product (800, no deposit)
    v_input_data := jsonb_build_object(
        'form', v_form_key, 'email', 'test-mixcart-2@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_2_id),
        'ticket', jsonb_build_array(jsonb_build_object('spot', v_spot_2_id))
    );
    SELECT create_ticket_order(v_input_data) INTO v_result;
    PERFORM assert_eq((v_result->>'code')::int, 200, 'Step 1b: Non-deposit order creation should succeed');
    DECLARE
        v_order_2_id bigint;
        v_pi_2_id bigint;
        v_dep_2 numeric;
        v_amt_2 numeric;
        v_transaction_2_id bigint;
    BEGIN
        v_order_2_id := (v_result->'order'->>'id')::bigint;
        SELECT payment_info INTO v_pi_2_id FROM eshop.orders WHERE id = v_order_2_id;
        SELECT amount, deposit_amount INTO v_amt_2, v_dep_2 FROM eshop.payment_info WHERE id = v_pi_2_id;
        PERFORM assert_eq(v_amt_2, 800::numeric, 'Step 1b: amount should be 800');
        PERFORM assert_true(v_dep_2 IS NULL, 'Step 1b: deposit_amount should be NULL for non-deposit product');
        RAISE NOTICE 'Step 1 PASSED: Deposit order (1000/500) + non-deposit order (800/NULL) created';

        -- ==================================================================
        -- Step 2: Pay deposit on order 1 (500)
        -- ==================================================================
        INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
        VALUES (90201, now(), 500, 'CZK', v_acc_id,
            (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_payment_info_id)::text)
        RETURNING id INTO v_transaction_id;
        PERFORM public.apply_transaction_pairing(v_transaction_id, v_payment_info_id, 'test', 'system');

        SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
        PERFORM assert_eq(v_order_state, 'paid', 'Step 2: Deposit order should be paid after 500');
        RAISE NOTICE 'Step 2 PASSED: Deposit order paid with 500';

        -- ==================================================================
        -- Step 3: Pay remaining on order 1 (500 more = 1000 total)
        -- ==================================================================
        INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
        VALUES (90202, now(), 500, 'CZK', v_acc_id,
            (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_payment_info_id)::text)
        RETURNING id INTO v_transaction_id;
        PERFORM public.apply_transaction_pairing(v_transaction_id, v_payment_info_id, 'test', 'system');

        SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = v_payment_info_id;
        PERFORM assert_eq(v_paid, 1000::numeric, 'Step 3: Order 1 paid should be 1000');

        -- Pay full on order 2 (800)
        INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
        VALUES (90203, now(), 800, 'CZK', v_acc_id,
            (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_pi_2_id)::text)
        RETURNING id INTO v_transaction_2_id;
        PERFORM public.apply_transaction_pairing(v_transaction_2_id, v_pi_2_id, 'test', 'system');

        SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_2_id;
        PERFORM assert_eq(v_order_state, 'paid', 'Step 3: Non-deposit order should be paid');
        RAISE NOTICE 'Step 3 PASSED: Both orders fully paid';

        -- ==================================================================
        -- Step 4: Verify financial report shows deposit/remaining split
        -- ==================================================================
        PERFORM create_user_for_test('report_integration', 'report-integration@test.local');
        v_report_user := get_user_id('report_integration');
        UPDATE public.user_info SET organization=v_org_id WHERE id=v_report_user;
        INSERT INTO public.occasion_users (occasion,"user",is_editor_order_view) VALUES (v_occasion_id,v_report_user,true);
        PERFORM set_config('request.jwt.claim.sub',v_report_user::text,true);
        PERFORM set_config('test.report_link',(SELECT link FROM public.occasions WHERE id=v_occasion_id),true);
        SET LOCAL ROLE authenticated;
        v_report := public.get_report_ws(current_setting('test.report_link',true));
        RESET ROLE;
        PERFORM assert_eq((v_report->>'code')::int,200,'Report succeeds through authorized RPC');
        PERFORM assert_eq((v_report->'report'->'money_by_currency'->0->>'deposit_received_gross')::numeric,
          500::numeric,'Report deposit split');
        PERFORM assert_eq((v_report->'report'->'money_by_currency'->0->>'beyond_deposit_received_gross')::numeric,
          500::numeric,'Report beyond-deposit split excludes non-deposit orders');
        PERFORM assert_eq((v_report->'report'->'money_by_currency'->0->>'received')::numeric,
          1800::numeric,'Report received from payment workflow');

    END;

    RAISE NOTICE '=============================================';
    RAISE NOTICE 'Mixed cart integration test PASSED!';
    RAISE NOTICE '=============================================';
END;
$$ LANGUAGE plpgsql;
