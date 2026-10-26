-- test-setup: database/tests/blueprint/fixtures.sql
-- test-setup: database/tests/helpers/canonical_blueprint_order_fixture.sql
-- Test: backward compatibility with existing orders
-- Goal: Verify orders without deposit continue to work with full price as threshold

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
    v_acc_id bigint;
    v_secret_id bigint;
    v_input_data jsonb;
    v_result jsonb;
    v_order_id bigint;
    v_payment_info_id bigint;
    v_transaction_id bigint;
    v_order_state text;
    v_paid numeric;
    v_deposit_amount numeric;
BEGIN
    -- ==================================================================
    -- Setup: Create test environment WITHOUT deposit product
    -- ==================================================================

    -- Create Org & Unit
    INSERT INTO public.organizations (title) VALUES ('Test Org Compat') RETURNING id INTO v_unit_id;
    INSERT INTO public.units (title, organization) VALUES ('Test Unit Compat', v_unit_id) RETURNING id INTO v_unit_id;

    -- Create Bank Account (CZK)
    INSERT INTO eshop.secrets (secret) VALUES ('test_secret_compat') RETURNING id INTO v_secret_id;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type)
    VALUES ('Test Bank Compat', ARRAY['CZK'], v_secret_id, 'FIO') RETURNING id INTO v_acc_id;

    -- Link Bank Account to Unit
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_acc_id, 1);

    -- Create Occasion
    INSERT INTO public.occasions (organization, title, unit, link, start_time, end_time)
    VALUES ((SELECT organization FROM public.units WHERE id=v_unit_id), 'Test Occasion Compat', v_unit_id, 'test-occ-compat-' || floor(random()*100000)::text, now(), now() + interval '1 day')
    RETURNING id INTO v_occasion_id;

    -- Create Form (Open)
    INSERT INTO public.forms (title, occasion, is_open)
    VALUES ('Test Form Compat', v_occasion_id, true)
    RETURNING id, key INTO v_form_id, v_form_key;

    -- Create Product Type (Spot)
    INSERT INTO eshop.product_types (title, occasion, type)
    VALUES ('Test PT Compat', v_occasion_id, 'spot')
    RETURNING id INTO v_product_type_id;

    -- Link Product Type to Form
    INSERT INTO public.form_fields (form, product_type) VALUES (v_form_id, v_product_type_id);

    -- Create Product WITHOUT deposit (price: 1000, no deposit field)
    INSERT INTO eshop.products (title, product_type, currency_code, price, is_hidden, occasion, data)
    VALUES ('Product No Deposit', v_product_type_id, 'CZK', 1000, false, v_occasion_id, NULL)
    RETURNING id INTO v_product_id;

    -- Create Spots for each scenario
    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot Compat A', v_product_id, v_occasion_id, gen_random_uuid())
    RETURNING id INTO v_spot_a_id;

    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot Compat B', v_product_id, v_occasion_id, gen_random_uuid())
    RETURNING id INTO v_spot_b_id;

    -- ==================================================================
    -- Scenario A: Full payment (1000) -> order becomes 'paid'
    -- ==================================================================

    -- Create order
    v_input_data := jsonb_build_object(
        'form', v_form_key,
        'email', 'test-compat-a@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_a_id),
        'ticket', jsonb_build_array(
            jsonb_build_object('spot', v_spot_a_id)
        )
    );

    v_input_data:=pg_temp.prepare_order_fixture_input(v_input_data);

    SELECT create_ticket_order(v_input_data) INTO v_result;
    v_order_id := (v_result->'order'->>'id')::bigint;
    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id = v_order_id;

    -- Verify deposit_amount is NULL (backward compatible)
    SELECT deposit_amount INTO v_deposit_amount FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_true(v_deposit_amount IS NULL, 'Scenario A: deposit_amount should be NULL for products without deposit');

    -- Verify initial state
    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    PERFORM assert_eq(v_order_state, 'ordered', 'Scenario A: Initial order state should be ordered');

    -- Create transaction for full amount (1000)
    INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
    VALUES (98001, now(), 1000, 'CZK', v_acc_id, (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_payment_info_id)::text)
    RETURNING id INTO v_transaction_id;

    -- Link transaction to payment_info
    PERFORM public.apply_transaction_pairing(v_transaction_id, v_payment_info_id, 'test', 'system');

    -- Verify order became 'paid' only after full payment
    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    PERFORM assert_eq(v_order_state, 'paid', 'Scenario A: Order state should be paid after full payment');

    SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_eq(v_paid, 1000::numeric, 'Scenario A: payment_info.paid should be 1000');

    -- ==================================================================
    -- Scenario B: Partial payment (500 on 1000) -> stays 'ordered'
    -- ==================================================================

    -- Create new order
    v_input_data := jsonb_build_object(
        'form', v_form_key,
        'email', 'test-compat-b@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_b_id),
        'ticket', jsonb_build_array(
            jsonb_build_object('spot', v_spot_b_id)
        )
    );

    v_input_data:=pg_temp.prepare_order_fixture_input(v_input_data);

    SELECT create_ticket_order(v_input_data) INTO v_result;
    v_order_id := (v_result->'order'->>'id')::bigint;
    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id = v_order_id;

    -- Verify deposit_amount is NULL
    SELECT deposit_amount INTO v_deposit_amount FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_true(v_deposit_amount IS NULL, 'Scenario B: deposit_amount should be NULL for products without deposit');

    -- Create transaction for partial amount (500)
    INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
    VALUES (98002, now(), 500, 'CZK', v_acc_id, (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_payment_info_id)::text)
    RETURNING id INTO v_transaction_id;

    -- Link transaction to payment_info
    PERFORM public.apply_transaction_pairing(v_transaction_id, v_payment_info_id, 'test', 'system');

    -- Verify order stays 'ordered' because threshold is full price (1000), not deposit
    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    PERFORM assert_eq(v_order_state, 'ordered', 'Scenario B: Order state should remain ordered with partial payment (threshold = full price)');

    SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_eq(v_paid, 500::numeric, 'Scenario B: payment_info.paid should be 500');

    -- ==================================================================
    -- Scenario C: Complete the partial payment (500 + 500 = 1000) -> becomes 'paid'
    -- ==================================================================

    -- Add another transaction to complete payment
    INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
    VALUES (98003, now(), 500, 'CZK', v_acc_id, (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_payment_info_id)::text)
    RETURNING id INTO v_transaction_id;

    -- Link transaction to payment_info
    PERFORM public.apply_transaction_pairing(v_transaction_id, v_payment_info_id, 'test', 'system');

    -- Now order should become 'paid'
    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    PERFORM assert_eq(v_order_state, 'paid', 'Scenario C: Order state should be paid after completing full payment');

    SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_eq(v_paid, 1000::numeric, 'Scenario C: payment_info.paid should be 1000');

    RAISE NOTICE 'All backward compatibility tests passed!';
END;
$$ LANGUAGE plpgsql;
