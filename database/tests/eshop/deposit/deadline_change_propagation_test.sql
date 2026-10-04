-- Test: deadline change propagation
-- Goal: When admin changes deposit_deadline_days on the occasion feature,
--       re-running queue_payment_reminders must update existing reminders' target_time
--       (DELETE+INSERT pattern), not leave stale ones.

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
    v_target_time timestamptz;
    v_expected_after_7d timestamptz;
    v_expected_after_14d timestamptz;
    v_occ_start_time timestamptz;
BEGIN
    -- ==================================================================
    -- Setup
    -- ==================================================================

    INSERT INTO public.organizations (title) VALUES ('Test Org Deadline') RETURNING id INTO v_org_id;
    INSERT INTO public.units (title, organization) VALUES ('Test Unit Deadline', v_org_id) RETURNING id INTO v_unit_id;

    INSERT INTO eshop.secrets (secret) VALUES ('test_secret_deadline') RETURNING id INTO v_secret_id;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type)
    VALUES ('Test Bank Deadline', ARRAY['CZK'], v_secret_id, 'FIO') RETURNING id INTO v_acc_id;
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_acc_id, 1);

    v_occ_start_time := NOW() + interval '30 days';
    -- Start with deposit_deadline_days = 7
    INSERT INTO public.occasions (title, unit, link, start_time, end_time, organization, features)
    VALUES (
        'Test Occasion Deadline', v_unit_id,
        'test-occ-deadline-' || floor(random()*100000)::text,
        v_occ_start_time, v_occ_start_time + interval '1 day', v_org_id,
        '[{"code": "deposit", "is_enabled": true, "deposit_deadline_days": 7}, {"code": "form", "is_enabled": true, "reminder_is_enabled": true, "reminder_interval_seconds": 259200}]'::jsonb
    ) RETURNING id INTO v_occasion_id;

    INSERT INTO public.forms (title, occasion, is_open) VALUES ('Test Form Deadline', v_occasion_id, true)
    RETURNING id, key INTO v_form_id, v_form_key;

    INSERT INTO eshop.product_types (title, occasion, type) VALUES ('Test PT Deadline', v_occasion_id, 'spot')
    RETURNING id INTO v_product_type_id;

    INSERT INTO public.form_fields (form, product_type) VALUES (v_form_id, v_product_type_id);

    INSERT INTO eshop.products (title, product_type, currency_code, price, is_hidden, occasion, data)
    VALUES ('Deadline Product', v_product_type_id, 'CZK', 1000, false, v_occasion_id, '{"deposit": {"amount": 500}}'::jsonb)
    RETURNING id INTO v_product_id;

    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Spot Deadline', v_product_id, v_occasion_id, gen_random_uuid())
    RETURNING id INTO v_spot_id;

    v_input_data := jsonb_build_object(
        'form', v_form_key,
        'email', 'test-deadline@example.com',
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
    -- Step 1: Queue reminder with deadline_days = 7
    -- ==================================================================
    DELETE FROM public.email_messages WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND occasion = v_occasion_id AND code = 'TICKET_ORDER_REMINDER';
    PERFORM queue_payment_reminders(v_occasion_id, 259200);  -- 3 days reminder interval

    SELECT COUNT(*) INTO v_reminder_count
    FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id
    AND (data->>'order_id')::bigint = v_order_id;
    PERFORM assert_eq(v_reminder_count, 1::bigint, 'Step 1: 1 reminder queued with 7d deadline');

    SELECT target_time INTO v_target_time
    FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id
    AND (data->>'order_id')::bigint = v_order_id;

    v_expected_after_7d := v_occ_start_time - interval '7 days' - interval '3 days';  -- start - 10d
    PERFORM assert_true(
        ABS(EXTRACT(EPOCH FROM (v_target_time - v_expected_after_7d))) < 1,
        'Step 1: target_time should be start - 7d - 3d (= start - 10d)'
    );
    RAISE NOTICE 'Step 1 PASSED: Reminder with 7d deadline targets start - 10d';

    -- ==================================================================
    -- Step 2: Admin changes deadline to 14 days
    -- ==================================================================
    UPDATE public.occasions
    SET features = '[{"code": "deposit", "is_enabled": true, "deposit_deadline_days": 14}, {"code": "form", "is_enabled": true, "reminder_is_enabled": true, "reminder_interval_seconds": 259200}]'::jsonb
    WHERE id = v_occasion_id;
    RAISE NOTICE 'Step 2 PASSED: Feature updated to 14d deadline';

    -- ==================================================================
    -- Step 3: Re-queue reminders; verify target_time reflects new deadline
    -- ==================================================================
    PERFORM queue_payment_reminders(v_occasion_id, 259200);

    SELECT COUNT(*) INTO v_reminder_count
    FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id
    AND (data->>'order_id')::bigint = v_order_id;
    PERFORM assert_eq(v_reminder_count, 1::bigint, 'Step 3: Still 1 reminder (DELETE+INSERT, no duplicate)');

    SELECT target_time INTO v_target_time
    FROM public.email_messages
    WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND code = 'TICKET_ORDER_REMINDER' AND occasion = v_occasion_id
    AND (data->>'order_id')::bigint = v_order_id;

    v_expected_after_14d := v_occ_start_time - interval '14 days' - interval '3 days';  -- start - 17d
    PERFORM assert_true(
        ABS(EXTRACT(EPOCH FROM (v_target_time - v_expected_after_14d))) < 1,
        'Step 3: target_time should reflect new 14d deadline (= start - 17d)'
    );
    RAISE NOTICE 'Step 3 PASSED: Reminder target_time updated to start - 17d';

    RAISE NOTICE '=============================================';
    RAISE NOTICE 'Deadline change propagation test PASSED!';
    RAISE NOTICE '=============================================';
END;
$$ LANGUAGE plpgsql;
