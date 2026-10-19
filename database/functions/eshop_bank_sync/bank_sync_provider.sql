-- Resolve by physical receiving account, independent of historical UI type.
CREATE OR REPLACE FUNCTION public.bank_sync_provider_for_account(p_account_number text)
RETURNS text LANGUAGE sql IMMUTABLE STRICT SET search_path=public,extensions AS $$
  WITH normalized AS (
    SELECT upper(regexp_replace(p_account_number, '\s', '', 'g')) AS account
  ), bank AS (
    SELECT CASE WHEN account ~ '^CZ[0-9]{22}$' THEN substring(account,5,4)
      ELSE substring(account FROM '/([0-9]{4})$') END AS code FROM normalized
  )
  SELECT CASE code
    WHEN '2010' THEN 'FIO' WHEN '3030' THEN 'AIRBANK'
    WHEN '0300' THEN 'CSOB' WHEN '0600' THEN 'MONETA'
    WHEN '2250' THEN 'CREDITAS' WHEN '5500' THEN 'RAIFFEISENBANK'
    WHEN '2700' THEN 'UNICREDIT' WHEN '0800' THEN 'CSAS'
  END FROM bank;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_provider_for_account(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.bank_sync_provider_for_account(text) TO service_role;
