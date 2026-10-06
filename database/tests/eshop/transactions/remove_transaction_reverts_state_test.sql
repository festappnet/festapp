-- Verify: deleting a manual transaction reverts the order state from 'paid' to 'ordered'
-- and recalculates payment_info.paid back to 0.

DO $$
DECLARE
    v_org_id bigint;
    v_unit_id bigint;
    v_user_id uuid := gen_random_uuid();
    v_bank_id bigint;
    v_pi_id bigint;
    v_occasion_id bigint;
    v_order_id bigint;
    v_state text;
    v_trans_id bigint;
    v_paid numeric;
BEGIN
    -- 1. Setup: org, unit, mock user (manager)
    INSERT INTO public.organizations (title) VALUES ('Test Org RTRS') RETURNING id INTO v_org_id;
    INSERT INTO public.units (organization, title) VALUES (v_org_id, 'Test Unit RTRS') RETURNING id INTO v_unit_id;

    INSERT INTO auth.users (id, email) VALUES (v_user_id, 'test_rtrs_' || v_user_id || '@example.com');
    INSERT INTO public.user_info (id, email_readonly) VALUES (v_user_id, 'test_rtrs_' || v_user_id || '@example.com');
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);
    INSERT INTO public.unit_users (unit, "user", is_manager) VALUES (v_unit_id, v_user_id, true);

    -- 2. Setup: bank account, link to unit + user as admin
    INSERT INTO eshop.bank_accounts (title, account_number, type, supported_currencies)
    VALUES ('FIO Account RTRS', 'TEST-' || floor(random()*1000000)::text || '/2010', 'FIO', ARRAY['CZK'])
    RETURNING id INTO v_bank_id;

    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_bank_id, 1);
    INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin) VALUES (v_bank_id, v_user_id, true);

    -- 3. Setup: occasion + occasion_users (editor_order for transaction ops)
    INSERT INTO public.occasions (unit, title, link, start_time, end_time)
    VALUES (v_unit_id, 'Test Occasion RTRS', 'test-link-rtrs-' || floor(random()*1000000)::text, now(), now() + interval '1 day')
    RETURNING id INTO v_occasion_id;
    INSERT INTO public.occasion_users (occasion, "user", is_manager, is_editor, is_editor_order)
    VALUES (v_occasion_id, v_user_id, true, true, true);

    -- 4. Setup: payment_info (amount 200, paid 0) + order (price 200, state 'ordered')
    INSERT INTO eshop.payment_info (variable_symbol, amount, currency_code, bank_account, paid)
    VALUES (floor(random()*1000000000)::bigint, 200.0, 'CZK', v_bank_id, 0)
    RETURNING id INTO v_pi_id;

    INSERT INTO eshop.orders (order_sequence, order_symbol, occasion, payment_info, state, price, currency_code)
    VALUES (public.next_order_sequence(v_occasion_id), public.generate_order_symbol(), v_occasion_id, v_pi_id, 'ordered', 200.0, 'CZK')
    RETURNING id INTO v_order_id;

    -- 5. Add FULL payment (200 CZK) → order should switch to 'paid'
    PERFORM public.insert_manual_transaction(
        200.0::double precision,
        'CZK',
        v_unit_id::integer,
        NULL,
        '2024-01-01 12:00:00',
        'Full Payment',
        v_pi_id::integer
    );

    SELECT state INTO v_state FROM eshop.orders WHERE id = v_order_id;
    IF v_state != 'paid' THEN RAISE EXCEPTION 'Order should be PAID, got %', v_state; END IF;

    -- 6. Delete the transaction → order should revert to 'ordered'
    SELECT id INTO v_trans_id
    FROM eshop.transactions
    WHERE payment_info = v_pi_id AND message_for_recipient = 'Full Payment'
    LIMIT 1;

    PERFORM public.delete_manual_transaction_ws(v_trans_id, v_pi_id::integer);

    SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = v_pi_id;
    IF v_paid != 0 THEN RAISE EXCEPTION 'Paid amount should be 0 after deletion, got %', v_paid; END IF;

    SELECT state INTO v_state FROM eshop.orders WHERE id = v_order_id;
    IF v_state != 'ordered' THEN
        RAISE EXCEPTION 'Order logic FAILED: State remained % instead of reverting to ordered.', v_state;
    END IF;

    RAISE NOTICE 'Test Passed: Order successfully reverted to ordered after transaction deletion.';
END $$;
