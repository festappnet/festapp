-- Form overrides remain distinct from inherited occasion defaults.
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
    v_deadline_case int;
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
    VALUES ('Grace Form', v_occasion_id, true, '{}'::jsonb)
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

    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id=v_order_id;
    PERFORM assert_true((SELECT abs(extract(epoch FROM (deadline-created_at))-604800)<10 FROM eshop.payment_info WHERE id=v_payment_info_id), 'Missing form deadline inherits seven-day fallback');
    PERFORM assert_true(EXISTS(SELECT 1 FROM public.email_messages m JOIN eshop.payment_info pi ON pi.id=v_payment_info_id WHERE m.order_id=v_order_id AND m.message_kind='order_reminder' AND m.workflow_state NOT IN ('cancelled','expired') AND m.target_time=pi.deadline-interval '3 days' AND public.email_intent_valid(m)), 'Absent override inherits enabled and event interval');

    UPDATE public.forms SET data='{"is_reminder_enabled":false}' WHERE id=v_form_id;
    PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.email_messages m WHERE m.order_id=v_order_id AND m.message_kind='order_reminder' AND public.email_intent_valid(m)), 'Explicit false invalidates queued reminder at send time');
    PERFORM public.queue_payment_reminders(v_occasion_id,0);
    PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.email_messages m WHERE m.order_id=v_order_id AND m.message_kind='order_reminder' AND m.workflow_state NOT IN ('cancelled','expired')), 'Explicit false suppresses queue');

    UPDATE public.occasions SET features='[{"code":"form","is_enabled":true,"reminder_is_enabled":false,"reminder_interval_seconds":259200}]' WHERE id=v_occasion_id;
    UPDATE public.forms SET data='{"is_reminder_enabled":true,"reminder_interval_seconds":86400}' WHERE id=v_form_id;
    PERFORM public.queue_payment_reminders(v_occasion_id,0);
    PERFORM assert_true(EXISTS(SELECT 1 FROM public.email_messages m JOIN eshop.payment_info pi ON pi.id=v_payment_info_id WHERE m.order_id=v_order_id AND m.message_kind='order_reminder' AND m.workflow_state NOT IN ('cancelled','expired') AND m.target_time=pi.deadline-interval '1 day' AND public.email_intent_valid(m)), 'Form true and interval override event false and three-day interval');

    UPDATE public.forms SET data='{"is_reminder_enabled":true,"reminder_interval_seconds":0}' WHERE id=v_form_id;
    PERFORM public.queue_payment_reminders(v_occasion_id,999999);
    PERFORM assert_true(EXISTS(SELECT 1 FROM public.email_messages m JOIN eshop.payment_info pi ON pi.id=v_payment_info_id WHERE m.order_id=v_order_id AND m.message_kind='order_reminder' AND m.workflow_state NOT IN ('cancelled','expired') AND m.target_time=pi.deadline AND public.email_intent_valid(m)), 'Explicit zero interval is retained and legacy argument cannot override persisted setting');
    UPDATE public.occasions SET features=features||'[{"code":"deposit","is_enabled":true,"deposit_deadline_days":7}]'::jsonb WHERE id=v_occasion_id;
    UPDATE eshop.payment_info SET deposit_amount=500,paid=500 WHERE id=v_payment_info_id;
    UPDATE eshop.orders SET state='paid' WHERE id=v_order_id;
    PERFORM public.queue_payment_reminders(v_occasion_id,0);
    PERFORM assert_true(EXISTS(SELECT 1 FROM public.email_messages m JOIN public.occasions occ ON occ.id=v_occasion_id WHERE m.order_id=v_order_id AND (m.data->>'is_deposit_reminder')::boolean IS TRUE AND m.workflow_state NOT IN ('cancelled','expired') AND m.target_time=occ.start_time-interval '7 days' AND public.email_intent_valid(m)), 'Deposit balance uses form opt-in over event false and explicit zero interval');
    UPDATE public.forms SET data='{"is_reminder_enabled":false}' WHERE id=v_form_id;
    PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.email_messages m WHERE m.order_id=v_order_id AND m.message_kind='order_reminder' AND public.email_intent_valid(m)), 'Deposit reminder invalidates after explicit form opt-out');
    PERFORM public.queue_payment_reminders(v_occasion_id,0);
    PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.email_messages m WHERE m.order_id=v_order_id AND m.message_kind='order_reminder' AND m.workflow_state NOT IN ('cancelled','expired')), 'Deposit form opt-out suppresses queue');
    UPDATE eshop.payment_info SET deposit_amount=NULL,paid=0 WHERE id=v_payment_info_id;
    UPDATE eshop.orders SET state='ordered' WHERE id=v_order_id;
    UPDATE public.forms SET data='{}' WHERE id=v_form_id;
    PERFORM public.queue_payment_reminders(v_occasion_id,0);
    PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.email_messages m WHERE m.order_id=v_order_id AND m.message_kind='order_reminder' AND m.workflow_state NOT IN ('cancelled','expired')), 'Clearing overrides restores disabled event default');

    UPDATE public.occasions SET features='[{"code":"form","is_enabled":true}]' WHERE id=v_occasion_id;
    PERFORM public.queue_payment_reminders(v_occasion_id,0);
    PERFORM assert_true(EXISTS(SELECT 1 FROM public.email_messages m JOIN eshop.payment_info pi ON pi.id=v_payment_info_id WHERE m.order_id=v_order_id AND m.message_kind='order_reminder' AND m.workflow_state NOT IN ('cancelled','expired') AND m.target_time=pi.deadline-interval '1 day' AND public.email_intent_valid(m)), 'Missing event values default to enabled and one day');

    UPDATE public.occasions SET features='[{"code":"form","is_enabled":false}]' WHERE id=v_occasion_id;
    UPDATE public.forms SET data='{"is_reminder_enabled":true}' WHERE id=v_form_id;
    PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.email_messages m WHERE m.order_id=v_order_id AND m.message_kind='order_reminder' AND public.email_intent_valid(m)), 'Disabled form feature prevents delivery even with explicit form enable');
    PERFORM public.queue_payment_reminders(v_occasion_id,0);
    PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.email_messages m WHERE m.order_id=v_order_id AND m.message_kind='order_reminder' AND m.workflow_state NOT IN ('cancelled','expired')), 'Disabled form feature prevents queue');

    -- Real order finalization must use occasion defaults, explicit form values,
    -- and zero without confusing any of them with an absent override.
    UPDATE public.occasions SET features='[{"code":"form","is_enabled":true,"deadline_duration_seconds":432000}]' WHERE id=v_occasion_id;
    FOR v_deadline_case IN 1..3 LOOP
        UPDATE public.forms SET deadline_duration_seconds=CASE v_deadline_case WHEN 1 THEN NULL WHEN 2 THEN 345600 ELSE 0 END WHERE id=v_form_id;
        INSERT INTO eshop.spots (title,product,occasion,secret)
        VALUES ('Deadline precedence spot',v_product_id,v_occasion_id,gen_random_uuid()) RETURNING id INTO v_spot_id;
        v_input_data:=jsonb_build_object('form',v_form_key,'email','deadline@example.com',
            'secret',(SELECT secret FROM eshop.spots WHERE id=v_spot_id),
            'ticket',jsonb_build_array(jsonb_build_object('spot',v_spot_id)));
        SELECT create_ticket_order(v_input_data) INTO v_result;
        PERFORM assert_eq((v_result->>'code')::int,200,'Deadline precedence order creation');
        v_order_id:=(v_result->'order'->>'id')::bigint;
        SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id=v_order_id;
        PERFORM assert_true((SELECT abs(extract(epoch FROM (deadline-created_at))-
            CASE v_deadline_case WHEN 1 THEN 432000 WHEN 2 THEN 345600 ELSE 0 END)<10
            FROM eshop.payment_info WHERE id=v_payment_info_id),
            'Actual deadline uses occasion, explicit form, and zero precedence');
    END LOOP;
    UPDATE public.occasions SET features='[{"code":"form","is_enabled":true,"reminder_is_enabled":false},{"code":"deposit","is_enabled":true,"deposit_deadline_days":7}]' WHERE id=v_occasion_id;
    UPDATE public.forms SET data='{"is_reminder_enabled":true,"reminder_interval_seconds":0}' WHERE id=v_form_id;
    UPDATE eshop.products SET data='{"deposit":{"amount":500}}' WHERE id=v_product_id;
    INSERT INTO eshop.spots(title,product,occasion,secret) VALUES('Actual deposit scheduling',v_product_id,v_occasion_id,gen_random_uuid()) RETURNING id INTO v_spot_id;
    v_input_data:=jsonb_build_object('form',v_form_key,'email','deposit@example.invalid','secret',(SELECT secret FROM eshop.spots WHERE id=v_spot_id),'ticket',jsonb_build_array(jsonb_build_object('spot',v_spot_id)));
    v_result:=public.create_ticket_order(v_input_data);
    PERFORM assert_eq((v_result->>'code')::integer,200,'Actual deposit order created with form override');
    v_order_id:=(v_result#>>'{order,id}')::bigint;
    PERFORM assert_true(EXISTS(SELECT 1 FROM public.email_messages m JOIN eshop.orders ord ON ord.id=m.order_id JOIN eshop.payment_info pi ON pi.id=ord.payment_info WHERE m.order_id=v_order_id AND m.message_kind='order_reminder' AND (m.data->>'is_deposit_reminder')::boolean IS TRUE AND m.workflow_state NOT IN ('cancelled','expired') AND m.target_time=pi.deposit_deadline),'Actual finalizer queues deposit-specific intent using form opt-in and zero interval');
    PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.email_messages m WHERE m.order_id=v_order_id AND (m.data->>'is_deposit_reminder')::boolean IS TRUE AND public.email_intent_valid(m)),'Initial unpaid ordered deposit intent is not deliverable before deposit transition');
    UPDATE eshop.orders SET state='paid' WHERE id=v_order_id;
    UPDATE eshop.payment_info SET paid=NULL WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=v_order_id);
    PERFORM assert_true(EXISTS(SELECT 1 FROM public.email_messages m WHERE m.order_id=v_order_id AND (m.data->>'is_deposit_reminder')::boolean IS TRUE AND public.email_intent_valid(m)),'Actual finalizer deposit intent delivers for legacy paid state with NULL paid balance treated as zero');
    UPDATE public.forms SET data='{"is_reminder_enabled":false}' WHERE id=v_form_id;
    PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.email_messages m WHERE m.order_id=v_order_id AND (m.data->>'is_deposit_reminder')::boolean IS TRUE AND public.email_intent_valid(m)),'Actual finalizer deposit intent respects subsequent form opt-out');
END $$;
