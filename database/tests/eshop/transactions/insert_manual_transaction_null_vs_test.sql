-- Verify: insert_manual_transaction with NULL variable_symbol and explicit payment_info_id
-- correctly links the transaction to the specified payment_info row.

DO $$
DECLARE
    v_org_id bigint;
    v_unit_id bigint;
    v_user_id uuid := gen_random_uuid();
    v_bank_id bigint;
    v_pi_id bigint;
    v_paid_amount numeric;
    v_trans_record eshop.transactions%ROWTYPE;
BEGIN
    -- 1. Setup: org, unit, mock user (manager)
    INSERT INTO public.organizations (title) VALUES ('Test Org IMT NullVS') RETURNING id INTO v_org_id;
    INSERT INTO public.units (organization, title) VALUES (v_org_id, 'Test Unit IMT NullVS') RETURNING id INTO v_unit_id;

    INSERT INTO auth.users (id, email) VALUES (v_user_id, 'test_imt_nullvs_' || v_user_id || '@example.com');
    INSERT INTO public.user_info (id, email_readonly) VALUES (v_user_id, 'test_imt_nullvs_' || v_user_id || '@example.com');
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);
    INSERT INTO public.unit_users (unit, "user", is_manager) VALUES (v_unit_id, v_user_id, true);

    -- 2. Setup: bank account + payment_info
    INSERT INTO eshop.bank_accounts (title, account_number, type, supported_currencies)
    VALUES ('FIO Account IMT NullVS', 'TEST-' || floor(random()*1000000)::text || '/2010', 'FIO', ARRAY['CZK'])
    RETURNING id INTO v_bank_id;

    INSERT INTO eshop.payment_info (variable_symbol, amount, currency_code, bank_account, paid)
    VALUES (floor(random()*1000000000)::bigint, 200.0, 'CZK', v_bank_id, 0)
    RETURNING id INTO v_pi_id;

    -- 3. Call RPC: NULL VS, explicit payment_info_id link
    PERFORM public.insert_manual_transaction(
        200.0::double precision,
        'CZK',
        v_unit_id::integer,
        NULL,
        '2024-01-01T12:00:00Z',
        'Test Explicit Link',
        v_pi_id::integer
    );

    -- 4. Verify: transaction with NULL vs exists
    SELECT * INTO v_trans_record
    FROM eshop.transactions
    WHERE amount = 200.0
    AND currency = 'CZK'
    AND vs IS NULL
    AND transaction_type = 'manual'
    AND payment_info = v_pi_id
    LIMIT 1;

    IF v_trans_record IS NULL THEN
        RAISE EXCEPTION 'Transaction with NULL VS was NOT inserted or not linked to payment_info %', v_pi_id;
    END IF;

    -- Verify: payment_info.paid updated
    SELECT paid INTO v_paid_amount FROM eshop.payment_info WHERE id = v_pi_id;
    IF v_paid_amount <> 200.0 THEN
        RAISE EXCEPTION 'Payment info PAID amount mismatch. Expected 200.0, got %', v_paid_amount;
    END IF;

    RAISE NOTICE 'Test Passed: Transaction inserted with NULL VS and explicitly linked to payment_info %.', v_pi_id;
END $$;
