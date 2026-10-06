BEGIN;

DO $$
DECLARE
    v_ba_id BIGINT;
    v_pi_id BIGINT;
    v_order_id BIGINT;
    v_tx_json JSONB;
    v_res JSONB;
    v_state TEXT;
    v_paid NUMERIC;
    v_ts TEXT;
BEGIN
    RAISE NOTICE 'Starting Debug Test...';

    -- 1. Create Bank Account
    INSERT INTO eshop.bank_accounts (title, type, supported_currencies, account_number)
    VALUES ('Debug Bank', 'FIO', ARRAY['CZK'], '999999/2010')
    RETURNING id INTO v_ba_id;
    RAISE NOTICE 'Bank Account ID: %', v_ba_id;

    -- 2. Create Payment Info & Order
    INSERT INTO eshop.payment_info (amount, currency_code, variable_symbol, paid, bank_account)
    VALUES (200.00, 'CZK', 88887777, 0, v_ba_id)
    RETURNING id INTO v_pi_id;

    INSERT INTO eshop.orders (order_sequence, order_symbol, payment_info, price, currency_code, state, occasion)
    VALUES (public.next_order_sequence(1), public.generate_order_symbol(), v_pi_id, 200.00, 'CZK', 'ordered', 1)
    RETURNING id INTO v_order_id;

    RAISE NOTICE 'Order ID: %, Payment Info ID: %', v_order_id, v_pi_id;

    -- 3. Prepare Transaction JSON matching Deno test
    -- column5 = VS "88887777"
    -- column22 = ID "12345678"
    v_tx_json := jsonb_build_array(
        jsonb_build_object(
            'column0', jsonb_build_object('value', '2026-01-25'),
            'column1', jsonb_build_object('value', 200.00),
            'column2', jsonb_build_object('value', 'Test Account'),
            'column5', jsonb_build_object('value', '88887777'),
            'column14', jsonb_build_object('value', 'CZK'),
            'column22', jsonb_build_object('value', 12345678),
            'column25', jsonb_build_object('value', 'Debug FIO')
        )
    );

    -- 4. Call insert_transactions
    v_res := public.insert_transactions(v_tx_json, v_ba_id);
    RAISE NOTICE 'RPC Result: %', v_res;

    -- 5. Verify State
    SELECT state INTO v_state FROM eshop.orders WHERE id = v_order_id;
    SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = v_pi_id;

    RAISE NOTICE 'Final Order State: %', v_state;
    RAISE NOTICE 'Final Paid Amount: %', v_paid;

    IF v_state = 'paid' THEN
        RAISE NOTICE 'TEST PASSED: Order is paid.';
    ELSE
        RAISE WARNING 'TEST FAILED: Order state is % (Expected paid)', v_state;
    END IF;

    -- Force Rollback to clean up
    RAISE EXCEPTION 'Debug Finished (Rollback)';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '%', SQLERRM;
END;
$$;
ROLLBACK;
