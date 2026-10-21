-- Rename table
ALTER TABLE eshop.transactions_log RENAME TO transactions_parser_log;

-- Drop old function
DROP FUNCTION IF EXISTS public.log_transactions_log(bigint, text, text, text);

-- Create new function
CREATE OR REPLACE FUNCTION public.log_transactions_parser_log(
    p_bank_account_id bigint,
    p_external_id text,
    p_raw_data text,
    p_message text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, eshop, extensions
AS $$
BEGIN
    INSERT INTO eshop.transactions_parser_log (bank_account_id, external_id, raw_email, error_message, created_at)
    VALUES (p_bank_account_id, p_external_id, p_raw_data, p_message, now());
END;
$$;

REVOKE ALL ON FUNCTION public.log_transactions_parser_log(bigint, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_transactions_parser_log(bigint, text, text, text) TO service_role;
