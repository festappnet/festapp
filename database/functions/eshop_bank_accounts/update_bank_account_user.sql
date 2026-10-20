CREATE OR REPLACE FUNCTION public.update_bank_account_user(
    p_bank_account_id bigint,
    p_user_email text,
    p_is_admin boolean,
    p_is_support boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_user_id uuid;
BEGIN
    -- Security Check: Caller must be an Admin of the bank account
    IF NOT EXISTS (
        SELECT 1 FROM eshop.bank_account_users 
        WHERE bank_account = p_bank_account_id AND "user" = auth.uid() AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Permission denied: Only bank account admins can manage users.';
    END IF;

    -- Find user by email (assuming email_readonly is populated and unique-ish for lookup)
    -- In a real app, might want a better user lookup, but this fits the pattern
    SELECT id INTO v_user_id FROM public.user_info WHERE email_readonly = p_user_email LIMIT 1;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User not found';
    END IF;

    -- If both flags are false or null, remove the user
    IF (p_is_admin IS NULL OR p_is_admin = false) AND (p_is_support IS NULL OR p_is_support = false) THEN
        DELETE FROM eshop.bank_account_users
        WHERE bank_account = p_bank_account_id AND "user" = v_user_id;
    ELSE
        IF EXISTS (SELECT 1 FROM eshop.bank_account_users WHERE bank_account = p_bank_account_id AND "user" = v_user_id) THEN
            UPDATE eshop.bank_account_users
            SET is_admin = COALESCE(p_is_admin, false), is_support = COALESCE(p_is_support, false)
            WHERE bank_account = p_bank_account_id AND "user" = v_user_id;
        ELSE
            INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin, is_support)
            VALUES (p_bank_account_id, v_user_id, COALESCE(p_is_admin, false), COALESCE(p_is_support, false));
        END IF;
    END IF;
END;
$$;
