CREATE OR REPLACE FUNCTION public.get_fetchable_bank_accounts_for_unit(p_unit_id bigint)
RETURNS TABLE (bank_account_id bigint, bank_secret text, account_type text)
SET search_path = public, extensions AS $$
BEGIN
  RETURN QUERY
  SELECT
    ba.id,
    s.secret,
    ba.type
  FROM eshop.bank_accounts ba
  JOIN eshop.secrets s ON ba.secret = s.id
  JOIN eshop.unit_bank_accounts uba ON uba.bank_account = ba.id
  WHERE uba.unit = p_unit_id
    AND ba.is_fetch_enabled = true
    AND NOT EXISTS (SELECT 1 FROM eshop.bank_sync_connections c WHERE c.legacy_blocked_at IS NOT NULL
      AND (c.bank_account_id=ba.id OR c.id IN (SELECT a.connection_id FROM eshop.bank_sync_account_aliases a WHERE a.bank_account_id=ba.id)))
    -- Ensure that the secret has not expired (if an expiry is set)
    AND (s.expiry_date IS NULL OR s.expiry_date > now());
END;
$$ LANGUAGE plpgsql;
