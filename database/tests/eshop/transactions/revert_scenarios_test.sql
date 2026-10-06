-- Verify: order state revert behaviour in two scenarios:
--   1. Delete payment when order is in 'sent' state — state should NOT revert to 'ordered'
--   2. Insert a negative manual transaction (refund) after full payment

DO $$
DECLARE
    v_org_id bigint;
    v_unit_id bigint;
    v_user_id uuid := gen_random_uuid();
    v_bank_id bigint;
    v_occasion_id bigint;
    v_order_id bigint;
    v_pi_id bigint;
    v_trans_id bigint;
    v_state text;
    v_paid numeric;
    v_returned numeric;
BEGIN
    -- 1. Setup: org, unit, mock user (manager + bank admin + occasion editor)
    INSERT INTO public.organizations (title) VALUES ('Test Org Revert') RETURNING id INTO v_org_id;
    INSERT INTO public.units (organization, title) VALUES (v_org_id, 'Test Unit Revert') RETURNING id INTO v_unit_id;

    INSERT INTO auth.users (id, email, aud, role)
    VALUES (v_user_id, 'test_revert_' || v_user_id || '@example.com', 'authenticated', 'authenticated');
    INSERT INTO public.user_info (id, email_readonly)
    VALUES (v_user_id, 'test_revert_' || v_user_id || '@example.com');
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);
    INSERT INTO public.unit_users (unit, "user", is_manager) VALUES (v_unit_id, v_user_id, true);

    -- 2. Setup: bank account + admin link
    INSERT INTO eshop.bank_accounts (title, account_number, type, supported_currencies)
    VALUES ('FIO Account Revert', 'TEST-' || floor(random()*1000000)::text || '/2010', 'FIO', ARRAY['CZK'])
    RETURNING id INTO v_bank_id;
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_bank_id, 1);
    INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin) VALUES (v_bank_id, v_user_id, true);

    -- 3. Setup: occasion + occasion_users (editor_order required)
    INSERT INTO public.occasions (unit, title, link, start_time, end_time)
    VALUES (v_unit_id, 'Test Occasion Revert', 'test-link-revert-' || floor(random()*1000000)::text, now(), now() + interval '1 day')
    RETURNING id INTO v_occasion_id;
    INSERT INTO public.occasion_users (occasion, "user", is_manager, is_editor, is_editor_order)
    VALUES (v_occasion_id, v_user_id, true, true, true);

    -- =====================================================================
    -- SCENARIO 1: Revert from SENT
    -- =====================================================================
    INSERT INTO eshop.payment_info (variable_symbol, amount, currency_code, bank_account, paid)
    VALUES (1000000 + floor(random() * 1000000)::bigint, 200.0, 'CZK', v_bank_id, 0.0)
    RETURNING id INTO v_pi_id;

    INSERT INTO eshop.orders (order_symbol, occasion, payment_info, state, price, currency_code)
    VALUES (public.generate_order_symbol(), v_occasion_id, v_pi_id, 'ordered', 200.0, 'CZK')
    RETURNING id INTO v_order_id;

    -- Pay full
    PERFORM public.insert_manual_transaction(
        200.0::double precision, 'CZK', v_unit_id::integer, NULL, '2024-01-01', 'Pay', v_pi_id::integer
    );

    -- Manually move to SENT
    UPDATE eshop.orders SET state = 'sent' WHERE id = v_order_id;

    -- Delete the payment
    SELECT id INTO v_trans_id FROM eshop.transactions WHERE payment_info = v_pi_id LIMIT 1;
    PERFORM public.delete_manual_transaction_ws(v_trans_id, v_pi_id::integer);

    SELECT state INTO v_state FROM eshop.orders WHERE id = v_order_id;
    RAISE NOTICE 'Scenario 1 (From Sent): State is %', v_state;

    -- =====================================================================
    -- SCENARIO 2: Insert Negative Transaction (refund) after full payment
    -- =====================================================================
    INSERT INTO eshop.payment_info (variable_symbol, amount, currency_code, bank_account, paid)
    VALUES (2000000 + floor(random() * 1000000)::bigint, 200.0, 'CZK', v_bank_id, 0.0)
    RETURNING id INTO v_pi_id;

    INSERT INTO eshop.orders (order_symbol, occasion, payment_info, state, price, currency_code)
    VALUES (public.generate_order_symbol(), v_occasion_id, v_pi_id, 'ordered', 200.0, 'CZK')
    RETURNING id INTO v_order_id;

    -- Pay full
    PERFORM public.insert_manual_transaction(
        200.0::double precision, 'CZK', v_unit_id::integer, NULL, '2024-01-01', 'Pay', v_pi_id::integer
    );

    -- Insert negative (refund)
    PERFORM public.insert_manual_transaction(
        -200.0::double precision, 'CZK', v_unit_id::integer, NULL, '2024-01-01', 'Refund', v_pi_id::integer
    );

    SELECT state, payment_info INTO v_state, v_pi_id FROM eshop.orders WHERE id = v_order_id;
    SELECT paid, returned INTO v_paid, v_returned FROM eshop.payment_info WHERE id = v_pi_id;

    RAISE NOTICE 'Scenario 2 (Negative Insert): State is %, Paid is %, Returned is %', v_state, v_paid, v_returned;
END $$;
