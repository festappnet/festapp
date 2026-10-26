CREATE OR REPLACE FUNCTION public.link_bank_account_to_unit(
    p_bank_account_id bigint,
    p_unit_id bigint,
    p_priority int,
    p_hard boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_conflict_data jsonb;
    v_is_reordering boolean;
BEGIN
    PERFORM public.check_bank_account_writable(p_bank_account_id);
    v_is_reordering := EXISTS (
        SELECT 1 FROM eshop.unit_bank_accounts
        WHERE unit = p_unit_id AND bank_account = p_bank_account_id
    );
    IF p_priority IS NULL OR v_is_reordering THEN
        IF NOT public.can_manage_unit_bank_accounts(p_unit_id) THEN
            RAISE insufficient_privilege USING MESSAGE='User is not manager.';
        END IF;
    ELSIF NOT public.can_link_bank_account_to_unit(p_bank_account_id,p_unit_id) THEN
        RAISE EXCEPTION 'User is not an admin of this bank account or manager of the target unit.' USING ERRCODE='42501';
    END IF;

    IF p_priority IS NULL THEN
        -- Unlink Logic

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
                JOIN eshop.products p2 ON ff.product_type = p2.product_type
                WHERE o.unit = p_unit_id
                  AND f.is_open = true
                  -- AND p.is_hidden = false -- Removed is_hidden check? Original SQL had it. Let's keep it tight.
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
        -- Link or Update Priority
        IF v_is_reordering THEN
            UPDATE eshop.unit_bank_accounts
            SET priority = p_priority
            WHERE unit = p_unit_id AND bank_account = p_bank_account_id;
        ELSE
            INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
            VALUES (p_unit_id, p_bank_account_id, p_priority);

        END IF;
    END IF;
END;
$$;
