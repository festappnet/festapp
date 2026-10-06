-- Verify: insert_manual_transaction creates CASH account lazily, inserts manual
-- transaction, links it to payment_info, and triggers order → 'paid' state.

DO $$
DECLARE
    v_org_id bigint;
    v_unit_id bigint;
    v_user_id uuid := gen_random_uuid();
    v_bank_id bigint;
    v_pi_id bigint;
    v_occasion_id bigint;
    v_order_id bigint;
    v_vs text := floor(random()*1000000000)::text;
    v_acc_id int;
    v_paid_amount numeric;
    v_order_state text;
    v_trans_record eshop.transactions%ROWTYPE;
BEGIN
    -- 1. Setup: org, unit, mock user (manager)
    INSERT INTO public.organizations (title) VALUES ('Test Org IMT') RETURNING id INTO v_org_id;
    INSERT INTO public.units (organization, title) VALUES (v_org_id, 'Test Unit IMT') RETURNING id INTO v_unit_id;

    INSERT INTO auth.users (id, email) VALUES (v_user_id, 'test_imt_' || v_user_id || '@example.com');
    INSERT INTO public.user_info (id, email_readonly) VALUES (v_user_id, 'test_imt_' || v_user_id || '@example.com');
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);
    INSERT INTO public.unit_users (unit, "user", is_manager) VALUES (v_unit_id, v_user_id, true);

    -- 2. Setup: bank account + payment_info + order
    INSERT INTO eshop.bank_accounts (title, account_number, type, supported_currencies)
    VALUES ('FIO Account IMT', 'TEST-' || floor(random()*1000000)::text || '/2010', 'FIO', ARRAY['CZK'])
    RETURNING id INTO v_bank_id;

    INSERT INTO eshop.payment_info (variable_symbol, amount, currency_code, bank_account, paid)
    VALUES (v_vs::bigint, 200.0, 'CZK', v_bank_id, 0)
    RETURNING id INTO v_pi_id;

    INSERT INTO public.occasions (unit, title, link, start_time, end_time)
    VALUES (v_unit_id, 'Test Occasion IMT', 'test-link-imt-' || floor(random()*1000000)::text, now(), now() + interval '1 day')
    RETURNING id INTO v_occasion_id;

    INSERT INTO eshop.orders (order_symbol, occasion, payment_info, state, price, currency_code)
    VALUES (public.generate_order_symbol(), v_occasion_id, v_pi_id, 'created', 200.0, 'CZK')
    RETURNING id INTO v_order_id;

    -- 3. Call the RPC (Pay 200 CZK CASH manually — full payment)
    PERFORM public.insert_manual_transaction(
        200.0::double precision,
        'CZK',
        v_unit_id::integer,
        v_vs,
        '2024-01-01 12:00:00',
        'Test Note'
    );

    -- 4. Verify: CASH account was lazy-created on the unit
    SELECT ba.id INTO v_acc_id
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    WHERE uba.unit = v_unit_id
    AND 'CZK' = ANY(ba.supported_currencies)
    AND ba.type = 'CASH';

    IF v_acc_id IS NULL THEN
        RAISE EXCEPTION 'CASH account was NOT lazy-created';
    END IF;

    -- Verify: transaction inserted
    SELECT * INTO v_trans_record
    FROM eshop.transactions
    WHERE bank_account_id = v_acc_id
    AND amount = 200.0
    AND currency = 'CZK'
    AND vs = v_vs
    AND transaction_type = 'manual'
    LIMIT 1;

    IF v_trans_record IS NULL THEN
        RAISE EXCEPTION 'Transaction was NOT inserted correctly';
    END IF;

    -- Verify: NOTE (mapped to message_for_recipient)
    IF v_trans_record.message_for_recipient IS DISTINCT FROM 'Test Note' THEN
        RAISE EXCEPTION 'Transaction NOTE mismatch. Expected "Test Note", got %', v_trans_record.message_for_recipient;
    END IF;

    -- Verify: payment_info.paid updated to 200
    SELECT paid INTO v_paid_amount FROM eshop.payment_info WHERE id = v_pi_id;
    IF v_paid_amount IS NULL OR v_paid_amount != 200.0 THEN
        RAISE EXCEPTION 'Payment Info was NOT updated. Expected 200.0, got %', v_paid_amount;
    END IF;

    -- Verify: order state transitioned to 'paid'
    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    IF v_order_state != 'paid' THEN
        RAISE EXCEPTION 'Order state was NOT updated to paid. Current state: %', v_order_state;
    END IF;

    RAISE NOTICE 'Test Passed: CASH account created, transaction inserted with NOTE, payment info updated, and order marked PAID.';
END $$;
