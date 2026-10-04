-- Test: storno cleanup of deposit reminders
-- Goal: When a deposit order is stornoed, its pending reminder must not be sent.
--       Verified via get_due_queue_emails validation (state='paid' filter).

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

    INSERT INTO public.organizations (title) VALUES ('Test Org Storno') RETURNING id INTO v_org_id;
    INSERT INTO public.units (title, organization) VALUES ('Test Unit Storno', v_org_id) RETURNING id INTO v_unit_id;

    INSERT INTO eshop.secrets (secret) VALUES ('test_secret_storno') RETURNING id INTO v_secret_id;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type)
    VALUES ('Test Bank Storno', ARRAY['CZK'], v_secret_id, 'FIO') RETURNING id INTO v_acc_id;
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_acc_id, 1);

    v_occ_start_time := NOW() + interval '30 days';
    INSERT INTO public.occasions (title, unit, link, start_time, end_time, organization, features)
    VALUES (
        'Test Occasion Storno', v_unit_id,
        'test-occ-storno-' || floor(random()*100000)::text,
        v_occ_start_time, v_occ_start_time + interval '1 day', v_org_id,
        '[{"code": "deposit", "is_enabled": true, "deposit_deadline_days": 7}, {"code": "form", "is_enabled": true, "reminder_is_enabled": true, "reminder_interval_seconds": 259200}]'::jsonb
    ) RETURNING id INTO v_occasion_id;

    INSERT INTO public.forms (title, occasion, is_open) VALUES ('Test Form Storno', v_occasion_id, true)
    RETURNING id, key INTO v_form_id, v_form_key;

    INSERT INTO eshop.product_types (title, occasion, type) VALUES ('Test PT Storno', v_occasion_id, 'spot')
    RETURNING id INTO v_product_type_id;

    INSERT INTO public.form_fields (form, product_type) VALUES (v_form_id, v_product_type_id);

    INSERT INTO eshop.products (title, product_type, currency_code, price, is_hidden, occasion, data)
    VALUES ('Storno Product', v_product_type_id, 'CZK', 1000, false, v_occasion_id, '{"deposit": {"amount": 500}}'::jsonb)
    RETURNING id INTO v_product_id;

    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot Storno', v_product_id, v_occasion_id, gen_random_uuid())
    RETURNING id INTO v_spot_id;

    -- Create order
    v_input_data := jsonb_build_object(
        'form', v_form_key,
        'email', 'test-storno@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_id),
        'ticket', jsonb_build_array(jsonb_build_object('spot', v_spot_id))
    );
    SELECT create_ticket_order(v_input_data) INTO v_result;
    PERFORM assert_eq((v_result->>'code')::int, 200, 'Setup: order creation should succeed');
    v_order_id := (v_result->'order'->>'id')::bigint;

    -- Simulate deposit payment
    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id = v_order_id;
    UPDATE eshop.payment_info SET paid = 500 WHERE id = v_payment_info_id;
    UPDATE eshop.orders SET state = 'paid' WHERE id = v_order_id;
    UPDATE eshop.tickets SET state = 'paid' FROM eshop.order_product_ticket
    WHERE eshop.order_product_ticket.ticket = eshop.tickets.id
    AND eshop.order_product_ticket."order" = v_order_id;

    -- ==================================================================
    -- Step 1: Queue deposit reminder
    -- ==================================================================
    DELETE FROM public.email_messages WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND occasion = v_occasion_id AND code = 'TICKET_ORDER_REMINDER';
    PERFORM queue_payment_reminders(v_occasion_id, 259200);

    SELECT COUNT(*) INTO v_reminder_count
    FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id
    AND (data->>'order_id')::bigint = v_order_id;
    PERFORM assert_eq(v_reminder_count, 1::bigint, 'Step 1: 1 deposit reminder should be queued for paid order');
    RAISE NOTICE 'Step 1 PASSED: Deposit reminder queued before storno';

    -- ==================================================================
    -- Step 2: Storno the order
    -- ==================================================================
    PERFORM update_order_and_tickets_to_storno_221(v_order_id);

    -- Verify order is in storno state
    PERFORM assert_eq(
        (SELECT state FROM eshop.orders WHERE id = v_order_id),
        'storno',
        'Step 2: Order should be in storno state'
    );
    RAISE NOTICE 'Step 2 PASSED: Order stornoed';

    -- ==================================================================
    -- Step 3: get_due_queue_emails validation removes the reminder
    -- ==================================================================
    -- Force target_time to past so the email is "due"
    UPDATE public.email_messages
    SET target_time = NOW() - interval '1 minute'
    WHERE code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id
    AND (data->>'order_id')::bigint = v_order_id;

    -- Call get_due_queue_emails — validation should delete the now-stale reminder
    SELECT jsonb_agg(to_jsonb(m)) INTO v_due_result FROM public.email_messages m WHERE m.target_time<=now() AND public.email_intent_valid(m);

    -- Verify the reminder is no longer in the queue
    SELECT COUNT(*) INTO v_reminder_count
    FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id
    AND (data->>'order_id')::bigint = v_order_id;
    PERFORM assert_eq(v_reminder_count, 0::bigint, 'Step 3: Reminder should be ineligible after validation after storno');
    RAISE NOTICE 'Step 3 PASSED: Storno reminder ineligible after validation';

    RAISE NOTICE '=============================================';
    RAISE NOTICE 'Storno cleanup test PASSED!';
    RAISE NOTICE '=============================================';
END;
$$ LANGUAGE plpgsql;
