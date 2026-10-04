DROP FUNCTION IF EXISTS public.regenerate_bank_account_pairing_code(bigint);
CREATE OR REPLACE FUNCTION public.regenerate_bank_account_pairing_code(p_account_id bigint)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_new_code text;
BEGIN
  PERFORM public.require_legacy_bank_authority(p_account_id);
    -- Check Permissions
    IF NOT EXISTS (
        SELECT 1 FROM eshop.bank_account_users 
        WHERE bank_account = p_account_id AND "user" = auth.uid() AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'ACCESS_DENIED';
    END IF;

    LOOP
        v_new_code := encode(gen_random_bytes(5), 'hex');

        BEGIN
            UPDATE eshop.bank_accounts
            SET pairing_code = v_new_code,
                updated_at = NOW()
            WHERE id = p_account_id;
            
            -- If we are here, update was successful (or row not found, but standard logic applies)
            EXIT; -- Break loop
        EXCEPTION WHEN unique_violation THEN
            -- Collision happened, loop again to generate new code
            RAISE NOTICE 'Pairing code collision for %, retrying...', v_new_code;
        END;
    END LOOP;

    RETURN v_new_code;
END;
$$;

REVOKE ALL ON FUNCTION public.regenerate_bank_account_pairing_code(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regenerate_bank_account_pairing_code(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.regenerate_bank_account_pairing_code(bigint) TO service_role;
