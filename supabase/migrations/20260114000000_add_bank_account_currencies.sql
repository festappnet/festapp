-- Add supported_currencies column
ALTER TABLE eshop.bank_accounts
ADD COLUMN IF NOT EXISTS supported_currencies text[];

-- Backfill existing accounts with CZK
UPDATE eshop.bank_accounts SET supported_currencies = ARRAY['CZK'] WHERE supported_currencies IS NULL;

-- Update public.update_bank_account to accept currencies
CREATE OR REPLACE FUNCTION public.update_bank_account(
    p_id bigint,
    p_account_number text,
    p_title text,
    p_type text DEFAULT 'FIO',
    p_supported_currencies text[] DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id bigint;
BEGIN
    IF p_id IS NULL THEN
        INSERT INTO eshop.bank_accounts (account_number, title, type, supported_currencies)
        VALUES (p_account_number, p_title, p_type, p_supported_currencies)
        RETURNING id INTO v_id;
    ELSE
        UPDATE eshop.bank_accounts
        SET
            account_number = p_account_number,
            title = p_title,
            type = p_type,
            supported_currencies = p_supported_currencies
        WHERE id = p_id
        RETURNING id INTO v_id;
    END IF;
    RETURN v_id;
END;
$$;

-- Drop first to avoid return type conflict (42P13)
DROP FUNCTION IF EXISTS public.get_my_admin_bank_accounts();

-- Update public.get_my_admin_bank_accounts to return currencies and linked units
CREATE OR REPLACE FUNCTION public.get_my_admin_bank_accounts()
RETURNS TABLE (
    id bigint,
    account_number text,
    title text,
    type text,
    token_masked text,
    token_valid_until timestamptz,
    supported_currencies text[],
    linked_units text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ba.id,
        ba.account_number,
        ba.title,
        ba.type,
        CASE WHEN s.secret IS NULL THEN NULL
             WHEN length(s.secret) <= 4 THEN '****'
             ELSE '****' || right(s.secret, 4)
        END as token_masked,
        ba.token_valid_until,
        ba.supported_currencies,
        ARRAY(
            SELECT u.name 
            FROM eshop.unit_bank_accounts uba
            JOIN public.units u ON uba.unit = u.id
            WHERE uba.bank_account = ba.id
        ) as linked_units
    FROM eshop.bank_accounts ba
    JOIN eshop.bank_account_users bau ON ba.id = bau.bank_account
    LEFT JOIN eshop.secrets s ON ba.secret = s.id
    WHERE bau."user" = auth.uid() AND bau.is_admin = true
    ORDER BY ba.title;
END;
$$;

-- Drop first to avoid return type conflict (42P13)
DROP FUNCTION IF EXISTS public.get_bank_accounts_for_unit_management(bigint);

-- Update public.get_bank_accounts_for_unit_management to return currencies
CREATE OR REPLACE FUNCTION public.get_bank_accounts_for_unit_management(p_unit_id bigint)
RETURNS TABLE (
    id bigint,
    account_number text,
    title text,
    priority int,
    type text,
    is_admin boolean,
    token_masked text,
    token_valid_until timestamptz,
    supported_currencies text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ba.id,
        ba.account_number,
        ba.title,
        uba.priority,
        ba.type,
        EXISTS(SELECT 1 FROM eshop.bank_account_users bau WHERE bau.bank_account = ba.id AND bau."user" = auth.uid() AND bau.is_admin = true) as is_admin,
        CASE WHEN s.secret IS NULL THEN NULL
             WHEN length(s.secret) <= 4 THEN '****'
             ELSE '****' || right(s.secret, 4)
        END as token_masked,
        ba.token_valid_until,
        ba.supported_currencies
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    LEFT JOIN eshop.secrets s ON ba.secret = s.id
    WHERE uba.unit = p_unit_id
    ORDER BY uba.priority ASC, ba.id ASC;
END;
$$;
