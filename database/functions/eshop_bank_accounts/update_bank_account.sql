DROP FUNCTION IF EXISTS public.update_bank_account(bigint,text,text,text,text[]);
DROP FUNCTION IF EXISTS public.update_bank_account(bigint,text,text,text,text[],text,bigint);
DROP FUNCTION IF EXISTS public.update_bank_account(bigint,text,text,text,text[],text,bigint,text);

CREATE FUNCTION public.update_bank_account(
    p_id bigint,
    p_account_number text,
    p_title text,
    p_type text DEFAULT 'FIO',
    p_supported_currencies text[] DEFAULT NULL,
    p_account_number_human_readable text DEFAULT NULL,
    p_unit_id bigint DEFAULT NULL,
    p_creditor_name text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_id bigint;
    v_account_number text;
BEGIN
    -- Prevent manual manipulation of CASH accounts
    IF p_type = 'CASH' THEN
        RAISE EXCEPTION 'CASH_ACCOUNT_MANUAL_UPDATE_FORBIDDEN';
    END IF;

    -- Input normalization
    v_account_number := TRIM(p_account_number);

    IF p_id IS NULL THEN
        -- Creation: If p_unit_id is provided, enforce that creator is Manager of that unit
        IF p_unit_id IS NOT NULL THEN
             PERFORM check_is_manager_on_unit(p_unit_id);
        END IF;

        -- Check for duplicate account number on insert
        IF EXISTS (SELECT 1 FROM eshop.bank_accounts WHERE account_number = v_account_number) THEN
             RAISE EXCEPTION 'ACCOUNT_NUMBER_EXISTS';
        END IF;

        INSERT INTO eshop.bank_accounts (account_number, title, type, supported_currencies, account_number_human_readable, creditor_name)
        VALUES (v_account_number, p_title, p_type, p_supported_currencies, p_account_number_human_readable, nullif(trim(p_creditor_name), ''))
        RETURNING id INTO v_id;

        -- Automatically make the creator an Admin
        INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin)
        VALUES (v_id, auth.uid(), true);

        -- Automatically link to unit if provided
        IF p_unit_id IS NOT NULL THEN
             INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
             VALUES (p_unit_id, v_id, 0);
        END IF;
    ELSE
        -- Check for duplicate account number on update (exclude current id)
        IF EXISTS (SELECT 1 FROM eshop.bank_accounts WHERE account_number = v_account_number AND id != p_id) THEN
             RAISE EXCEPTION 'ACCOUNT_NUMBER_EXISTS';
        END IF;

        -- Security Check: Caller must be an Admin of the bank account
        IF NOT EXISTS (
            SELECT 1 FROM eshop.bank_account_users 
            WHERE bank_account = p_id AND "user" = auth.uid() AND is_admin = true
        ) THEN
            RAISE EXCEPTION 'Permission denied: Only bank account admins can update details.';
        END IF;

        PERFORM 1 FROM eshop.bank_accounts WHERE id=p_id FOR UPDATE;
        IF EXISTS (SELECT 1 FROM eshop.bank_sync_connections WHERE bank_account_id=p_id)
          AND EXISTS (SELECT 1 FROM eshop.bank_accounts WHERE id=p_id
            AND (account_number IS DISTINCT FROM v_account_number OR type IS DISTINCT FROM p_type)) THEN
          RAISE EXCEPTION 'BANK_SYNC_ACCOUNT_IDENTITY_IMMUTABLE';
        END IF;
        UPDATE eshop.bank_accounts
        SET
            account_number = v_account_number,
            title = p_title,
            type = p_type,
            supported_currencies = p_supported_currencies,
            account_number_human_readable = p_account_number_human_readable,
            creditor_name = nullif(trim(p_creditor_name), ''),
            updated_at = NOW()
        WHERE id = p_id
        RETURNING id INTO v_id;
    END IF;
    RETURN v_id;
END;
$$;
