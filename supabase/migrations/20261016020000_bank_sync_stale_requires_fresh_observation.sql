-- Source: database/functions/eshop_bank_sync/bank_sync_health.sql (bank_sync_problem only)
CREATE OR REPLACE FUNCTION public.bank_sync_problem(p_connection_id bigint)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
  SELECT CASE
    WHEN c.state='suspended' THEN 'suspended'
    WHEN c.state IN ('provisioning','shadow') THEN 'not_configured'
    WHEN c.mode='email' AND c.pairing_code IS NULL THEN 'email_missing'
    WHEN c.mode='api' AND h.token_present IS FALSE THEN 'token_missing'
    WHEN h.ingest_enabled IS FALSE OR (c.mode='api' AND h.polling_enabled IS FALSE) THEN 'bank_error'
    WHEN c.last_error IS NOT NULL OR c.state='degraded' THEN 'bank_error'
    -- bank_pull_at is a local copy of BankSync's successful pull timestamp.
    -- Only a fresh remote health observation can prove that polling stalled;
    -- an unmonitored or expired snapshot is not evidence of a bank failure.
    WHEN c.mode='api' AND h.checked_at>now()-interval '10 minutes'
      AND COALESCE(c.bank_pull_at,c.created_at)<now()-interval '30 minutes' THEN 'stale'
    ELSE NULL END
  FROM eshop.bank_sync_connections c LEFT JOIN eshop.bank_sync_health h ON h.connection_id=c.id
  WHERE c.id=p_connection_id;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_problem(bigint) FROM PUBLIC,anon,authenticated,service_role;
