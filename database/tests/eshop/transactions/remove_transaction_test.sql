-- Test: Remove Transactions (Delete Manual vs Unlink Bank)
-- 1. Setup Data

-- Create Org/Unit
INSERT INTO organizations (id, title) VALUES (888, 'RemoveTest Org');
INSERT INTO units (id, organization, title) VALUES (888, 888, 'RemoveTest Unit');

-- Mock Auth User
DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES ('00000000-0000-0000-0000-000000000002', 'remover@example.com');
    INSERT INTO public.user_info (id, email_readonly) VALUES ('00000000-0000-0000-0000-000000000002', 'remover@example.com');

    -- Mock Session
    PERFORM set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
END $$;

-- Setup Bank Accounts
-- 1. FIO Account (The primary account for the payment info)
INSERT INTO eshop.bank_accounts (id, title, account_number, type, supported_currencies)
VALUES (2000, 'FIO Account', '2222/2010', 'FIO', ARRAY['CZK']);

-- 2. CASH Account (For manual transactions)
INSERT INTO eshop.bank_accounts (id, title, account_number, type, supported_currencies)
VALUES (2001, 'Cash Desk', 'CASH', 'cash', ARRAY['CZK']);


-- Grant Admin Access to User for FIO Account (needed for removal security check)
INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin)
VALUES (2000, '00000000-0000-0000-0000-000000000002', true);

-- Link Accounts to Unit (optional for this specific test mostly, but good for consistency)
INSERT INTO eshop.unit_bank_accounts (unit, bank_account) VALUES (888, 2000);
INSERT INTO eshop.unit_bank_accounts (unit, bank_account) VALUES (888, 2001);

-- Grant Admin Access to User for FIO Account AND Cash Account
INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin)
VALUES (2000, '00000000-0000-0000-0000-000000000002', true);

INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin)
VALUES (2001, '00000000-0000-0000-0000-000000000002', true);

-- Setup Occasion (needed for check_is_editor_order_on_occasion)
INSERT INTO occasions (id, unit, title, link, start_time, end_time)
VALUES (888, 888, 'RemoveTest Occasion', 'remove-test', now(), now() + interval '1 day');

-- Grant Editor Access to User for Unit/Occasion (Check via unit_users is_manager or similar)
INSERT INTO public.unit_users (unit, "user", is_manager) VALUES (888, '00000000-0000-0000-0000-000000000002', true);
INSERT INTO public.occasion_users (occasion, "user", is_manager, is_editor, is_editor_order)
VALUES (888, '00000000-0000-0000-0000-000000000002', true, true, true);


-- Setup Order & Payment Info
INSERT INTO eshop.payment_info (id, variable_symbol, amount, currency_code, bank_account, created_at, paid)
VALUES (3000, 999999999, 500.0, 'CZK', 2000, now(), 300.0);

INSERT INTO eshop.orders (order_sequence, order_symbol, id, occasion, payment_info, state, price, currency_code, created_at)
VALUES (public.next_order_sequence(888), public.generate_order_symbol(), 6000, 888, 3000, 'created', 500.0, 'CZK', now());

-- Canonical aggregates are derived from linked source rows. This existing
-- 200 CZK movement is the baseline that remains after each tested removal.
INSERT INTO eshop.transactions (
  payment_info, bank_account_id, amount, currency, vs, transaction_type, date, transaction_id
) VALUES (
  3000, 2000, 200.0, 'CZK', '999999999', 'incoming', now(), 987654320
);


-- TEST CASE 1: Delete Manual Transaction
DO $$
DECLARE
    v_trans_id bigint;
    v_paid numeric;
BEGIN
    -- Insert a Manual Transaction linked to this payment info
    INSERT INTO eshop.transactions (
        payment_info, bank_account_id, amount, currency, vs, transaction_type, date, transaction_id
    ) VALUES (
        3000, 2001, 100.0, 'CZK', '999999999', 'manual', now(), -123456
    ) RETURNING id INTO v_trans_id;

    -- Pre-Verify: Paid is 300 (set in insert above)
    -- We want to remove this 100.

    -- Call Delete RPC
    PERFORM public.delete_manual_transaction_ws(v_trans_id, 3000);

    -- Verify 1: Transaction should be GONE
    PERFORM 1 FROM eshop.transactions WHERE id = v_trans_id;
    IF FOUND THEN
        RAISE EXCEPTION 'Manual Transaction % should have been deleted, but was found.', v_trans_id;
    END IF;

    -- Verify 2: Payment Info Paid should decrease by 100 (300 -> 200)
    SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = 3000;

    IF v_paid != 200.0 THEN
        RAISE EXCEPTION 'Payment Info Paid amount wrong after delete. Expected 200.0, got %', v_paid;
    END IF;

    RAISE NOTICE 'Test Case 1 (Delete Manual) PASSED';
END $$;


-- TEST CASE 2: Unlink Bank Transaction
DO $$
DECLARE
    v_trans_id bigint;
    v_paid numeric;
BEGIN
    -- Insert a Standard Bank Transaction linked to this payment info
    INSERT INTO eshop.transactions (
        payment_info, bank_account_id, amount, currency, vs, transaction_type, date, transaction_id
    ) VALUES (
        3000, 2000, 100.0, 'CZK', '999999999', 'incoming', now(), 987654321
    ) RETURNING id INTO v_trans_id;

    -- Update Payment Info Paid back to 300 for this test (200 + 100 newly added logic-wise? No, manual insert above didn't auto-update paid, we relied on initial state.
    -- Let's set paid explicitly to match the scenario where this transaction contributed to the balance.
    UPDATE eshop.payment_info SET paid = 300.0 WHERE id = 3000;

    -- Call Remove (Unlink) RPC
    PERFORM public.remove_transaction_from_payment_info_ws(v_trans_id, 3000);

    -- Verify 1: Transaction should STILL EXIST but payment_info is NULL
    PERFORM 1 FROM eshop.transactions WHERE id = v_trans_id AND payment_info IS NULL;
    IF NOT FOUND THEN
         RAISE EXCEPTION 'Bank Transaction % should exist with NULL payment_info, but was not found or is still linked.', v_trans_id;
    END IF;

    -- Verify 2: Payment Info Paid should decrease by 100 (300 -> 200)
    SELECT paid INTO v_paid FROM eshop.payment_info WHERE id = 3000;

    IF v_paid != 200.0 THEN
        RAISE EXCEPTION 'Payment Info Paid amount wrong after unlink. Expected 200.0, got %', v_paid;
    END IF;

    RAISE NOTICE 'Test Case 2 (Unlink Bank) PASSED';
END $$;

ROLLBACK;
