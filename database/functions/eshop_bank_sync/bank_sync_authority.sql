CREATE OR REPLACE FUNCTION public.bank_sync_accounts_match(p_transaction_id bigint,p_target_account bigint)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
  SELECT EXISTS (
    SELECT 1 FROM eshop.transactions t
    JOIN eshop.bank_transaction_identities i ON i.transaction_id=t.id AND i.identity_kind='movement'
    JOIN eshop.bank_sync_connections c ON c.instance_id=i.instance_id AND c.provider=i.provider
      AND c.physical_account=i.physical_account AND c.bank_account_id=t.bank_account_id
    WHERE t.id=p_transaction_id AND t.ingest_source='banksync_api' AND c.legacy_blocked_at IS NOT NULL
      AND (p_target_account=c.bank_account_id OR p_target_account IN
        (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id))
  );
$$;
REVOKE ALL ON FUNCTION public.bank_sync_accounts_match(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.activate_bank_sync_connection(p_connection_id bigint,p_manifest_sha256 text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_connection eshop.bank_sync_connections%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO STRICT v_connection FROM eshop.bank_sync_connections WHERE id=p_connection_id;
  IF v_connection.manifest_sha256 IS DISTINCT FROM p_manifest_sha256 OR v_connection.pairing_code IS NULL THEN
    RAISE EXCEPTION 'BANK_SYNC_MANIFEST_OR_PAIRING_MISMATCH';
  END IF;
  IF EXISTS(SELECT 1 FROM eshop.bank_sync_account_aliases WHERE bank_account_id=v_connection.bank_account_id AND connection_id<>p_connection_id)
    OR EXISTS(SELECT 1 FROM eshop.bank_sync_connections c JOIN eshop.bank_sync_account_aliases a ON a.bank_account_id=c.bank_account_id WHERE a.connection_id=p_connection_id AND c.id<>p_connection_id) THEN
    RAISE EXCEPTION 'BANK_SYNC_ALIAS_AUTHORITY_CONFLICT';
  END IF;
  PERFORM 1 FROM eshop.bank_accounts WHERE id=v_connection.bank_account_id OR id IN
    (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection_id)
    ORDER BY id FOR UPDATE;
  -- Adopt known bank movement IDs before the first replay. Historical ledger
  -- rows and manual pairing decisions remain unchanged; the receiver compares
  -- bank facts and quarantines a mismatch instead of crediting history twice.
  IF v_connection.provider='FIO' THEN
    INSERT INTO eshop.bank_transaction_identities(instance_id,provider,physical_account,identity_kind,identity_value,transaction_id)
      SELECT v_connection.instance_id,'FIO',v_connection.physical_account,'movement',t.transaction_id::text,t.id
      FROM eshop.transactions t
      WHERE (t.bank_account_id=v_connection.bank_account_id OR t.bank_account_id IN
        (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection_id))
        AND t.ingest_source IN ('fio_api','legacy_api','legacy') AND t.transaction_id IS NOT NULL
      ON CONFLICT(instance_id,provider,physical_account,identity_kind,identity_value) DO UPDATE
        SET transaction_id=eshop.bank_transaction_identities.transaction_id
        WHERE eshop.bank_transaction_identities.transaction_id=EXCLUDED.transaction_id;
    IF EXISTS(SELECT 1 FROM eshop.transactions t JOIN eshop.bank_transaction_identities i
      ON i.instance_id=v_connection.instance_id AND i.provider='FIO' AND i.physical_account=v_connection.physical_account
        AND i.identity_kind='movement' AND i.identity_value=t.transaction_id::text
      WHERE t.bank_account_id=v_connection.bank_account_id AND t.ingest_source IN ('fio_api','legacy_api','legacy')
        AND i.transaction_id<>t.id) THEN RAISE EXCEPTION 'BANK_SYNC_HISTORICAL_IDENTITY_CONFLICT'; END IF;
  END IF;
  UPDATE eshop.bank_accounts SET is_fetch_enabled=false WHERE id=v_connection.bank_account_id OR id IN
    (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection_id);
  UPDATE eshop.bank_sync_connections SET state='connected',legacy_blocked_at=COALESCE(legacy_blocked_at,now())
    WHERE id=p_connection_id AND manifest_sha256=p_manifest_sha256;
END;
$$;
REVOKE ALL ON FUNCTION public.activate_bank_sync_connection(bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.activate_bank_sync_connection(bigint,text) TO service_role;
