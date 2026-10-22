-- Test: deposit payment status transitions
-- Goal: Verify order payment status changes correctly based on deposit threshold

DO $$
DECLARE
    v_unit_id bigint;
    v_occasion_id bigint;
    v_form_id bigint;
    v_form_key uuid;
    v_product_type_id bigint;
    v_product_id bigint;
    v_spot_a_id bigint;
    v_spot_b_id bigint;
    v_spot_c_id bigint;
    v_spot_d_id bigint;
    v_acc_id bigint;
    v_secret_id bigint;
    v_input_data jsonb;
    v_result jsonb;
    v_order_id bigint;
    v_payment_info_id bigint;
    v_transaction_id bigint;
    v_order_state text;
    v_paid numeric;
BEGIN
    -- ==================================================================
    -- Setup: Create test environment with deposit product
    -- ==================================================================

    -- Create Org & Unit
    INSERT INTO public.organizations (title) VALUES ('Test Org Status') RETURNING id INTO v_unit_id;
    INSERT INTO public.units (title, organization) VALUES ('Test Unit Status', v_unit_id) RETURNING id INTO v_unit_id;

    -- Create Bank Account (CZK)
    INSERT INTO eshop.secrets (secret) VALUES ('test_secret_status') RETURNING id INTO v_secret_id;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type)
    VALUES ('Test Bank Status', ARRAY['CZK'], v_secret_id, 'FIO') RETURNING id INTO v_acc_id;

    -- Link Bank Account to Unit
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_acc_id, 1);

    -- Create Occasion
    INSERT INTO public.occasions (organization, title, unit, link, start_time, end_time)
    VALUES ((SELECT organization FROM public.units WHERE id=v_unit_id), 'Test Occasion Status', v_unit_id, 'test-occ-status-' || floor(random()*100000)::text, now(), now() + interval '1 day')
    RETURNING id INTO v_occasion_id;

    -- Create Form (Open)
    INSERT INTO public.forms (title, occasion, is_open)
    VALUES ('Test Form Status', v_occasion_id, true)
    RETURNING id, key INTO v_form_id, v_form_key;

    -- Create Product Type (Spot)
    INSERT INTO eshop.product_types (title, occasion, type)
    VALUES ('Test PT Status', v_occasion_id, 'spot')
    RETURNING id INTO v_product_type_id;

    -- Link Product Type to Form
    INSERT INTO public.form_fields (form, product_type) VALUES (v_form_id, v_product_type_id);

    -- Create Product with deposit (price: 1000, deposit: 500)
    INSERT INTO eshop.products (title, product_type, currency_code, price, is_hidden, occasion, data)
    VALUES ('Product Status Test', v_product_type_id, 'CZK', 1000, false, v_occasion_id, '{"deposit": {"amount": 500}}'::jsonb)
    RETURNING id INTO v_product_id;

    -- Create Spots for each scenario
    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot Status A', v_product_id, v_occasion_id, gen_random_uuid())
    RETURNING id INTO v_spot_a_id;

    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot Status B', v_product_id, v_occasion_id, gen_random_uuid())
    RETURNING id INTO v_spot_b_id;

    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot Status C', v_product_id, v_occasion_id, gen_random_uuid())
    RETURNING id INTO v_spot_c_id;

    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot Status D', v_product_id, v_occasion_id, gen_random_uuid())
    RETURNING id INTO v_spot_d_id;

    -- ==================================================================
    -- Scenario A: Pay deposit amount (500) -> order becomes 'paid'
    -- ==================================================================

    -- Create order
    v_input_data := jsonb_build_object(
        'form', v_form_key,
        'email', 'test-status-a@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_a_id),
        'ticket', jsonb_build_array(
            jsonb_build_object('spot', v_spot_a_id)
        )
    );

    SELECT create_ticket_order(v_input_data) INTO v_result;
    v_order_id := (v_result->'order'->>'id')::bigint;
    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id = v_order_id;

    -- Verify initial state
    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    PERFORM assert_eq(v_order_state, 'ordered', 'Scenario A: Initial order state should be ordered');

    -- Create transaction for deposit amount (500)
    INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
    VALUES (99001, now(), 500, 'CZK', v_acc_id, (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_payment_info_id)::text)
    RETURNING id INTO v_transaction_id;

    -- Link transaction to payment_info
    PERFORM public.apply_transaction_pairing(v_transaction_id, v_payment_info_id, 'test', 'system');

    -- Verify order became 'paid'
    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    PERFORM assert_eq(v_order_state, 'paid', 'Scenario A: Order state should be paid after deposit payment');

    SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_eq(v_paid, 500::numeric, 'Scenario A: payment_info.paid should be 500');

    -- ==================================================================
    -- Scenario B: Pay full amount at once (1000) -> order becomes 'paid'
    -- ==================================================================

    -- Create new order
    v_input_data := jsonb_build_object(
        'form', v_form_key,
        'email', 'test-status-b@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_b_id),
        'ticket', jsonb_build_array(
            jsonb_build_object('spot', v_spot_b_id)
        )
    );

    SELECT create_ticket_order(v_input_data) INTO v_result;
    v_order_id := (v_result->'order'->>'id')::bigint;
    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id = v_order_id;

    -- Create transaction for full amount (1000)
    INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
    VALUES (99002, now(), 1000, 'CZK', v_acc_id, (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_payment_info_id)::text)
    RETURNING id INTO v_transaction_id;

    -- Link transaction to payment_info
    PERFORM public.apply_transaction_pairing(v_transaction_id, v_payment_info_id, 'test', 'system');

    -- Verify order became 'paid'
    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    PERFORM assert_eq(v_order_state, 'paid', 'Scenario B: Order state should be paid after full payment');

    SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_eq(v_paid, 1000::numeric, 'Scenario B: payment_info.paid should be 1000');

    -- ==================================================================
    -- Scenario C: Partial payment below deposit (300) -> stays 'ordered'
    -- ==================================================================

    -- Create new order
    v_input_data := jsonb_build_object(
        'form', v_form_key,
        'email', 'test-status-c@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_c_id),
        'ticket', jsonb_build_array(
            jsonb_build_object('spot', v_spot_c_id)
        )
    );

    SELECT create_ticket_order(v_input_data) INTO v_result;
    v_order_id := (v_result->'order'->>'id')::bigint;
    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id = v_order_id;

    -- Create transaction for partial amount below deposit (300)
    INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
    VALUES (99003, now(), 300, 'CZK', v_acc_id, (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_payment_info_id)::text)
    RETURNING id INTO v_transaction_id;

    -- Link transaction to payment_info
    PERFORM public.apply_transaction_pairing(v_transaction_id, v_payment_info_id, 'test', 'system');

    -- Verify order still 'ordered'
    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    PERFORM assert_eq(v_order_state, 'ordered', 'Scenario C: Order state should remain ordered with partial payment below deposit');

    SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_eq(v_paid, 300::numeric, 'Scenario C: payment_info.paid should be 300');

    -- ==================================================================
    -- Scenario D: Deposit paid, then remaining (500 + 500) -> stays 'paid'
    -- ==================================================================

    -- Create new order
    v_input_data := jsonb_build_object(
        'form', v_form_key,
        'email', 'test-status-d@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_d_id),
        'ticket', jsonb_build_array(
            jsonb_build_object('spot', v_spot_d_id)
        )
    );

    SELECT create_ticket_order(v_input_data) INTO v_result;
    v_order_id := (v_result->'order'->>'id')::bigint;
    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id = v_order_id;

    -- First payment: deposit (500)
    INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
    VALUES (99004, now(), 500, 'CZK', v_acc_id, (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_payment_info_id)::text)
    RETURNING id INTO v_transaction_id;

    PERFORM public.apply_transaction_pairing(v_transaction_id, v_payment_info_id, 'test', 'system');

    -- Verify order became 'paid' after deposit
    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    PERFORM assert_eq(v_order_state, 'paid', 'Scenario D: Order state should be paid after deposit');

    -- Second payment: remaining (500)
    INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
    VALUES (99005, now(), 500, 'CZK', v_acc_id, (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_payment_info_id)::text)
    RETURNING id INTO v_transaction_id;

    PERFORM public.apply_transaction_pairing(v_transaction_id, v_payment_info_id, 'test', 'system');

    -- Verify order still 'paid' and total paid is 1000
    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    PERFORM assert_eq(v_order_state, 'paid', 'Scenario D: Order state should remain paid after remaining payment');

    SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_eq(v_paid, 1000::numeric, 'Scenario D: payment_info.paid should be 1000 after both payments');

    RAISE NOTICE 'All deposit payment status tests passed!';
END;
$$ LANGUAGE plpgsql;
