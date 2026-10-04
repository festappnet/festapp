-- Test: reminder grace period — stale queue entries are dropped on validation
-- Goal: Verify get_due_queue_emails treats reminder entries older than 7 days as invalid
-- and deletes them, while entries within the grace period are returned for sending.

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
    v_due_result jsonb;
    v_reminder_count bigint;
    v_stale_id bigint;
    v_fresh_id bigint;
BEGIN
    -- ==================================================================
    -- Setup: minimal org/occasion/form/order with deadline + reminder enabled
    -- ==================================================================

    INSERT INTO public.organizations (title) VALUES ('Grace Org') RETURNING id INTO v_org_id;
    INSERT INTO public.units (title, organization) VALUES ('Grace Unit', v_org_id) RETURNING id INTO v_unit_id;

    INSERT INTO eshop.secrets (secret) VALUES ('grace_secret') RETURNING id INTO v_secret_id;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type)
    VALUES ('Grace Bank', ARRAY['CZK'], v_secret_id, 'FIO') RETURNING id INTO v_acc_id;
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_acc_id, 1);

    INSERT INTO public.occasions (
        title, unit, link, start_time, end_time, organization, features
    )
    VALUES (
        'Grace Occasion', v_unit_id,
        'grace-occ-' || floor(random()*100000)::text,
        NOW() + interval '30 days',
        NOW() + interval '31 days',
        v_org_id,
        '[{"code": "form", "is_enabled": true, "reminder_is_enabled": true, "reminder_interval_seconds": 259200}]'::jsonb
    )
    RETURNING id INTO v_occasion_id;

    INSERT INTO public.forms (title, occasion, is_open, data)
    VALUES ('Grace Form', v_occasion_id, true, '{"is_reminder_enabled": true}'::jsonb)
    RETURNING id, key INTO v_form_id, v_form_key;

    INSERT INTO eshop.product_types (title, occasion, type)
    VALUES ('Grace PT', v_occasion_id, 'spot')
    RETURNING id INTO v_product_type_id;

    INSERT INTO public.form_fields (form, product_type) VALUES (v_form_id, v_product_type_id);

    INSERT INTO eshop.products (title, product_type, currency_code, price, is_hidden, occasion)
    VALUES ('Grace Product', v_product_type_id, 'CZK', 1000, false, v_occasion_id)
    RETURNING id INTO v_product_id;

    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Grace Spot', v_product_id, v_occasion_id, gen_random_uuid())
    RETURNING id INTO v_spot_id;

    v_input_data := jsonb_build_object(
        'form', v_form_key,
        'email', 'grace@example.com',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_id),
        'ticket', jsonb_build_array(jsonb_build_object('spot', v_spot_id))
    );
    SELECT create_ticket_order(v_input_data) INTO v_result;
    PERFORM assert_eq((v_result->>'code')::int, 200, 'Setup: Order creation should succeed');
    v_order_id := (v_result->'order'->>'id')::bigint;

    -- Ensure order is in 'ordered' state with a future deadline so the only failing
    -- condition in tests below is the grace period itself.
    UPDATE eshop.orders SET state = 'ordered' WHERE id = v_order_id;
    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id = v_order_id;
    UPDATE eshop.payment_info
    SET deadline = NOW() + interval '30 days',
        data = COALESCE(data, '{}'::jsonb) || '{"current_version_reminded": false}'::jsonb
    WHERE id = v_payment_info_id;

    DELETE FROM public.email_messages WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND occasion = v_occasion_id;

    -- ==================================================================
    -- Test 1: stale entry (target_time 8 days in past) is invalidated + deleted
    -- ==================================================================

    SELECT public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object('order_id', v_order_id),v_org_id,v_occasion_id,v_unit_id,NOW() - interval '8 days',gen_random_uuid()::text) INTO v_result;
    SELECT id INTO v_stale_id FROM public.email_messages WHERE message_id=(v_result->>'message_id')::uuid;

    SELECT jsonb_agg(to_jsonb(m)) INTO v_due_result FROM public.email_messages m WHERE m.target_time<=now() AND public.email_intent_valid(m);

    PERFORM assert_true(
        NOT EXISTS(SELECT 1 FROM public.email_messages WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND id = v_stale_id),
        'Test 1: stale entry (8d old) should be ineligible for delivery, with audit retained'
    );

    PERFORM assert_true(
        v_due_result IS NULL
        OR NOT EXISTS(
            SELECT 1 FROM jsonb_array_elements(v_due_result) e
            WHERE (e->>'id')::bigint = v_stale_id
        ),
        'Test 1: stale entry should not appear in result for sending'
    );

    RAISE NOTICE 'Test 1 PASSED: stale entry beyond grace period was dropped';

    -- ==================================================================
    -- Test 2: entry within grace period (6 days old) is still returned
    -- ==================================================================

    SELECT public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object('order_id', v_order_id),v_org_id,v_occasion_id,v_unit_id,NOW() - interval '6 days',gen_random_uuid()::text) INTO v_result;
    SELECT id INTO v_fresh_id FROM public.email_messages WHERE message_id=(v_result->>'message_id')::uuid;

    SELECT jsonb_agg(to_jsonb(m)) INTO v_due_result FROM public.email_messages m WHERE m.target_time<=now() AND public.email_intent_valid(m);

    PERFORM assert_true(
        EXISTS(SELECT 1 FROM public.email_messages WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND id = v_fresh_id),
        'Test 2: entry within grace period (6d) should remain in queue'
    );

    PERFORM assert_true(
        v_due_result IS NOT NULL
        AND EXISTS(
            SELECT 1 FROM jsonb_array_elements(v_due_result) e
            WHERE (e->>'id')::bigint = v_fresh_id
        ),
        'Test 2: entry within grace period should be returned for sending'
    );

    RAISE NOTICE 'Test 2 PASSED: entry within grace period was returned';

    -- ==================================================================
    -- Test 3: boundary — entry exactly at 7-day boundary (slightly before) is dropped
    -- ==================================================================

    DELETE FROM public.email_messages WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND occasion = v_occasion_id;

    SELECT public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object('order_id', v_order_id),v_org_id,v_occasion_id,v_unit_id,NOW() - interval '7 days' - interval '1 minute',gen_random_uuid()::text) INTO v_result;
    SELECT id INTO v_stale_id FROM public.email_messages WHERE message_id=(v_result->>'message_id')::uuid;

    SELECT jsonb_agg(to_jsonb(m)) INTO v_due_result FROM public.email_messages m WHERE m.target_time<=now() AND public.email_intent_valid(m);

    PERFORM assert_true(
        NOT EXISTS(SELECT 1 FROM public.email_messages WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND id = v_stale_id),
        'Test 3: entry just past 7-day boundary should be dropped'
    );

    RAISE NOTICE 'Test 3 PASSED: entry just past 7-day boundary was dropped';

    -- ==================================================================
    -- Test 4: deposit reminder (with is_deposit_reminder flag) also respects grace
    -- ==================================================================

    SELECT public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object('order_id', v_order_id, 'is_deposit_reminder', true),v_org_id,v_occasion_id,v_unit_id,NOW() - interval '10 days',gen_random_uuid()::text) INTO v_result;
    SELECT id INTO v_stale_id FROM public.email_messages WHERE message_id=(v_result->>'message_id')::uuid;

    SELECT jsonb_agg(to_jsonb(m)) INTO v_due_result FROM public.email_messages m WHERE m.target_time<=now() AND public.email_intent_valid(m);

    PERFORM assert_true(
        NOT EXISTS(SELECT 1 FROM public.email_messages WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND id = v_stale_id),
        'Test 4: stale deposit reminder should also be dropped by grace period'
    );

    RAISE NOTICE 'Test 4 PASSED: grace period applies to deposit reminders too';

    -- ==================================================================
    UPDATE eshop.orders SET state='paid' WHERE id=v_order_id;
    -- Test 5: PAYMENT_DONE is NOT affected by grace (different code path)
    -- ==================================================================

    SELECT public.enqueue_order_email('TICKET_ORDER_PAYMENT_DONE',jsonb_build_object('order_id', v_order_id),v_org_id,v_occasion_id,v_unit_id,NOW() - interval '30 days',gen_random_uuid()::text) INTO v_result;
    SELECT id INTO v_fresh_id FROM public.email_messages WHERE message_id=(v_result->>'message_id')::uuid;

    SELECT jsonb_agg(to_jsonb(m)) INTO v_due_result FROM public.email_messages m WHERE m.target_time<=now() AND public.email_intent_valid(m);

    PERFORM assert_true(
        EXISTS(SELECT 1 FROM public.email_messages WHERE workflow_state NOT IN ('cancelled','expired') AND (target_time>now() OR public.email_intent_valid(email_messages)) AND id = v_fresh_id),
        'Test 5: old PAYMENT_DONE should NOT be dropped (grace applies only to reminders)'
    );

    RAISE NOTICE 'Test 5 PASSED: PAYMENT_DONE is exempt from reminder grace period';

    RAISE NOTICE '=============================================';
    RAISE NOTICE 'All grace period tests passed!';
    RAISE NOTICE '=============================================';
END;
$$ LANGUAGE plpgsql;
