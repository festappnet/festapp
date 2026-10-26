-- Verify regenerate_bank_account_pairing_code: token is regenerated to 10 chars,
-- DB row is updated, and the new token is resolvable via lookup RPC.

DO $$
DECLARE
    v_bank_id bigint;
    v_new_token text;
    v_db_token text;
BEGIN
    -- 1. Setup: temp bank account with an initial token
    INSERT INTO eshop.bank_accounts (type, pairing_code)
    VALUES ('FIO', 'init_token')
    RETURNING id INTO v_bank_id;

    -- 2. Execute RPC
    v_new_token := public.regenerate_bank_account_pairing_code(v_bank_id);

    IF v_new_token IS NULL THEN
        RAISE EXCEPTION 'Test Failed: New token is null';
    END IF;

    IF length(v_new_token) != 10 THEN
        RAISE EXCEPTION 'Test Failed: Token length expected 10, got %', length(v_new_token);
    END IF;

    IF v_new_token = 'init_token' THEN
        RAISE EXCEPTION 'Test Failed: Token did not change';
    END IF;

    -- 3. Verify DB update
    SELECT pairing_code INTO v_db_token FROM eshop.bank_accounts WHERE id = v_bank_id;
    IF v_db_token != v_new_token THEN
        RAISE EXCEPTION 'Test Failed: Database not updated. Expected %, got %', v_new_token, v_db_token;
    END IF;

    RAISE NOTICE 'Test Passed: Short token regenerated successfully. Token: %', v_new_token;

    -- 4. Verify lookup RPC by new token
    PERFORM * FROM eshop.get_bank_account_by_pairing_code(v_new_token);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Test Failed: Lookup by token failed';
    END IF;

    RAISE NOTICE 'Test Passed: Lookup successful.';
END $$;
