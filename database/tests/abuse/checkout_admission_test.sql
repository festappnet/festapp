-- Checkout limit errors must survive finalization and rollback atomically.
DO $$
DECLARE
    v_unit_id bigint;
    v_occasion_id bigint;
    v_form_id bigint;
    v_form_key uuid;
    v_product_type_id bigint;
    v_product_id bigint;
    v_spot_id bigint;
    v_blueprint_id bigint;
    v_group_node uuid:=gen_random_uuid();
    v_seat_node uuid:=gen_random_uuid();
    v_acc_id bigint;
    v_secret_id bigint;
    v_input_data jsonb;
    v_result jsonb;
    v_receipt jsonb;
    v_command uuid:=gen_random_uuid();
    v_client uuid:=gen_random_uuid();
    v_user_email text := 'checkout-limit@example.invalid';
    v_user_id uuid;
BEGIN
    PERFORM set_config('festapp.email_wake','scheduled',true);
    -- 1. Setup Full Environment (Self-Contained)

    -- Create User Context (Required for some checks, though usually anonymous is fine for orders)
    SELECT id INTO v_user_id FROM auth.users LIMIT 1;
    -- If no user, mock one? create_ticket_order usually works anonymously.
    -- set_config('request.jwt.claim.sub', ...); -- Not strictly needed for anonymous order.

    -- Create Org & Unit
    INSERT INTO public.organizations (title) VALUES ('Test Org Eshop') RETURNING id INTO v_unit_id; -- Reuse variable for linking, actually separate IDs
    INSERT INTO public.units (title, organization) VALUES ('Test Unit Eshop', v_unit_id) RETURNING id INTO v_unit_id;

    -- Create Bank Account (CZK)
    INSERT INTO eshop.secrets (secret) VALUES ('test_secret_eshop') RETURNING id INTO v_secret_id;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type)
    VALUES ('Test Bank CZK', ARRAY['CZK'], v_secret_id, 'FIO') RETURNING id INTO v_acc_id;

    -- Link Bank Account to Unit
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_acc_id, 1);

    -- Create Occasion
    INSERT INTO public.occasions (organization, title, unit, link, start_time, end_time)
    VALUES ((SELECT organization FROM public.units WHERE id=v_unit_id), 'Test Occasion Eshop', v_unit_id, 'test-occ-eshop-' || floor(random()*100000)::text, now(), now() + interval '1 day')
    RETURNING id INTO v_occasion_id;

    -- Create Form (Open)
    INSERT INTO public.forms (title, occasion, is_open)
    VALUES ('Test Form Eshop', v_occasion_id, true)
    RETURNING id, key INTO v_form_id, v_form_key;

    -- Create Product Type (Spot)
    INSERT INTO eshop.product_types (title, occasion, type)
    VALUES ('Test PT Spot', v_occasion_id, 'spot')
    RETURNING id INTO v_product_type_id;

    -- Create Product (CZK)
    INSERT INTO eshop.products (title, product_type, currency_code, price, is_hidden, occasion)
    VALUES ('Test Product CZK', v_product_type_id, 'CZK', 100, false, v_occasion_id)
    RETURNING id INTO v_product_id;

    -- Link Product to Form
    INSERT INTO public.form_fields (form, product_type) VALUES (v_form_id, v_product_type_id);

    -- Create Spot
    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Test Spot', v_product_id, v_occasion_id, gen_random_uuid())
    RETURNING id INTO v_spot_id;

    INSERT INTO eshop.blueprints(organization,occasion,title) VALUES ((SELECT organization FROM public.units WHERE id=v_unit_id),v_occasion_id,'Seating')
    RETURNING id INTO v_blueprint_id;
    UPDATE public.forms SET blueprint=v_blueprint_id WHERE id=v_form_id;
    UPDATE eshop.spots SET blueprint=v_blueprint_id, secret_expiration_time=now()+interval '10 minutes' WHERE id=v_spot_id;
    UPDATE eshop.blueprints SET layout=jsonb_set(layout,'{nodes}',jsonb_build_array(
     jsonb_build_object('id',v_group_node,'kind','group','label','7','width',1,'height',1,'transform',jsonb_build_object('x',0,'y',0,'rotation',0)),
     jsonb_build_object('id',v_seat_node,'kind','seat','parentId',v_group_node,'width',40,'height',40,'transform',jsonb_build_object('x',60,'y',60,'rotation',0)))) WHERE id=v_blueprint_id;
    INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,group_node)
    VALUES(v_blueprint_id,v_seat_node,v_spot_id,v_group_node);

    -- 2. Construct Order Input
    -- { form: key, email: ..., ticket: [ { spot: spot_id } ] }
    v_input_data := jsonb_build_object(
        'form', v_form_key,
        'email', v_user_email,
        'payment_method', 'bank',
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_id),
        'ticket', jsonb_build_array(
            jsonb_build_object('spot', v_spot_id)
        )
    );

    INSERT INTO eshop.payment_method_policy_scopes(organization_id,preferred_method)
    SELECT organization,'bank' FROM public.units WHERE id=v_unit_id;
    INSERT INTO eshop.organization_payment_method_policies(organization_id,method,enabled)
    SELECT organization,'bank',true FROM public.units WHERE id=v_unit_id;
    UPDATE public.forms SET bank_account=v_acc_id,data='{"payments":{"bankEnabled":true}}'::jsonb WHERE id=v_form_id;
    -- Creating a bank checkout schedules a reminder through real email admission.
    UPDATE public.occasions SET features='[{"code":"form","is_enabled":true,"reminder_is_enabled":true}]'::jsonb WHERE id=v_occasion_id;
    INSERT INTO public.abuse_budget_usage(rule_key,scope_id,bucket_at,amount,expires_at)
    SELECT rule_key,public.abuse_recipient_key_v1(v_user_email),
      date_trunc('hour',clock_timestamp()),base_limit,clock_timestamp()+interval '25 hours'
    FROM public.abuse_policy_rules WHERE rule_key='email.ordinary.recipient.day';

    v_receipt:=public.create_ticket_order_client_sync_v1(v_input_data,v_command,v_client);
    v_result:=v_receipt->'data';
    PERFORM assert_eq((v_result->>'code')::int,429,
      'Email admission during checkout must return capacity error, not generic 1013: '||v_result::text);
    PERFORM assert_eq(v_result->>'errorCode','ABUSE_LIMIT_EXCEEDED','Stable client error code');
    PERFORM assert_true((v_result->>'retryAfterSeconds')::int>0,'Rolling limit carries a useful retry delay');
    PERFORM assert_true(NOT v_result ?| ARRAY['ruleKey','policyRevision'],'Internal rule metadata is not public');
    PERFORM assert_eq(v_receipt->>'status','rejected','Capacity rejection is a definitive command outcome');
    PERFORM assert_eq((SELECT count(*) FROM eshop.orders WHERE occasion=v_occasion_id),0::bigint,'Denied checkout leaves no allocated order');
    PERFORM assert_eq((SELECT count(*) FROM eshop.tickets WHERE occasion=v_occasion_id),0::bigint,'Denied checkout leaves no tickets');
    PERFORM assert_eq((SELECT order_product_ticket IS NULL FROM eshop.spots WHERE id=v_spot_id),true,'Seat remains available');
    DELETE FROM public.abuse_budget_usage WHERE rule_key='email.ordinary.recipient.day'
      AND scope_id=public.abuse_recipient_key_v1(v_user_email);
    PERFORM assert_eq((public.create_ticket_order_client_sync_v1(v_input_data,v_command,v_client)->'data')-'analytics',v_result,
      'Transport replay retains the original rejection after capacity recovers');
    v_receipt:=public.create_ticket_order_client_sync_v1(v_input_data,gen_random_uuid(),v_client);
    PERFORM assert_eq(v_receipt#>>'{data,code}','200','New explicit attempt succeeds when budget is available: '||v_receipt::text);
    PERFORM assert_eq((SELECT count(*) FROM eshop.orders WHERE occasion=v_occasion_id),1::bigint,'Exactly one order exists after retry');
END $$;
