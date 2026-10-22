-- Prepare canonical onboarding and adopt historical identities before retiring old importers.

-- SOURCE: eshop_bank_sync/bank_sync_authority.sql



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



-- SOURCE: eshop_bank_sync/bank_sync_manage.sql








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
  RETURN jsonb_build_object('lease_token',v_op.lease_token,'account_number',v_account.account_number,'provider',COALESCE(v_conn.provider,CASE WHEN upper(regexp_replace(v_account.account_number,'\s','','g')) ~ '^CZ[0-9]{2}2010' OR v_account.account_number ~ '/2010$' THEN 'FIO' WHEN upper(regexp_replace(v_account.account_number,'\s','','g')) ~ '^CZ[0-9]{2}3030' OR v_account.account_number ~ '/3030$' THEN 'AIRBANK' ELSE v_account.type END),'title',v_account.title,
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
  IF v_op.operation<>'create' THEN RAISE EXCEPTION 'BANK_SYNC_PROVISION_OPERATION_REQUIRED'; END IF;
  SELECT * INTO STRICT v_account FROM eshop.bank_accounts WHERE id=v_op.bank_account_id FOR UPDATE;
  -- Activation adopts historical movement identities under the account lock.
  -- Existing accounts use the same canonical provisioning path as new accounts.
  INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,
    provider,mode,state,pairing_code,manifest_sha256)
    VALUES(p_instance_id,'festapp',p_remote_id,v_account.id,upper(regexp_replace(v_account.account_number,'\s','','g')),
      CASE WHEN upper(regexp_replace(v_account.account_number,'\s','','g')) ~ '^CZ[0-9]{2}2010' OR v_account.account_number ~ '/2010$' THEN 'FIO' WHEN upper(regexp_replace(v_account.account_number,'\s','','g')) ~ '^CZ[0-9]{2}3030' OR v_account.account_number ~ '/3030$' THEN 'AIRBANK' ELSE v_account.type END,p_mode,'provisioning',p_pairing_code,v_op.payload_sha256)
    ON CONFLICT(bank_account_id) DO UPDATE SET pairing_code=EXCLUDED.pairing_code
    WHERE eshop.bank_sync_connections.remote_bank_account_id=EXCLUDED.remote_bank_account_id
      AND eshop.bank_sync_connections.instance_id=EXCLUDED.instance_id RETURNING id INTO v_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_CONNECTION_MAPPING_CONFLICT'; END IF;
  RETURN v_id;
END;
$$;



DROP FUNCTION IF EXISTS public.update_bank_sync_connection_metadata(bigint,text,timestamptz,text);
CREATE OR REPLACE FUNCTION public.update_bank_sync_connection_metadata(p_id bigint,p_pairing_code text,p_expiry timestamptz,p_state text,p_mode text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  UPDATE eshop.bank_sync_connections SET pairing_history=CASE WHEN p_pairing_code IS NOT NULL AND pairing_code IS DISTINCT FROM p_pairing_code
      THEN pairing_history||jsonb_build_array(jsonb_build_object('code',pairing_code,'retired_at',now())) ELSE pairing_history END,
    pairing_code=COALESCE(p_pairing_code,pairing_code),
    token_expiry_at=CASE WHEN p_mode='api' THEN p_expiry ELSE COALESCE(p_expiry,token_expiry_at) END,
    mode=COALESCE(p_mode,mode),state=p_state WHERE id=p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_CONNECTION_NOT_FOUND'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.update_bank_sync_connection_metadata(bigint,text,timestamptz,text,text) FROM PUBLIC,anon,authenticated;






















-- Only the authenticated management handler calls this after checking bank-admin rights.




-- SOURCE: eshop_bank_accounts/get_my_admin_bank_accounts.sql
DROP FUNCTION IF EXISTS public.get_my_admin_bank_accounts();

CREATE FUNCTION public.get_my_admin_bank_accounts()
RETURNS TABLE (
    id bigint,
    account_number text,
    account_number_human_readable text,
    title text,
    creditor_name text,
    type text,
    token_masked text,
    token_expiry_date timestamptz,
    supported_currencies text[],
    linked_units text[],
    last_fetch_time timestamptz,
    last_fio_fetch_time timestamptz,
    bank_sync jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ba.id,
        ba.account_number,
        ba.account_number_human_readable,
        ba.title,
        ba.creditor_name,
        ba.type,
        NULL::text as token_masked,
        (public.get_bank_sync_connection(ba.id)->>'token_expiry_at')::timestamptz as token_expiry_date,
        ba.supported_currencies,
        ARRAY(
            SELECT u.title 
            FROM eshop.unit_bank_accounts uba
            JOIN public.units u ON uba.unit = u.id
            WHERE uba.bank_account = ba.id
        ) as linked_units,
        ba.last_fetch_time,
        ba.last_fio_fetch_time,
        public.get_bank_sync_connection(ba.id) AS bank_sync
    FROM eshop.bank_accounts ba
    JOIN eshop.bank_account_users bau ON ba.id = bau.bank_account
    WHERE bau."user" = auth.uid() AND bau.is_admin = true
    AND ba.type != 'cash'
    ORDER BY ba.title;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_admin_bank_accounts() FROM PUBLIC, anon;


-- SOURCE: eshop_bank_accounts/get_bank_accounts_for_unit_management.sql
DROP FUNCTION IF EXISTS public.get_bank_accounts_for_unit_management(bigint);

CREATE FUNCTION public.get_bank_accounts_for_unit_management(p_unit_id bigint)
RETURNS TABLE (
    id bigint,
    account_number text,
    title text,
    creditor_name text,
    type text,
    is_admin boolean,
    token_masked text,
    token_expiry_date timestamptz,
    supported_currencies text[],
    last_fio_fetch_time timestamptz,
    bank_sync jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    PERFORM public.check_is_manager_on_unit(p_unit_id);
    RETURN QUERY
    SELECT 
        ba.id,
        ba.account_number,
        ba.title,
        ba.creditor_name,
        ba.type,
        EXISTS (
            SELECT 1 
            FROM eshop.bank_account_users bau
            WHERE bau.bank_account = ba.id 
            AND bau."user" = auth.uid() 
            AND bau.is_admin = true
        ) as is_admin,
        NULL::text as token_masked,
        NULL::timestamptz as token_expiry_date,
        ba.supported_currencies,
        ba.last_fio_fetch_time,
        CASE WHEN EXISTS (
            SELECT 1 FROM eshop.bank_account_users bank_admin
            WHERE bank_admin.bank_account = ba.id
              AND bank_admin."user" = auth.uid()
              AND bank_admin.is_admin
        ) THEN public.get_bank_sync_connection(ba.id)
          ELSE (
            SELECT jsonb_build_object('state',connection.state,'mode',connection.mode)
            FROM eshop.bank_sync_connections connection
            WHERE connection.bank_account_id = ba.id
          ) END AS bank_sync
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    WHERE uba.unit = p_unit_id
    AND ba.type != 'CASH'; -- Exclude Cash Accounts from management list
END;
$$;

REVOKE ALL ON FUNCTION public.get_bank_accounts_for_unit_management(bigint) FROM PUBLIC, anon;
