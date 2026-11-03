-- Add last_fetch_time column if missing (though it might exist)
-- Also drop last_fetch_at if it was accidentally added
DO $$
BEGIN
  IF EXISTS(SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'eshop'
            AND table_name = 'bank_accounts'
            AND column_name = 'last_fetch_at') THEN
      ALTER TABLE eshop.bank_accounts DROP COLUMN last_fetch_at;
  END IF;

  -- Ensure last_fetch_time exists (it should per schema, but for safety)
  IF NOT EXISTS(SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'eshop'
            AND table_name = 'bank_accounts'
            AND column_name = 'last_fetch_time') THEN
      ALTER TABLE eshop.bank_accounts ADD COLUMN last_fetch_time timestamptz;
  END IF;
END $$;

-- Drop valid for 42P13
DROP FUNCTION IF EXISTS public.get_my_admin_bank_accounts();

-- Update get_my_admin_bank_accounts
CREATE OR REPLACE FUNCTION public.get_my_admin_bank_accounts()
RETURNS TABLE (
    id bigint,
    account_number text,
    title text,
    type text,
    token_masked text,
    token_valid_until timestamptz,
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
        ba.title,
        ba.type,
        CASE WHEN s.secret IS NULL THEN NULL
             WHEN length(s.secret) <= 4 THEN '****'
             ELSE '************' || right(s.secret, 4) -- Keep the 12 asterisk masking
        END as token_masked,
        ba.token_valid_until,
        ba.supported_currencies,
        ARRAY(
            SELECT u.title 
            FROM eshop.unit_bank_accounts uba
            JOIN public.units u ON uba.unit_id = u.id
            WHERE uba.bank_account_id = ba.id
        ) as linked_units,
        ba.last_fetch_time
    FROM eshop.bank_accounts ba
    JOIN eshop.bank_account_users bau ON ba.id = bau.bank_account
    LEFT JOIN eshop.secrets s ON ba.secret = s.id
    WHERE bau."user" = auth.uid() AND bau.is_admin = true
    ORDER BY ba.title;
END;
$$;

-- Drop valid for 42P13
DROP FUNCTION IF EXISTS public.get_bank_accounts_for_unit_management(bigint);

-- Update get_bank_accounts_for_unit_management
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
        ba.title,
        uba.priority,
        ba.type,
        EXISTS(SELECT 1 FROM eshop.bank_account_users bau WHERE bau.bank_account = ba.id AND bau."user" = auth.uid() AND bau.is_admin = true) as is_admin,
        CASE WHEN s.secret IS NULL THEN NULL
             WHEN length(s.secret) <= 4 THEN '****'
             ELSE '************' || right(s.secret, 4) -- Keep the 12 asterisk masking
        END as token_masked,
        ba.token_valid_until,
        ba.supported_currencies,
        ba.last_fetch_time
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    LEFT JOIN eshop.secrets s ON ba.secret = s.id
    WHERE uba.unit = p_unit_id
    ORDER BY uba.priority ASC, ba.id ASC;
END;
$$;
