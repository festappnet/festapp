-- Test: Full deposit lifecycle integration test
-- Goal: Validate end-to-end flow: order -> deposit payment -> reminder -> remaining payment -> scan
-- Plan: 04-01, Task 1
-- Runner: node web_client/scripts/run_integration_tests.js full_deposit_flow

DO $$
DECLARE
    v_org_id bigint;
    v_unit_id bigint;
    v_occasion_id bigint;
    v_form_id bigint;
    v_form_key uuid;
    v_product_type_id bigint;
    v_product_id bigint;
    v_spot_id bigint;
    v_acc_id bigint;
    v_secret_id bigint;
    v_hidden_id bigint;
    v_scan_code text;
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
    v_ticket_symbol text;
    v_scan_result jsonb;
    v_deposit_info jsonb;
    v_reminder_count bigint;
BEGIN
    -- ==================================================================
    -- Setup: Create test environment with deposit product
    -- ==================================================================
    INSERT INTO public.organizations (title) VALUES ('Test Org IntegFlow') RETURNING id INTO v_org_id;
    INSERT INTO public.units (title, organization) VALUES ('Test Unit IntegFlow', v_org_id) RETURNING id INTO v_unit_id;
    INSERT INTO eshop.secrets (secret) VALUES ('test_secret_integflow') RETURNING id INTO v_secret_id;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type)
    VALUES ('Test Bank IntegFlow', ARRAY['CZK'], v_secret_id, 'FIO') RETURNING id INTO v_acc_id;
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_acc_id, 1);
    INSERT INTO public.occasions_hidden (secret) VALUES ('scan_secret_integflow') RETURNING id INTO v_hidden_id;
    v_scan_code := 'scan_secret_integflow';

    v_occ_start_time := NOW() + interval '30 days';
    INSERT INTO public.occasions (
        title, unit, link, start_time, end_time, organization,
        features, occasion_hidden
    ) VALUES (
        'Test Occasion IntegFlow', v_unit_id,
        'test-occ-integflow-' || floor(random()*100000)::text,
        v_occ_start_time, v_occ_start_time + interval '1 day', v_org_id,
        '[{"code": "deposit", "is_enabled": true, "deposit_deadline_days": 7}, {"code": "form", "is_enabled": true, "reminder_is_enabled": true, "reminder_interval_seconds": 259200}]'::jsonb,
        v_hidden_id
    ) RETURNING id INTO v_occasion_id;

    INSERT INTO public.forms (title, occasion, is_open)
    VALUES ('Test Form IntegFlow', v_occasion_id, true) RETURNING id, key INTO v_form_id, v_form_key;
    INSERT INTO eshop.product_types (title, occasion, type)
    VALUES ('Test PT IntegFlow', v_occasion_id, 'spot') RETURNING id INTO v_product_type_id;
    INSERT INTO public.form_fields (form, product_type) VALUES (v_form_id, v_product_type_id);
    INSERT INTO eshop.products (title, product_type, currency_code, price, is_hidden, occasion, data)
    VALUES ('Product IntegFlow', v_product_type_id, 'CZK', 1000, false, v_occasion_id, '{"deposit": {"amount": 500}}'::jsonb)
    RETURNING id INTO v_product_id;
    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot IntegFlow', v_product_id, v_occasion_id, gen_random_uuid()) RETURNING id INTO v_spot_id;

    -- ==================================================================
    -- Step 1: Create order with deposit product
    -- ==================================================================
    v_input_data := jsonb_build_object(
        'form', v_form_key, 'email', 'test-integflow@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_id),
        'ticket', jsonb_build_array(jsonb_build_object('spot', v_spot_id))
    );
    SELECT create_ticket_order(v_input_data) INTO v_result;
    PERFORM assert_eq((v_result->>'code')::int, 200, 'Step 1: Order creation should succeed');
    v_order_id := (v_result->'order'->>'id')::bigint;
    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id = v_order_id;
    SELECT amount, deposit_amount INTO v_amount, v_deposit_amount FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_eq(v_deposit_amount, 500::numeric, 'Step 1: deposit_amount should be 500');
    PERFORM assert_eq(v_amount, 1000::numeric, 'Step 1: amount should be 1000');
    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    PERFORM assert_eq(v_order_state, 'ordered', 'Step 1: Initial state should be ordered');

    -- Verify deposit reminder queued at order creation
    SELECT COUNT(*) INTO v_reminder_count FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id
    AND (data->>'order_id')::bigint = v_order_id;
    PERFORM assert_eq(v_reminder_count, 1::bigint, 'Step 1: Deposit reminder should be queued at order creation');
    RAISE NOTICE 'Step 1 PASSED: Order created, deposit=500, reminder queued';

    -- ==================================================================
    -- Step 2: Pay deposit (500) -> order becomes paid
    -- ==================================================================
    INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
    VALUES (90001, now(), 500, 'CZK', v_acc_id,
        (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_payment_info_id)::text)
    RETURNING id INTO v_transaction_id;
    PERFORM public.apply_transaction_pairing(v_transaction_id, v_payment_info_id, 'test', 'system');

    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    PERFORM assert_eq(v_order_state, 'paid', 'Step 2: Order should be paid after deposit');
    SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_eq(v_paid, 500::numeric, 'Step 2: paid should be 500');

    -- Verify TICKET_ORDER_PAYMENT_DONE email queued (deposit paid)
    PERFORM assert_true(
        EXISTS(SELECT 1 FROM public.email_messages
            WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_PAYMENT_DONE' AND message_kind='order_payment_notice' AND occasion = v_occasion_id
            AND (data->>'order_id')::bigint = v_order_id),
        'Step 2: TICKET_ORDER_PAYMENT_DONE email should be queued'
    );
    RAISE NOTICE 'Step 2 PASSED: Deposit paid, TICKET_ORDER_PAYMENT_DONE email queued';

    -- ==================================================================
    -- Step 3: Deposit reminder still queued (deposit paid, remaining outstanding)
    -- ==================================================================
    SELECT COUNT(*) INTO v_reminder_count FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id
    AND (data->>'order_id')::bigint = v_order_id;
    PERFORM assert_eq(v_reminder_count, 1::bigint, 'Step 3: Deposit reminder should still be queued');
    RAISE NOTICE 'Step 3 PASSED: Deposit reminder still active';

    -- ==================================================================
    -- Step 4: Scan ticket (after deposit only) -> shows remaining outstanding
    -- ==================================================================
    SELECT t.ticket_symbol INTO v_ticket_symbol FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    WHERE opt."order" = v_order_id LIMIT 1;

    SELECT scan_ticket(v_ticket_symbol, v_scan_code) INTO v_scan_result;
    PERFORM assert_eq((v_scan_result->>'code')::int, 200, 'Step 4: Scan should succeed');
    v_deposit_info := v_scan_result->'deposit_info';
    PERFORM assert_true(v_deposit_info IS NOT NULL, 'Step 4: deposit_info should NOT be NULL');
    PERFORM assert_eq((v_deposit_info->>'remaining_amount')::numeric, 500::numeric, 'Step 4: remaining should be 500');
    PERFORM assert_eq((v_deposit_info->>'is_fully_paid')::boolean, false, 'Step 4: is_fully_paid should be false');
    PERFORM assert_eq((v_deposit_info->>'deposit_amount')::numeric, 500::numeric, 'Step 4: deposit_amount should be 500');
    PERFORM assert_eq((v_deposit_info->>'paid_amount')::numeric, 500::numeric, 'Step 4: paid_amount should be 500');
    RAISE NOTICE 'Step 4 PASSED: Scan shows 500 remaining';

    -- ==================================================================
    -- Step 5: Pay remaining (500) -> fully paid
    -- ==================================================================
    INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
    VALUES (90002, now(), 500, 'CZK', v_acc_id,
        (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_payment_info_id)::text)
    RETURNING id INTO v_transaction_id;
    PERFORM public.apply_transaction_pairing(v_transaction_id, v_payment_info_id, 'test', 'system');

    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    PERFORM assert_eq(v_order_state, 'paid', 'Step 5: Order should remain paid');
    SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_eq(v_paid, 1000::numeric, 'Step 5: paid should be 1000');
    RAISE NOTICE 'Step 5 PASSED: Remaining paid, total 1000';

    -- ==================================================================
    -- Step 6: Batch reminder function removes reminder (fully paid)
    -- ==================================================================
    PERFORM queue_payment_reminders(v_occasion_id, 259200);
    SELECT COUNT(*) INTO v_reminder_count FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id;
    PERFORM assert_eq(v_reminder_count, 0::bigint, 'Step 6: No reminder after full payment');
    RAISE NOTICE 'Step 6 PASSED: Reminder cleaned up';

    -- ==================================================================
    -- Step 7: Scan ticket (after full payment) -> shows fully paid
    -- ==================================================================
    SELECT scan_ticket(v_ticket_symbol, v_scan_code) INTO v_scan_result;
    PERFORM assert_eq((v_scan_result->>'code')::int, 200, 'Step 7: Scan should succeed');
    v_deposit_info := v_scan_result->'deposit_info';
    PERFORM assert_eq((v_deposit_info->>'remaining_amount')::numeric, 0::numeric, 'Step 7: remaining should be 0');
    PERFORM assert_eq((v_deposit_info->>'is_fully_paid')::boolean, true, 'Step 7: is_fully_paid should be true');
    PERFORM assert_eq((v_deposit_info->>'paid_amount')::numeric, 1000::numeric, 'Step 7: paid_amount should be 1000');
    RAISE NOTICE 'Step 7 PASSED: Scan shows fully paid';

    RAISE NOTICE '=============================================';
    RAISE NOTICE 'Full deposit lifecycle integration test PASSED!';
    RAISE NOTICE '=============================================';
END;
$$ LANGUAGE plpgsql;
