-- Test: Overpayment integration test
-- Goal: Validate paying full amount at once triggers TICKET_ORDER_PAYMENT_DONE (fully paid), no deposit reminder
-- Plan: 04-01, Task 2
-- Runner: node web_client/scripts/run_integration_tests.js overpayment_flow

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
    v_ticket_symbol text;
    v_scan_result jsonb;
    v_deposit_info jsonb;
    v_reminder_count bigint;
    v_paid_email_count bigint;
BEGIN
    -- ==================================================================
    -- Setup
    -- ==================================================================
    INSERT INTO public.organizations (title) VALUES ('Test Org Overpay') RETURNING id INTO v_org_id;
    INSERT INTO public.units (title, organization) VALUES ('Test Unit Overpay', v_org_id) RETURNING id INTO v_unit_id;
    INSERT INTO eshop.secrets (secret) VALUES ('test_secret_overpay') RETURNING id INTO v_secret_id;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type)
    VALUES ('Test Bank Overpay', ARRAY['CZK'], v_secret_id, 'FIO') RETURNING id INTO v_acc_id;
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_acc_id, 1);
    INSERT INTO public.occasions_hidden (secret) VALUES ('scan_secret_overpay') RETURNING id INTO v_hidden_id;
    v_scan_code := 'scan_secret_overpay';

    v_occ_start_time := NOW() + interval '30 days';
    INSERT INTO public.occasions (
        title, unit, link, start_time, end_time, organization,
        features, occasion_hidden
    ) VALUES (
        'Test Occasion Overpay', v_unit_id,
        'test-occ-overpay-' || floor(random()*100000)::text,
        v_occ_start_time, v_occ_start_time + interval '1 day', v_org_id,
        '[{"code": "deposit", "is_enabled": true, "deposit_deadline_days": 7}, {"code": "form", "is_enabled": true, "reminder_is_enabled": true, "reminder_interval_seconds": 259200}]'::jsonb,
        v_hidden_id
    ) RETURNING id INTO v_occasion_id;

    INSERT INTO public.forms (title, occasion, is_open)
    VALUES ('Test Form Overpay', v_occasion_id, true) RETURNING id, key INTO v_form_id, v_form_key;
    INSERT INTO eshop.product_types (title, occasion, type)
    VALUES ('Test PT Overpay', v_occasion_id, 'spot') RETURNING id INTO v_product_type_id;
    INSERT INTO public.form_fields (form, product_type) VALUES (v_form_id, v_product_type_id);
    INSERT INTO eshop.products (title, product_type, currency_code, price, is_hidden, occasion, data)
    VALUES ('Product Overpay', v_product_type_id, 'CZK', 1000, false, v_occasion_id, '{"deposit": {"amount": 500}}'::jsonb)
    RETURNING id INTO v_product_id;
    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot Overpay', v_product_id, v_occasion_id, gen_random_uuid()) RETURNING id INTO v_spot_id;

    -- ==================================================================
    -- Step 1: Create order
    -- ==================================================================
    v_input_data := jsonb_build_object(
        'form', v_form_key, 'email', 'test-overpay@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_id),
        'ticket', jsonb_build_array(jsonb_build_object('spot', v_spot_id))
    );
    SELECT create_ticket_order(v_input_data) INTO v_result;
    PERFORM assert_eq((v_result->>'code')::int, 200, 'Step 1: Order creation should succeed');
    v_order_id := (v_result->'order'->>'id')::bigint;
    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id = v_order_id;
    SELECT deposit_amount INTO v_deposit_amount FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_eq(v_deposit_amount, 500::numeric, 'Step 1: deposit_amount should be 500');
    RAISE NOTICE 'Step 1 PASSED: Order created with deposit';

    -- ==================================================================
    -- Step 2: Pay full amount immediately (1000)
    -- ==================================================================
    INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
    VALUES (90101, now(), 1000, 'CZK', v_acc_id,
        (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_payment_info_id)::text)
    RETURNING id INTO v_transaction_id;
    PERFORM public.apply_transaction_pairing(v_transaction_id, v_payment_info_id, 'test', 'system');

    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    PERFORM assert_eq(v_order_state, 'paid', 'Step 2: Order should be paid');
    SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_eq(v_paid, 1000::numeric, 'Step 2: paid should be 1000');

    -- Verify TICKET_ORDER_PAYMENT_DONE email queued (fully paid)
    SELECT COUNT(*) INTO v_paid_email_count FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_PAYMENT_DONE' AND message_kind='order_payment_notice' AND occasion = v_occasion_id
    AND (data->>'order_id')::bigint = v_order_id;
    PERFORM assert_eq(v_paid_email_count, 1::bigint, 'Step 2: TICKET_ORDER_PAYMENT_DONE email should be queued');
    RAISE NOTICE 'Step 2 PASSED: Full payment triggers TICKET_ORDER_PAYMENT_DONE';

    -- ==================================================================
    -- Step 3: No active deposit reminder
    -- ==================================================================
    PERFORM queue_payment_reminders(v_occasion_id, 259200);
    SELECT COUNT(*) INTO v_reminder_count FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id;
    PERFORM assert_eq(v_reminder_count, 0::bigint, 'Step 3: No reminder for fully-paid order');
    RAISE NOTICE 'Step 3 PASSED: No deposit reminder';

    -- ==================================================================
    -- Step 4: Scan ticket shows fully paid
    -- ==================================================================
    SELECT t.ticket_symbol INTO v_ticket_symbol FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    WHERE opt."order" = v_order_id LIMIT 1;

    SELECT scan_ticket(v_ticket_symbol, v_scan_code) INTO v_scan_result;
    PERFORM assert_eq((v_scan_result->>'code')::int, 200, 'Step 4: Scan should succeed');
    v_deposit_info := v_scan_result->'deposit_info';
    PERFORM assert_true(v_deposit_info IS NOT NULL, 'Step 4: deposit_info should NOT be NULL');
    PERFORM assert_eq((v_deposit_info->>'remaining_amount')::numeric, 0::numeric, 'Step 4: remaining should be 0');
    PERFORM assert_eq((v_deposit_info->>'is_fully_paid')::boolean, true, 'Step 4: is_fully_paid should be true');
    PERFORM assert_eq((v_deposit_info->>'paid_amount')::numeric, 1000::numeric, 'Step 4: paid_amount should be 1000');
    PERFORM assert_eq((v_deposit_info->>'deposit_amount')::numeric, 500::numeric, 'Step 4: deposit_amount should be 500');
    RAISE NOTICE 'Step 4 PASSED: Scan shows fully paid, zero remaining';

    RAISE NOTICE '=============================================';
    RAISE NOTICE 'Overpayment integration test PASSED!';
    RAISE NOTICE '=============================================';
END;
$$ LANGUAGE plpgsql;
