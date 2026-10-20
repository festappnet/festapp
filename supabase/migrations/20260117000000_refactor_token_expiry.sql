-- Refactor token_valid_until to token_expiry_date using eshop.secrets.expiry_date

-- 1. Drop old column if it exists (it shouldn't in prod, but for safety in dev envs)
DO $$
BEGIN
    IF EXISTS(SELECT 1
              FROM information_schema.columns
              WHERE table_schema = 'eshop'
              AND table_name = 'bank_accounts'
              AND column_name = 'token_valid_until') THEN
        ALTER TABLE eshop.bank_accounts DROP COLUMN token_valid_until;
    END IF;
END $$;


-- 2. Update functions to use eshop.secrets.expiry_date

-- Drop functions first to handle return type changes (42P13)
DROP FUNCTION IF EXISTS public.get_my_admin_bank_accounts();
DROP FUNCTION IF EXISTS public.get_bank_accounts_for_unit_management(bigint);

-- Update get_my_admin_bank_accounts
CREATE OR REPLACE FUNCTION public.get_my_admin_bank_accounts()
RETURNS TABLE (
    id bigint,
    account_number text,
    account_number_human_readable text,
    title text,
    type text,
    token_masked text,
    token_expiry_date timestamptz,
    supported_currencies text[],
    linked_units text[],
    last_fetch_time timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ba.id,
        ba.account_number,
        ba.account_number_human_readable,
        ba.title,
        ba.type,
        CASE WHEN s.secret IS NULL THEN NULL
             WHEN length(s.secret) <= 4 THEN '************'
             ELSE '************' || right(s.secret, 4)
        END as token_masked,
        s.expiry_date as token_expiry_date,
        ba.supported_currencies,
        ARRAY(
            SELECT u.title 
            FROM eshop.unit_bank_accounts uba
            JOIN public.units u ON uba.unit = u.id
            WHERE uba.bank_account = ba.id
        ) as linked_units,
        ba.last_fetch_time
    FROM eshop.bank_accounts ba
    JOIN eshop.bank_account_users bau ON ba.id = bau.bank_account
    LEFT JOIN eshop.secrets s ON ba.secret = s.id
    WHERE bau."user" = auth.uid() AND bau.is_admin = true
    ORDER BY ba.title;
END;
$$;


-- Update get_bank_accounts_for_unit_management
CREATE OR REPLACE FUNCTION public.get_bank_accounts_for_unit_management(p_unit_id bigint)
RETURNS TABLE (
    id bigint,
    account_number text,
    account_number_human_readable text,
    title text,
    priority int,
    type text,
    is_admin boolean,
    token_masked text,
    token_expiry_date timestamptz,
    supported_currencies text[],
    last_fetch_time timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ba.id,
        ba.account_number,
        ba.account_number_human_readable,
        ba.title,
        uba.priority,
        ba.type,
        EXISTS(SELECT 1 FROM eshop.bank_account_users bau WHERE bau.bank_account = ba.id AND bau."user" = auth.uid() AND bau.is_admin = true) as is_admin,
        CASE WHEN s.secret IS NULL THEN NULL
             WHEN length(s.secret) <= 4 THEN '************'
             ELSE '************' || right(s.secret, 4)
        END as token_masked,
        s.expiry_date as token_expiry_date,
        ba.supported_currencies,
        ba.last_fetch_time
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    LEFT JOIN eshop.secrets s ON ba.secret = s.id
    WHERE uba.unit = p_unit_id
    AND ba.type != 'CASH'
    ORDER BY uba.priority ASC, ba.id ASC;
END;
$$;

-- Update update_bank_account_token
CREATE OR REPLACE FUNCTION public.update_bank_account_token(
    p_bank_account_id bigint,
    p_token text,
    p_valid_until timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_secret_id bigint;
BEGIN
    SELECT secret INTO v_secret_id FROM eshop.bank_accounts WHERE id = p_bank_account_id;

    -- Security Check: Caller must be an Admin of the bank account
    IF NOT EXISTS (
        SELECT 1 FROM eshop.bank_account_users 
        WHERE bank_account = p_bank_account_id AND "user" = auth.uid() AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Permission denied: Only bank account admins can update tokens.';
    END IF;

    -- Update validity date only if explicitly provided along with token or just standalone?
    -- Logic: If token is updated, invalidates expiry unless provided.
    
    IF p_token IS NOT NULL AND p_token <> '' THEN
        IF v_secret_id IS NOT NULL THEN
            UPDATE eshop.secrets
            SET secret = p_token, 
                created_at = now(),
                expiry_date = p_valid_until
            WHERE id = v_secret_id;
            
            UPDATE eshop.bank_accounts
            SET is_fetch_enabled = true,
                updated_at = NOW()
            WHERE id = p_bank_account_id;
        ELSE
            INSERT INTO eshop.secrets (secret, expiry_date)
            VALUES (p_token, p_valid_until)
            RETURNING id INTO v_secret_id;

            UPDATE eshop.bank_accounts
            SET secret = v_secret_id,
                is_fetch_enabled = true,
                updated_at = NOW()
            WHERE id = p_bank_account_id;
        END IF;
    ELSE
        -- If only updating validity date
        IF p_valid_until IS NOT NULL AND v_secret_id IS NOT NULL THEN
             UPDATE eshop.secrets
             SET expiry_date = p_valid_until
             WHERE id = v_secret_id;

             UPDATE eshop.bank_accounts
             SET is_fetch_enabled = true,
                 updated_at = NOW()
             WHERE id = p_bank_account_id;
        END IF;
    END IF;
END;
$$;
