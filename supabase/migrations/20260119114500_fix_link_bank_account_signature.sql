-- Drop the old, ambiguous function signature (3 args)
DROP FUNCTION IF EXISTS public.link_bank_account_to_unit(bigint, bigint, int);

-- Re-create the correct function with the 4th argument (p_hard) and default value
CREATE OR REPLACE FUNCTION public.link_bank_account_to_unit(
    p_bank_account_id bigint,
    p_unit_id bigint,
    p_priority int,
    p_hard boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_conflict_data jsonb;
BEGIN
    -- Strict Check: User must be a MANAGER of the unit to link/unlink bank accounts
    PERFORM check_is_manager_on_unit(p_unit_id);

    IF p_priority IS NULL THEN
        -- Unlink
        
        -- Dependency Check (unless hard)
        IF NOT p_hard THEN
            WITH TargetAcc AS (
                SELECT unnest(supported_currencies) as curr FROM eshop.bank_accounts WHERE id = p_bank_account_id
            ),
            OtherAccs AS (
                SELECT unnest(ba.supported_currencies) as curr
                FROM eshop.unit_bank_accounts uba
                JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
                WHERE uba.unit = p_unit_id AND uba.bank_account != p_bank_account_id
            ),
            LostCurrencies AS (
                SELECT curr FROM TargetAcc
                EXCEPT
                SELECT curr FROM OtherAccs
            ),
            ConflictingForms AS (
                SELECT DISTINCT f.title as form_title, f.link as form_link, p.currency_code, o.title as occasion_title
                FROM public.forms f
                JOIN public.occasions o ON f.occasion = o.id
                JOIN public.form_fields ff ON ff.form = f.id
                JOIN eshop.product_types pt ON ff.product_type = pt.id
                JOIN eshop.products p ON p.product_type = pt.id
                WHERE o.unit = p_unit_id
                  AND f.is_open = true
                  AND p.is_hidden = false
                  AND p.currency_code IN (SELECT curr FROM LostCurrencies)
            )
            SELECT jsonb_agg(jsonb_build_object('form', form_title, 'link', form_link, 'currency', currency_code, 'occasion', occasion_title))
            INTO v_conflict_data
            FROM ConflictingForms;

            IF v_conflict_data IS NOT NULL THEN
                 RAISE EXCEPTION '%', jsonb_build_object(
                    'code', 'LINK_DEPENDENCY_ERROR',
                    'message', 'Cannot unlink bank account because some active forms depend on its currency support.',
                    'conflicts', v_conflict_data
                 )::text;
            END IF;
        END IF;

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
