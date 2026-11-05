-- test-setup: database/tests/blueprint/fixtures.sql
-- test-setup: database/tests/helpers/canonical_blueprint_order_fixture.sql
-- Keep production email limits: independent buyers must not recharge existing reminders.
-- This regressed to code 1013 / abuse_limit_exceeded on the seventh checkout.
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
    v_payment_info_id bigint;
    i integer;
    first_order bigint;
    first_version bigint;
    first_message bigint;
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

    FOR i IN 1..8 LOOP
      INSERT INTO eshop.spots(title,product,occasion,secret)
      VALUES ('Seat '||i,v_product_id,v_occasion_id,gen_random_uuid()) RETURNING id INTO v_spot_id;
      v_input_data:=pg_temp.prepare_order_fixture_input(jsonb_build_object(
        'form',v_form_key,'email','buyer-'||i||'@example.invalid',
        'ticket',jsonb_build_array(jsonb_build_object('spot',v_spot_id))));
      v_result:=public.create_ticket_order_client_sync_v1(v_input_data,gen_random_uuid(),gen_random_uuid());
      PERFORM assert_eq((v_result->>'code')::int,200,'Public checkout succeeds: '||v_result::text);
      v_result:=v_result->'data';
      PERFORM assert_eq((v_result->>'code')::int,200,'Independent buyer checkout must not exhaust another buyer email budget: '||v_result::text);
      IF i=1 THEN
        first_order:=(v_result#>>'{order,id}')::bigint;
        SELECT pi.email_reminder_version INTO first_version FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id WHERE o.id=first_order;
        SELECT id INTO first_message FROM public.email_messages WHERE order_id=first_order AND message_kind='order_reminder';
      END IF;
    END LOOP;
    PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE occasion=v_occasion_id AND message_kind='order_reminder'),8::bigint,'One reminder per independent checkout');
    PERFORM assert_eq((SELECT pi.email_reminder_version FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id WHERE o.id=first_order),first_version,'Other checkouts leave the first payment reminder version unchanged');
    PERFORM assert_eq((SELECT workflow_state FROM public.email_messages WHERE id=first_message),'pending','Other checkouts preserve the first reminder');
    SELECT payment_info INTO v_payment_info_id FROM eshop.orders WHERE id=(v_result#>>'{order,id}')::bigint;
    PERFORM public.set_payment_deadline(v_payment_info_id,now()+interval '20 days');
    PERFORM assert_eq((SELECT workflow_state FROM public.email_messages WHERE id=first_message),'pending','Changing one deadline preserves another payment reminder');
    -- Deposits also reschedule reminders during finalization. Keep that path scoped.
    UPDATE public.occasions SET features=features||'[{"code":"deposit","is_enabled":true,"deposit_deadline_days":7}]'::jsonb WHERE id=v_occasion_id;
    UPDATE eshop.products SET data='{"deposit":{"amount":500}}' WHERE id=v_product_id;
    FOR i IN 9..16 LOOP
      INSERT INTO eshop.spots(title,product,occasion,secret)
      VALUES ('Seat '||i,v_product_id,v_occasion_id,gen_random_uuid()) RETURNING id INTO v_spot_id;
      v_input_data:=pg_temp.prepare_order_fixture_input(jsonb_build_object(
        'form',v_form_key,'email','buyer-'||i||'@example.invalid',
        'ticket',jsonb_build_array(jsonb_build_object('spot',v_spot_id))));
      v_result:=public.create_ticket_order_client_sync_v1(v_input_data,gen_random_uuid(),gen_random_uuid());
      PERFORM assert_eq((v_result->>'code')::int,200,'Deposit checkout must not recharge another buyer: '||v_result::text);
    END LOOP;
    PERFORM assert_eq((SELECT pi.email_reminder_version FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id WHERE o.id=first_order),first_version,'Deposit checkouts preserve existing payment versions');
    PERFORM assert_eq((SELECT workflow_state FROM public.email_messages WHERE id=first_message),'pending','Deposit checkouts preserve existing reminder intents');
END $$;
