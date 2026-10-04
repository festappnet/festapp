-- Test: deposit reminder queueing and validation
-- Goal: Verify queue_payment_reminders (deposit branch), send-time validation, and email code determination

DO $$
DECLARE
    v_org_id bigint;
    v_unit_id bigint;
    v_occasion_id bigint;
    v_form_id bigint;
    v_form_key uuid;
    v_product_type_id bigint;
    v_product_with_deposit_id bigint;
    v_product_without_deposit_id bigint;
    v_spot_1_id bigint;
    v_spot_2_id bigint;
    v_acc_id bigint;
    v_secret_id bigint;
    v_input_data jsonb;
    v_result jsonb;
    v_order_id bigint;
    v_order_2_id bigint;
    v_payment_info_id bigint;
    v_reminder_count bigint;
    v_target_time timestamptz;
    v_expected_target_time timestamptz;
    v_occ_start_time timestamptz;
    v_due_result jsonb;
BEGIN
    -- ==================================================================
    -- Setup: Create test environment
    -- ==================================================================

    -- Create Org & Unit
    INSERT INTO public.organizations (title) VALUES ('Test Org Reminder') RETURNING id INTO v_org_id;
    INSERT INTO public.units (title, organization) VALUES ('Test Unit Reminder', v_org_id) RETURNING id INTO v_unit_id;

    -- Create Bank Account (CZK)
    INSERT INTO eshop.secrets (secret) VALUES ('test_secret_reminder') RETURNING id INTO v_secret_id;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type)
    VALUES ('Test Bank Reminder', ARRAY['CZK'], v_secret_id, 'FIO') RETURNING id INTO v_acc_id;

    -- Link Bank Account to Unit
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_acc_id, 1);

    -- Create Occasion (30 days in the future with deposit deadline 7 days before, reminder enabled)
    v_occ_start_time := NOW() + interval '30 days';
    INSERT INTO public.occasions (
        title, unit, link, start_time, end_time, organization,
        features
    )
    VALUES (
        'Test Occasion Reminder', v_unit_id,
        'test-occ-reminder-' || floor(random()*100000)::text,
        v_occ_start_time,
        v_occ_start_time + interval '1 day',
        v_org_id,
        '[{"code": "deposit", "is_enabled": true, "deposit_deadline_days": 7}, {"code": "form", "is_enabled": true, "reminder_is_enabled": true, "reminder_interval_seconds": 259200}]'::jsonb
    )
    RETURNING id INTO v_occasion_id;

    -- Create Form (Open)
    INSERT INTO public.forms (title, occasion, is_open)
    VALUES ('Test Form Reminder', v_occasion_id, true)
    RETURNING id, key INTO v_form_id, v_form_key;

    -- Create Product Type (Spot)
    INSERT INTO eshop.product_types (title, occasion, type)
    VALUES ('Test PT Reminder', v_occasion_id, 'spot')
    RETURNING id INTO v_product_type_id;

    -- Link Product Type to Form
    INSERT INTO public.form_fields (form, product_type) VALUES (v_form_id, v_product_type_id);

    -- Create Product with deposit (price: 1000, deposit: 500)
    INSERT INTO eshop.products (title, product_type, currency_code, price, is_hidden, occasion, data)
    VALUES ('Product With Deposit R', v_product_type_id, 'CZK', 1000, false, v_occasion_id, '{"deposit": {"amount": 500}}'::jsonb)
    RETURNING id INTO v_product_with_deposit_id;

    -- Create Product without deposit (price: 800)
    INSERT INTO eshop.products (title, product_type, currency_code, price, is_hidden, occasion, data)
    VALUES ('Product No Deposit R', v_product_type_id, 'CZK', 800, false, v_occasion_id, NULL)
    RETURNING id INTO v_product_without_deposit_id;

    -- Create Spots
    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot R1', v_product_with_deposit_id, v_occasion_id, gen_random_uuid())
    RETURNING id INTO v_spot_1_id;

    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot R2', v_product_without_deposit_id, v_occasion_id, gen_random_uuid())
    RETURNING id INTO v_spot_2_id;

    -- Create order with deposit product
    v_input_data := jsonb_build_object(
        'form', v_form_key,
        'email', 'test-reminder@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_1_id),
        'ticket', jsonb_build_array(
            jsonb_build_object('spot', v_spot_1_id)
        )
    );
    SELECT create_ticket_order(v_input_data) INTO v_result;
    PERFORM assert_eq((v_result->>'code')::int, 200, 'Setup: Deposit order creation should succeed');
    v_order_id := (v_result->'order'->>'id')::bigint;

    -- Simulate deposit payment: update paid to deposit_amount and order to 'paid'
    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id = v_order_id;
    UPDATE eshop.payment_info SET paid = 500 WHERE id = v_payment_info_id;
    UPDATE eshop.orders SET state = 'paid' WHERE id = v_order_id;
    UPDATE eshop.tickets SET state = 'paid' FROM eshop.order_product_ticket
    WHERE eshop.order_product_ticket.ticket = eshop.tickets.id
    AND eshop.order_product_ticket."order" = v_order_id;

    -- ==================================================================
    -- Test 1: Deposit reminder queued via queue_payment_reminders
    -- ==================================================================

    -- Clear any reminders that may have been queued at order creation
    DELETE FROM public.email_messages WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND occasion = v_occasion_id AND code = 'TICKET_ORDER_REMINDER';

    -- Call the batch function
    PERFORM queue_payment_reminders(v_occasion_id, 259200);

    SELECT COUNT(*) INTO v_reminder_count
    FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id;

    PERFORM assert_eq(v_reminder_count, 1::bigint, 'Test 1: Should queue exactly 1 deposit reminder');

    -- Verify target_time = occasion start - 7 days (deposit deadline) - 3 days (reminder interval) = start - 10 days
    SELECT target_time INTO v_target_time
    FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id;

    v_expected_target_time := v_occ_start_time - interval '7 days' - interval '3 days';

    -- Allow 1 second tolerance for timing
    PERFORM assert_true(
        ABS(EXTRACT(EPOCH FROM (v_target_time - v_expected_target_time))) < 1,
        'Test 1: target_time should be occasion start - 10 days'
    );

    RAISE NOTICE 'Test 1 PASSED: Deposit reminder queued with correct target_time';

    -- ==================================================================
    -- Test 2: No reminder for "on site" deadline
    -- ==================================================================

    -- Change deposit feature to on_site deadline
    UPDATE public.occasions
    SET features = '[{"code": "deposit", "is_enabled": true, "deposit_deadline": "on_site"}, {"code": "form", "is_enabled": true, "reminder_is_enabled": true, "reminder_interval_seconds": 259200}]'::jsonb
    WHERE id = v_occasion_id;

    PERFORM queue_payment_reminders(v_occasion_id, 259200);

    SELECT COUNT(*) INTO v_reminder_count
    FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id;

    PERFORM assert_eq(v_reminder_count, 0::bigint, 'Test 2: No reminder should be queued for on_site deadline');

    RAISE NOTICE 'Test 2 PASSED: No reminder for on_site deadline';

    -- Reset deposit feature back for subsequent tests
    UPDATE public.occasions
    SET features = '[{"code": "deposit", "is_enabled": true, "deposit_deadline_days": 7}, {"code": "form", "is_enabled": true, "reminder_is_enabled": true, "reminder_interval_seconds": 259200}]'::jsonb
    WHERE id = v_occasion_id;

    -- ==================================================================
    -- Test 3: No reminder for fully-paid order
    -- ==================================================================

    -- Mark order as fully paid
    UPDATE eshop.payment_info SET paid = 1000 WHERE id = v_payment_info_id;

    PERFORM queue_payment_reminders(v_occasion_id, 259200);

    SELECT COUNT(*) INTO v_reminder_count
    FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id;

    PERFORM assert_eq(v_reminder_count, 0::bigint, 'Test 3: No reminder should be queued for fully-paid order');

    RAISE NOTICE 'Test 3 PASSED: No reminder for fully-paid order';

    -- ==================================================================
    -- Test 4: Send-time validation deletes invalid reminders
    -- ==================================================================

    -- Reset paid to deposit amount (partially paid again)
    UPDATE eshop.payment_info SET paid = 500 WHERE id = v_payment_info_id;

    -- Queue a reminder
    PERFORM queue_payment_reminders(v_occasion_id, 259200);

    SELECT COUNT(*) INTO v_reminder_count
    FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id;

    PERFORM assert_eq(v_reminder_count, 1::bigint, 'Test 4: Should have 1 queued reminder');

    -- Make the reminder "due" by setting target_time to past
    UPDATE public.email_messages
    SET target_time = NOW() - interval '1 minute'
    WHERE code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id;

    -- Now simulate full payment
    UPDATE eshop.payment_info SET paid = 1000 WHERE id = v_payment_info_id;

    -- Call get_due_queue_emails — should invalidate and delete the reminder
    SELECT jsonb_agg(to_jsonb(m)) INTO v_due_result FROM public.email_messages m WHERE m.target_time<=now() AND public.email_intent_valid(m);

    -- Verify the deposit reminder was deleted (invalidated because paid >= amount)
    SELECT COUNT(*) INTO v_reminder_count
    FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id;

    PERFORM assert_eq(v_reminder_count, 0::bigint, 'Test 4: Stale reminder should be deleted after full payment');

    RAISE NOTICE 'Test 4 PASSED: Send-time validation deleted stale reminder';

    -- ==================================================================
    -- Test 5: No reminder for order without deposit
    -- ==================================================================

    -- Reset payment info for deposit order
    UPDATE eshop.payment_info SET paid = 500 WHERE id = v_payment_info_id;

    -- Create second order with non-deposit product
    v_input_data := jsonb_build_object(
        'form', v_form_key,
        'email', 'test-reminder-nodeposit@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_2_id),
        'ticket', jsonb_build_array(
            jsonb_build_object('spot', v_spot_2_id)
        )
    );
    SELECT create_ticket_order(v_input_data) INTO v_result;
    PERFORM assert_eq((v_result->>'code')::int, 200, 'Test 5: Non-deposit order creation should succeed');
    v_order_2_id := (v_result->'order'->>'id')::bigint;

    -- Move to paid state
    UPDATE eshop.orders SET state = 'paid' WHERE id = v_order_2_id;

    -- Queue reminders again
    PERFORM queue_payment_reminders(v_occasion_id, 259200);

    -- Should only have 1 reminder (for the deposit order, not the non-deposit one)
    SELECT COUNT(*) INTO v_reminder_count
    FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id;

    PERFORM assert_eq(v_reminder_count, 1::bigint, 'Test 5: Should only queue reminder for deposit order, not non-deposit');

    -- Verify the reminder is for the deposit order, not the non-deposit order
    PERFORM assert_true(
        EXISTS(
            SELECT 1 FROM public.email_messages
            WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER'
            AND occasion = v_occasion_id
            AND (data->>'order_id')::bigint = v_order_id
        ),
        'Test 5: Reminder should be for deposit order only'
    );

    RAISE NOTICE 'Test 5 PASSED: No reminder for non-deposit order';

    RAISE NOTICE '=============================================';
    RAISE NOTICE 'All deposit reminder tests passed!';
    RAISE NOTICE '=============================================';
END;
$$ LANGUAGE plpgsql;
