-- Test: On-site deposit deadline integration test
-- Goal: Validate on_site deadline means no reminder, scan shows on_site type, report shows split
-- Plan: 04-02, Task 2
-- Runner: node web_client/scripts/run_integration_tests.js on_site_surcharge_flow

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
    v_ticket_symbol text;
    v_scan_result jsonb;
    v_deposit_info jsonb;
    v_reminder_count bigint;
    v_report jsonb;
    v_report_user uuid;
BEGIN
    -- ==================================================================
    -- Setup: On-site deposit deadline (NOT days-based)
    -- ==================================================================
    INSERT INTO public.organizations (title) VALUES ('Test Org OnSite') RETURNING id INTO v_org_id;
    INSERT INTO public.units (title, organization) VALUES ('Test Unit OnSite', v_org_id) RETURNING id INTO v_unit_id;
    INSERT INTO eshop.secrets (secret) VALUES ('test_secret_onsite') RETURNING id INTO v_secret_id;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type)
    VALUES ('Test Bank OnSite', ARRAY['CZK'], v_secret_id, 'FIO') RETURNING id INTO v_acc_id;
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_acc_id, 1);
    INSERT INTO public.occasions_hidden (secret) VALUES ('scan_secret_onsite') RETURNING id INTO v_hidden_id;
    v_scan_code := 'scan_secret_onsite';

    v_occ_start_time := NOW() + interval '30 days';
    INSERT INTO public.occasions (
        title, unit, link, start_time, end_time, organization,
        features, occasion_hidden
    ) VALUES (
        'Test Occasion OnSite', v_unit_id,
        'test-occ-onsite-' || floor(random()*100000)::text,
        v_occ_start_time, v_occ_start_time + interval '1 day', v_org_id,
        '[{"code": "deposit", "is_enabled": true, "deposit_deadline": "on_site"}, {"code": "form", "is_enabled": true, "reminder_is_enabled": true, "reminder_interval_seconds": 259200}]'::jsonb,
        v_hidden_id
    ) RETURNING id INTO v_occasion_id;

    INSERT INTO public.forms (title, occasion, is_open)
    VALUES ('Test Form OnSite', v_occasion_id, true) RETURNING id, key INTO v_form_id, v_form_key;
    INSERT INTO eshop.product_types (title, occasion, type)
    VALUES ('Test PT OnSite', v_occasion_id, 'spot') RETURNING id INTO v_product_type_id;
    INSERT INTO public.form_fields (form, product_type) VALUES (v_form_id, v_product_type_id);
    INSERT INTO eshop.products (title, product_type, currency_code, price, is_hidden, occasion, data)
    VALUES ('Product OnSite', v_product_type_id, 'CZK', 1000, false, v_occasion_id, '{"deposit": {"amount": 500}}'::jsonb)
    RETURNING id INTO v_product_id;
    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot OnSite', v_product_id, v_occasion_id, gen_random_uuid()) RETURNING id INTO v_spot_id;

    -- ==================================================================
    -- Step 1: Create order (on_site deadline - no inline reminder expected)
    -- ==================================================================
    v_input_data := jsonb_build_object(
        'form', v_form_key, 'email', 'test-onsite@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_id),
        'ticket', jsonb_build_array(jsonb_build_object('spot', v_spot_id))
    );
    SELECT create_ticket_order(v_input_data) INTO v_result;
    PERFORM assert_eq((v_result->>'code')::int, 200, 'Step 1: Order creation should succeed');
    v_order_id := (v_result->'order'->>'id')::bigint;
    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id = v_order_id;

    -- No deposit reminder should be queued (on_site deadline)
    SELECT COUNT(*) INTO v_reminder_count FROM public.queue_emails
    WHERE code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id;
    PERFORM assert_eq(v_reminder_count, 0::bigint, 'Step 1: No reminder for on_site deadline');
    RAISE NOTICE 'Step 1 PASSED: Order created, no reminder for on_site';

    -- ==================================================================
    -- Step 2: Pay deposit (500)
    -- ==================================================================
    INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
    VALUES (90301, now(), 500, 'CZK', v_acc_id,
        (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_payment_info_id)::text)
    RETURNING id INTO v_transaction_id;
    PERFORM public.apply_transaction_pairing(v_transaction_id, v_payment_info_id, 'test', 'system');

    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    PERFORM assert_eq(v_order_state, 'paid', 'Step 2: Order should be paid after deposit');
    RAISE NOTICE 'Step 2 PASSED: Deposit paid';

    -- ==================================================================
    -- Step 3: Batch function produces no reminder (on_site excluded)
    -- ==================================================================
    PERFORM queue_payment_reminders(v_occasion_id, 259200);
    SELECT COUNT(*) INTO v_reminder_count FROM public.queue_emails
    WHERE code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id;
    PERFORM assert_eq(v_reminder_count, 0::bigint, 'Step 3: No reminder from batch for on_site');
    RAISE NOTICE 'Step 3 PASSED: Batch produces no reminder for on_site';

    -- ==================================================================
    -- Step 4: Scan ticket (after deposit) - shows on_site deadline type
    -- ==================================================================
    SELECT t.ticket_symbol INTO v_ticket_symbol FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    WHERE opt."order" = v_order_id LIMIT 1;

    SELECT scan_ticket(v_ticket_symbol, v_scan_code) INTO v_scan_result;
    PERFORM assert_eq((v_scan_result->>'code')::int, 200, 'Step 4: Scan should succeed');
    v_deposit_info := v_scan_result->'deposit_info';
    PERFORM assert_true(v_deposit_info IS NOT NULL, 'Step 4: deposit_info should NOT be NULL');
    PERFORM assert_eq(v_deposit_info->>'deadline_type', 'on_site', 'Step 4: deadline_type should be on_site');
    PERFORM assert_true(
        (v_deposit_info->>'deadline_date') IS NULL,
        'Step 4: deadline_date should be NULL for on_site'
    );
    PERFORM assert_eq((v_deposit_info->>'remaining_amount')::numeric, 500::numeric, 'Step 4: remaining should be 500');
    PERFORM assert_eq((v_deposit_info->>'is_fully_paid')::boolean, false, 'Step 4: is_fully_paid should be false');
    RAISE NOTICE 'Step 4 PASSED: Scan shows on_site deadline, 500 remaining';

    -- ==================================================================
    -- Step 5: Pay remaining (500)
    -- ==================================================================
    INSERT INTO eshop.transactions (transaction_id, date, amount, currency, bank_account_id, vs)
    VALUES (90302, now(), 500, 'CZK', v_acc_id,
        (SELECT variable_symbol FROM eshop.payment_info WHERE id = v_payment_info_id)::text)
    RETURNING id INTO v_transaction_id;
    PERFORM public.apply_transaction_pairing(v_transaction_id, v_payment_info_id, 'test', 'system');

    SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = v_payment_info_id;
    PERFORM assert_eq(v_paid, 1000::numeric, 'Step 5: paid should be 1000');
    RAISE NOTICE 'Step 5 PASSED: Remaining paid, total 1000';

    -- ==================================================================
    -- Step 6: Scan ticket (after full payment) - still shows on_site type
    -- ==================================================================
    SELECT scan_ticket(v_ticket_symbol, v_scan_code) INTO v_scan_result;
    v_deposit_info := v_scan_result->'deposit_info';
    PERFORM assert_eq((v_deposit_info->>'remaining_amount')::numeric, 0::numeric, 'Step 6: remaining should be 0');
    PERFORM assert_eq((v_deposit_info->>'is_fully_paid')::boolean, true, 'Step 6: is_fully_paid should be true');
    PERFORM assert_eq(v_deposit_info->>'deadline_type', 'on_site', 'Step 6: deadline_type should still be on_site');
    RAISE NOTICE 'Step 6 PASSED: Scan shows fully paid, on_site deadline';

    -- ==================================================================
    -- Step 7: Financial report shows deposit/remaining split
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
      1000::numeric,'Report received from payment workflow');


    RAISE NOTICE '=============================================';
    RAISE NOTICE 'On-site deposit deadline integration test PASSED!';
    RAISE NOTICE '=============================================';
END;
$$ LANGUAGE plpgsql;
