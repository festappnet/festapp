ALTER TABLE eshop.unit_bank_accounts
ADD COLUMN IF NOT EXISTS priority int NOT NULL DEFAULT 0;

-- Add token_valid_until to eshop.bank_accounts
ALTER TABLE eshop.bank_accounts
ADD COLUMN IF NOT EXISTS token_valid_until timestamptz;

-- Drop generic link function if exists to avoid signature conflicts during dev iterations
DROP FUNCTION IF EXISTS eshop.update_bank_account(bigint, text, text);
DROP FUNCTION IF EXISTS eshop.update_bank_account(bigint, text, text, text);




-- Function to link or unlink bank account to unit
-- If p_priority is NULL, the link is removed.
-- If p_priority is NOT NULL, the link is created or updated.
CREATE OR REPLACE FUNCTION public.link_bank_account_to_unit(
    p_bank_account_id bigint,
    p_unit_id bigint,
    p_priority int
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Strict Check: User must be a MANAGER of the unit to link/unlink bank accounts
    PERFORM check_is_manager_on_unit(p_unit_id);

    IF p_priority IS NULL THEN
        -- Unlink
        DELETE FROM eshop.unit_bank_accounts
        WHERE unit = p_unit_id AND bank_account = p_bank_account_id;
    ELSE
        -- Strict Check: User must also be an ADMIN of the bank account to LINK/UPDATE it
        IF NOT EXISTS (
            SELECT 1 FROM eshop.bank_account_users 
            WHERE bank_account = p_bank_account_id AND "user" = auth.uid() AND is_admin = true
        ) THEN
            RAISE EXCEPTION 'User is not an admin of this bank account.';
        END IF;

        -- Upsert Link
        IF EXISTS (SELECT 1 FROM eshop.unit_bank_accounts WHERE unit = p_unit_id AND bank_account = p_bank_account_id) THEN
            UPDATE eshop.unit_bank_accounts
            SET priority = p_priority
            WHERE unit = p_unit_id AND bank_account = p_bank_account_id;
        ELSE
            INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
            VALUES (p_unit_id, p_bank_account_id, p_priority);
        END IF;

        -- Ensure Creator is Admin (if they are linking, they should be able to manage permissions)
        -- NOTE: If they are linking an existing account where they are already admin, this is redundant but safe.
        IF NOT EXISTS (SELECT 1 FROM eshop.bank_account_users WHERE bank_account = p_bank_account_id AND "user" = auth.uid()) THEN
             INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin, is_support)
             VALUES (p_bank_account_id, auth.uid(), true, true);
        END IF;
    END IF;
END;
$$;

-- Function to get bank accounts where current user is admin (for linking)
DROP FUNCTION IF EXISTS public.get_my_admin_bank_accounts();
CREATE OR REPLACE FUNCTION public.get_my_admin_bank_accounts()
RETURNS TABLE (
    id bigint,
    account_number text,
    title text,
    type text,
    token_masked text,
    token_valid_until timestamptz
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
        ba.token_valid_until
    FROM eshop.bank_accounts ba
    JOIN eshop.bank_account_users bau ON ba.id = bau.bank_account
    LEFT JOIN eshop.secrets s ON ba.secret = s.id
    WHERE bau."user" = auth.uid() AND bau.is_admin = true
    ORDER BY ba.title;
END;
$$;

-- Function to get bank accounts for a unit with details
DROP FUNCTION IF EXISTS public.get_bank_accounts_for_unit_management(bigint);
CREATE OR REPLACE FUNCTION public.get_bank_accounts_for_unit_management(p_unit_id bigint)
RETURNS TABLE (
    id bigint,
    account_number text,
    title text,
    priority int,
    type text,
    is_admin boolean,
    token_masked text,
    token_valid_until timestamptz
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
        ba.token_valid_until
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    LEFT JOIN eshop.secrets s ON ba.secret = s.id
    WHERE uba.unit = p_unit_id
    ORDER BY uba.priority ASC, ba.id ASC;
END;
$$;

-- Function to get users for a bank account
CREATE OR REPLACE FUNCTION public.get_bank_account_users(p_bank_account_id bigint)
RETURNS TABLE (
    user_id uuid,
    email text,
    name text,
    surname text,
    is_admin boolean,
    is_support boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        u.id,
        u.email_readonly,
        u.name,
        u.surname,
        bau.is_admin,
        bau.is_support
    FROM eshop.bank_account_users bau
    JOIN public.user_info u ON bau."user" = u.id
    WHERE bau.bank_account = p_bank_account_id;
END;
$$;

-- Function to update or add a bank account user
CREATE OR REPLACE FUNCTION public.update_bank_account_user(
    p_bank_account_id bigint,
    p_user_email text,
    p_is_admin boolean,
    p_is_support boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Drop remove_bank_account_user function if exists (cleanup)
DROP FUNCTION IF EXISTS eshop.remove_bank_account_user(bigint, uuid);

-- Function to update bank account token (secret)
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

    -- Update validity date only if explicitly provided
    IF p_valid_until IS NOT NULL THEN
        UPDATE eshop.bank_accounts
        SET token_valid_until = p_valid_until,
            is_fetch_enabled = true,
            updated_at = NOW()
        WHERE id = p_bank_account_id;
    END IF;

    IF p_token IS NOT NULL AND p_token <> '' THEN
        IF v_secret_id IS NOT NULL THEN
            UPDATE eshop.secrets
            SET secret = p_token, created_at = now()
            WHERE id = v_secret_id;
            
            -- If token changed, we should reset valid_until unless explicit new date is provided
            -- Here we assume if p_token is passed, we update validity too.
            -- If p_valid_until is NULL (default), this clears it.
            UPDATE eshop.bank_accounts
            SET token_valid_until = p_valid_until,
                is_fetch_enabled = true,
                updated_at = NOW()
            WHERE id = p_bank_account_id;
        ELSE
            INSERT INTO eshop.secrets (secret)
            VALUES (p_token)
            RETURNING id INTO v_secret_id;

            UPDATE eshop.bank_accounts
            SET secret = v_secret_id,
                token_valid_until = p_valid_until,
                is_fetch_enabled = true,
                updated_at = NOW()
            WHERE id = p_bank_account_id;
        END IF;
    END IF;
END;
$$;

-- Update update_bank_account to handle type
CREATE OR REPLACE FUNCTION public.update_bank_account(
    p_id bigint,
    p_account_number text,
    p_title text,
    p_type text DEFAULT 'FIO',
    p_supported_currencies text[] DEFAULT NULL,
    p_account_number_human_readable text DEFAULT NULL,
    p_unit_id bigint DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id bigint;
    v_account_number text;
BEGIN
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

        INSERT INTO eshop.bank_accounts (account_number, title, type, supported_currencies, account_number_human_readable)
        VALUES (v_account_number, p_title, p_type, p_supported_currencies, p_account_number_human_readable)
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

        UPDATE eshop.bank_accounts
        SET
            account_number = v_account_number,
            title = p_title,
            type = p_type,
            supported_currencies = p_supported_currencies,
            account_number_human_readable = p_account_number_human_readable,
            updated_at = NOW()
        WHERE id = p_id
        RETURNING id INTO v_id;
    END IF;
    RETURN v_id;
END;
$$;
