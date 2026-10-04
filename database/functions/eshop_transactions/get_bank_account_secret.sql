CREATE OR REPLACE FUNCTION public.get_bank_account_secret(p_bank_account_id bigint)
RETURNS jsonb
SET search_path = public, extensions AS $$
DECLARE
  v_bank_secret bigint;
  v_secret_rec RECORD;
BEGIN
  PERFORM public.require_legacy_bank_authority(p_bank_account_id);
  -- Fetch the secret associated with the bank account
  SELECT secret
    INTO v_bank_secret
    FROM eshop.bank_accounts
   WHERE id = p_bank_account_id;

  IF v_bank_secret IS NULL THEN
    RAISE EXCEPTION 'Bank account not found or missing secret for id %', p_bank_account_id;
  END IF;

  -- Fetch the secret details from the secrets table
  SELECT secret, expiry_date
    INTO v_secret_rec
    FROM eshop.secrets
   WHERE id = v_bank_secret;

  IF NOT FOUND OR v_secret_rec.secret IS NULL THEN
    RAISE EXCEPTION 'Secret not found or expired for bank account %', p_bank_account_id;
  END IF;

  RETURN to_jsonb(v_secret_rec);
END;
$$ LANGUAGE plpgsql;
