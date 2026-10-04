-- Test: race condition — customer pays remaining balance just before reminder cron fires
-- Goal: get_due_queue_emails must invalidate the deposit reminder once pi.paid >= pi.amount,
--       so the customer doesn't receive a "you still owe X" email after paying in full.

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
    v_input_data jsonb;
    v_result jsonb;
    v_order_id bigint;
    v_payment_info_id bigint;
    v_reminder_count bigint;
    v_due_result jsonb;
    v_occ_start_time timestamptz;
BEGIN
    -- ==================================================================
    -- Setup
    -- ==================================================================

    INSERT INTO public.organizations (title) VALUES ('Test Org Race') RETURNING id INTO v_org_id;
    INSERT INTO public.units (title, organization) VALUES ('Test Unit Race', v_org_id) RETURNING id INTO v_unit_id;

    INSERT INTO eshop.secrets (secret) VALUES ('test_secret_race') RETURNING id INTO v_secret_id;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type)
    VALUES ('Test Bank Race', ARRAY['CZK'], v_secret_id, 'FIO') RETURNING id INTO v_acc_id;
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_acc_id, 1);

    v_occ_start_time := NOW() + interval '30 days';
    INSERT INTO public.occasions (title, unit, link, start_time, end_time, organization, features)
    VALUES (
        'Test Occasion Race', v_unit_id,
        'test-occ-race-' || floor(random()*100000)::text,
        v_occ_start_time, v_occ_start_time + interval '1 day', v_org_id,
        '[{"code": "deposit", "is_enabled": true, "deposit_deadline_days": 7}, {"code": "form", "is_enabled": true, "reminder_is_enabled": true, "reminder_interval_seconds": 259200}]'::jsonb
    ) RETURNING id INTO v_occasion_id;

    INSERT INTO public.forms (title, occasion, is_open) VALUES ('Test Form Race', v_occasion_id, true)
    RETURNING id, key INTO v_form_id, v_form_key;

    INSERT INTO eshop.product_types (title, occasion, type) VALUES ('Test PT Race', v_occasion_id, 'spot')
    RETURNING id INTO v_product_type_id;

    INSERT INTO public.form_fields (form, product_type) VALUES (v_form_id, v_product_type_id);

    INSERT INTO eshop.products (title, product_type, currency_code, price, is_hidden, occasion, data)
    VALUES ('Race Product', v_product_type_id, 'CZK', 1000, false, v_occasion_id, '{"deposit": {"amount": 500}}'::jsonb)
    RETURNING id INTO v_product_id;

    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot Race', v_product_id, v_occasion_id, gen_random_uuid())
    RETURNING id INTO v_spot_id;

    -- Create order
    v_input_data := jsonb_build_object(
        'form', v_form_key,
        'email', 'test-race@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_id),
        'ticket', jsonb_build_array(jsonb_build_object('spot', v_spot_id))
    );
    SELECT create_ticket_order(v_input_data) INTO v_result;
    PERFORM assert_eq((v_result->>'code')::int, 200, 'Setup: order creation should succeed');
    v_order_id := (v_result->'order'->>'id')::bigint;

    -- Simulate deposit payment (paid=500, total=1000, balance still due)
    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id = v_order_id;
    UPDATE eshop.payment_info SET paid = 500 WHERE id = v_payment_info_id;
    UPDATE eshop.orders SET state = 'paid' WHERE id = v_order_id;
    UPDATE eshop.tickets SET state = 'paid' FROM eshop.order_product_ticket
    WHERE eshop.order_product_ticket.ticket = eshop.tickets.id
    AND eshop.order_product_ticket."order" = v_order_id;

    -- ==================================================================
    -- Step 1: Queue deposit reminder (state at the moment cron prepared the email)
    -- ==================================================================
    DELETE FROM public.email_messages WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND occasion = v_occasion_id AND code = 'TICKET_ORDER_REMINDER';
    PERFORM queue_payment_reminders(v_occasion_id, 259200);

    SELECT COUNT(*) INTO v_reminder_count
    FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id
    AND (data->>'order_id')::bigint = v_order_id;
    PERFORM assert_eq(v_reminder_count, 1::bigint, 'Step 1: deposit reminder queued');
    RAISE NOTICE 'Step 1 PASSED: Reminder queued (paid=500, amount=1000)';

    -- ==================================================================
    -- Step 2: Customer pays remaining balance — race window
    -- ==================================================================
    -- Force the reminder to be due (simulate cron tick time arriving)
    UPDATE public.email_messages
    SET target_time = NOW() - interval '1 minute'
    WHERE code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id
    AND (data->>'order_id')::bigint = v_order_id;

    -- Pay the rest (1000 total)
    UPDATE eshop.payment_info SET paid = 1000 WHERE id = v_payment_info_id;
    RAISE NOTICE 'Step 2 PASSED: Customer paid full amount (paid=1000 = amount)';

    -- ==================================================================
    -- Step 3: Reminder cron fires — validation must catch it
    -- ==================================================================
    SELECT jsonb_agg(to_jsonb(m)) INTO v_due_result FROM public.email_messages m WHERE m.target_time<=now() AND public.email_intent_valid(m);

    SELECT COUNT(*) INTO v_reminder_count
    FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id
    AND (data->>'order_id')::bigint = v_order_id;
    PERFORM assert_eq(v_reminder_count, 0::bigint, 'Step 3: Reminder must be invalidated when paid >= amount');
    RAISE NOTICE 'Step 3 PASSED: Stale reminder removed (validation blocked send)';

    RAISE NOTICE '=============================================';
    RAISE NOTICE 'Race condition test PASSED!';
    RAISE NOTICE '=============================================';
END;
$$ LANGUAGE plpgsql;
