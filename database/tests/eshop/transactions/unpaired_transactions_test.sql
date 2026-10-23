BEGIN;

-- Helper to ensure we have a clean slate or isolation
DO $$
DECLARE
    v_user_id uuid;
    v_org_id bigint;
    v_unit_id bigint;
    v_acc_id bigint;
    v_payment_info_id bigint;
    v_trans_email_id bigint;
    v_trans_manual_id bigint;
    v_result jsonb;
BEGIN
    RAISE NOTICE 'Starting Unpaired Transactions Visibility Test...';

    -- 1. Setup Auth
    SELECT id INTO v_user_id FROM auth.users LIMIT 1;
    IF v_user_id IS NULL THEN
        -- Create dummy user if needed, but usually exists in test DB
        v_user_id := gen_random_uuid();
        INSERT INTO auth.users (id) VALUES (v_user_id);
        INSERT INTO public.user_info (id, name, surname) VALUES (v_user_id, 'Test', 'User');
    END IF;
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);

    -- 2. Setup Bank Account
    INSERT INTO eshop.bank_accounts (title, type, supported_currencies, account_number) 
    VALUES ('Test Bank', 'FIO', ARRAY['CZK'], '123456789/2010') 
    RETURNING id INTO v_acc_id;

    -- Make user admin
    INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin) 
    VALUES (v_acc_id, v_user_id, true);

    INSERT INTO public.organizations(title) VALUES('Unpaired account authority') RETURNING id INTO v_org_id;
    INSERT INTO public.units(title,organization) VALUES('Bank manager',v_org_id) RETURNING id INTO v_unit_id;
    INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(v_unit_id,v_user_id,true);
    INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(v_unit_id,v_acc_id);

    -- 3. Create Payment Info (representing a Ticket Order payment request)
    -- Must be linked to the bank account
    INSERT INTO eshop.payment_info (bank_account, amount, currency_code, variable_symbol)
    VALUES (v_acc_id, 1000, 'CZK', 12345)
    RETURNING id INTO v_payment_info_id;

    -- 4. Create UNPAIRED Transactions
    
    -- Transaction A: Imported (Email/API) -> Should be visible
    INSERT INTO eshop.transactions (bank_account_id, amount, currency, date, transaction_type, external_id)
    VALUES (v_acc_id, 1000, 'CZK', now(), 'incoming', 'trans-email-1')
    RETURNING id INTO v_trans_email_id;

    -- Transaction B: Manual -> Should be visible? (Currently filtered out)
    INSERT INTO eshop.transactions (bank_account_id, amount, currency, date, transaction_type, external_id)
    VALUES (v_acc_id, 1000, 'CZK', now(), 'manual', 'trans-manual-1')
    RETURNING id INTO v_trans_manual_id;

    -- 5. Call the function
    v_result := public.get_transactions_for_order_all_available(v_payment_info_id);
    
    RAISE NOTICE 'Result: %', v_result;

    -- 6. Verify
    -- Expect to find Email transaction
    IF NOT (v_result @> jsonb_build_array(jsonb_build_object('id', v_trans_email_id))) THEN
         RAISE EXCEPTION 'Failed to find imported transaction';
    END IF;

    -- Expect to find Manual transaction?
    -- If logic is incorrect, this assertion will fail (or pass depending on what I assert).
    -- I will Assert that it IS found, because manual transactions should be pairable if unpaired.
    IF NOT (v_result @> jsonb_build_array(jsonb_build_object('id', v_trans_manual_id))) THEN
         RAISE EXCEPTION 'Failed to find manual transaction (Fix NOT applied)';
    ELSE
         RAISE NOTICE 'Manual transaction found (Fix verified).';
    END IF;

END $$;

ROLLBACK;
