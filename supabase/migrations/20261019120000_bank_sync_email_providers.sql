-- Canonical bank notification capabilities.
-- Supported notification providers; existing connection identities remain unchanged.
ALTER TABLE eshop.bank_sync_connections DROP CONSTRAINT IF EXISTS bank_sync_connections_provider_check;
ALTER TABLE eshop.bank_sync_connections ADD CONSTRAINT bank_sync_connections_provider_check CHECK(provider IN ('FIO','AIRBANK','CSOB','MONETA','CREDITAS','RAIFFEISENBANK','UNICREDIT','CSAS'));

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











CREATE OR REPLACE FUNCTION public.claim_bank_sync_operation(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_op eshop.bank_sync_operations%ROWTYPE; v_account eshop.bank_accounts%ROWTYPE; v_conn eshop.bank_sync_connections%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  UPDATE eshop.bank_sync_operations SET state='running',lease_token=gen_random_uuid(),updated_at=now() WHERE id=p_id
    AND (state IN ('pending','uncertain','failed') OR (state='running' AND updated_at<now()-interval '5 minutes'))
    RETURNING * INTO v_op;
  IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_OPERATION_BUSY'; END IF;
  SELECT * INTO STRICT v_account FROM eshop.bank_accounts WHERE id=v_op.bank_account_id;
  SELECT * INTO v_conn FROM eshop.bank_sync_connections WHERE bank_account_id=v_op.bank_account_id;
  RETURN jsonb_build_object('lease_token',v_op.lease_token,'account_number',v_account.account_number,'provider',COALESCE(v_conn.provider,public.bank_sync_provider_for_account(v_account.account_number)),'title',v_account.title,
    'connection_id',v_conn.id,'remote_id',v_conn.remote_bank_account_id,'pairing_code',v_conn.pairing_code,
    'state',v_conn.state,'mode',v_conn.mode,'barrier',v_conn.legacy_blocked_at,'manifest_sha256',v_conn.manifest_sha256,'request',v_op.request,'token_cipher',v_op.token_cipher);
END;
$$;







CREATE OR REPLACE FUNCTION public.save_bank_sync_connection(p_operation_id uuid,p_instance_id text,p_remote_id text,p_pairing_code text,p_mode text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_op eshop.bank_sync_operations%ROWTYPE; v_account eshop.bank_accounts%ROWTYPE; v_id bigint;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO STRICT v_op FROM eshop.bank_sync_operations WHERE id=p_operation_id AND state='running';
  PERFORM public.check_bank_account_writable(v_op.bank_account_id);
  IF v_op.operation<>'create' THEN RAISE EXCEPTION 'BANK_SYNC_PROVISION_OPERATION_REQUIRED'; END IF;
  SELECT * INTO STRICT v_account FROM eshop.bank_accounts WHERE id=v_op.bank_account_id FOR UPDATE;
  -- Activation adopts historical movement identities under the account lock.
  -- Existing accounts use the same canonical provisioning path as new accounts.
  INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,
    provider,mode,state,pairing_code,manifest_sha256)
    VALUES(p_instance_id,'festapp',p_remote_id,v_account.id,upper(regexp_replace(v_account.account_number,'\s','','g')),
      public.bank_sync_provider_for_account(v_account.account_number),p_mode,'provisioning',p_pairing_code,v_op.payload_sha256)
    ON CONFLICT(bank_account_id) DO UPDATE SET pairing_code=EXCLUDED.pairing_code
    WHERE eshop.bank_sync_connections.remote_bank_account_id=EXCLUDED.remote_bank_account_id
      AND eshop.bank_sync_connections.instance_id=EXCLUDED.instance_id RETURNING id INTO v_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_CONNECTION_MAPPING_CONFLICT'; END IF;
  RETURN v_id;
END;
$$;



DROP FUNCTION IF EXISTS public.update_bank_sync_connection_metadata(bigint,text,timestamptz,text);
























-- Only the authenticated management handler calls this after checking bank-admin rights.
