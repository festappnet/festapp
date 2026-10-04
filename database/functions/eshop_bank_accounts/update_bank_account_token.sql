CREATE OR REPLACE FUNCTION public.update_bank_account_token(
    p_bank_account_id bigint,
    p_token text,
    p_valid_until timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_secret_id bigint;
BEGIN
  PERFORM public.require_legacy_bank_authority(p_bank_account_id);
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
