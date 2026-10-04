ALTER TABLE eshop.bank_sync_inbox ADD COLUMN IF NOT EXISTS resolution jsonb;
ALTER TABLE eshop.bank_sync_inbox ADD COLUMN IF NOT EXISTS resolved_at timestamptz;
-- Legacy Fio stored offset midnight as UTC; BankSync date-only statements use
-- noon UTC to retain the original bank date. Compare historical facts in the
-- bank's supplied offset, without rewriting either representation.
CREATE OR REPLACE FUNCTION public.bank_sync_existing_facts_match(p_tx eshop.transactions,p_data jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE v_shift interval:=interval '0'; v_offset integer;
BEGIN
  IF p_tx.ingest_source IN ('legacy','legacy_api','fio_api')
    AND p_data->>'date_offset_min' ~ '^-?[0-9]{1,3}$' THEN
    v_offset:=(p_data->>'date_offset_min')::integer;
    IF abs(v_offset)<=840 THEN v_shift:=make_interval(mins=>v_offset); END IF;
  END IF;
  RETURN p_tx.amount IS NOT DISTINCT FROM (p_data->>'amount_cents')::numeric/100
    AND trim(p_tx.currency) IS NOT DISTINCT FROM p_data->>'currency'
    AND (p_tx.date+v_shift)::date IS NOT DISTINCT FROM
      (((p_data->>'date')::timestamptz AT TIME ZONE 'UTC')+v_shift)::date
    AND nullif(trim(p_tx.vs),'') IS NOT DISTINCT FROM nullif(p_data->>'raw_vs','')
    AND (p_tx.payer_reference IS NULL OR p_tx.payer_reference IS NOT DISTINCT FROM p_data->>'payer_reference');
END;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_existing_facts_match(eshop.transactions,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.bank_sync_existing_facts_match(eshop.transactions,jsonb) TO service_role;
CREATE OR REPLACE FUNCTION public.ingest_bank_sync_transaction(
  p_instance_id text, p_consumer_app_id text, p_body_sha256 text, p_envelope jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE
  v_data jsonb := p_envelope->'data';
  v_delivery text := p_envelope->>'delivery_id';
  v_connection eshop.bank_sync_connections%ROWTYPE;
  v_inbox eshop.bank_sync_inbox%ROWTYPE;
  v_tx eshop.transactions%ROWTYPE;
  v_ids bigint[];
  v_identity text := v_data->>'transaction_id';
  v_amount numeric;
  v_date timestamptz;
  v_outcome text;
  v_match jsonb;
  v_receipt jsonb;
  v_source_id bigint;
  v_command_id bigint;
BEGIN
  PERFORM public.require_service_role();
  IF p_consumer_app_id IS DISTINCT FROM 'festapp' OR nullif(p_instance_id,'') IS NULL
    OR p_body_sha256 IS NULL OR p_body_sha256 !~ '^[0-9a-f]{64}$'
    OR p_envelope->>'event' IS DISTINCT FROM 'transaction.received'
    OR p_envelope->>'event_version' IS DISTINCT FROM '2'
    OR v_delivery IS NULL OR v_delivery !~ '^[0-9A-HJKMNP-TV-Z]{26}$'
    OR v_data->>'currency' IS NULL OR v_data->>'currency' NOT IN ('CZK','EUR','USD')
    OR jsonb_typeof(v_data->'amount_cents') IS DISTINCT FROM 'number'
    OR v_data->>'amount_cents' !~ '^-?[0-9]+$'
    OR abs((v_data->>'amount_cents')::numeric)>9007199254740991
    OR v_data->>'id' IS NULL OR v_data->>'bank_account_id' IS NULL
    OR v_data->>'date' IS NULL OR v_data->>'date' !~ 'T.*(Z|[+-][0-9]{2}:[0-9]{2})$' THEN
    RAISE EXCEPTION 'BANK_SYNC_INVALID_ENVELOPE';
  END IF;
  v_amount := (v_data->>'amount_cents')::numeric/100;
  v_date := (v_data->>'date')::timestamptz;
  IF v_data->>'direction' IS DISTINCT FROM (CASE WHEN v_amount>0 THEN 'incoming' WHEN v_amount<0 THEN 'outgoing' ELSE 'zero' END) THEN
    RAISE EXCEPTION 'BANK_SYNC_INVALID_DIRECTION';
  END IF;

  -- Lock order: delivery advisory -> connection -> identity/ledger -> payment_info.
  -- Legacy writers hold the same account row barrier before any ledger writes.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_instance_id||':'||p_consumer_app_id||':'||v_delivery,0));
  SELECT * INTO v_inbox FROM eshop.bank_sync_inbox
    WHERE instance_id=p_instance_id AND consumer_app_id=p_consumer_app_id AND delivery_id=v_delivery;
  IF FOUND THEN
    IF v_inbox.body_sha256<>p_body_sha256 THEN RAISE EXCEPTION 'BANK_SYNC_DELIVERY_CONFLICT'; END IF;
    RETURN v_inbox.receipt;
  END IF;
  SELECT * INTO v_connection FROM eshop.bank_sync_connections
    WHERE instance_id=p_instance_id AND consumer_app_id=p_consumer_app_id
      AND remote_bank_account_id=v_data->>'bank_account_id' FOR UPDATE;
  INSERT INTO eshop.bank_sync_inbox(instance_id,consumer_app_id,delivery_id,body_sha256,event_version,
    remote_transaction_id,connection_id,epoch,payload)
    VALUES(p_instance_id,p_consumer_app_id,v_delivery,p_body_sha256,'2',v_data->>'id',v_connection.id,v_connection.epoch,p_envelope);

  IF v_connection.id IS NULL THEN v_outcome:='quarantined_scope';
  ELSIF v_connection.state='shadow' THEN v_outcome:='shadow_recorded';
  ELSIF v_connection.state NOT IN ('connected','degraded') OR v_connection.legacy_blocked_at IS NULL THEN v_outcome:='quarantined_scope';
  ELSIF v_data->>'identity_kind' IS DISTINCT FROM 'movement'
    OR v_data->>'identity_provenance' IS DISTINCT FROM 'fio_api_column22'
    OR v_data->>'source' IS DISTINCT FROM 'fio_api'
    OR v_connection.provider<>'FIO' OR nullif(v_identity,'') IS NULL THEN
    v_outcome:='quarantined_identity';
  ELSE
    SELECT t.* INTO v_tx FROM eshop.bank_transaction_identities i
      JOIN eshop.transactions t ON t.id=i.transaction_id
      WHERE i.instance_id=p_instance_id AND i.provider=v_connection.provider
        AND i.physical_account=v_connection.physical_account AND i.identity_kind='movement' AND i.identity_value=v_identity
      FOR UPDATE OF t;
    IF v_tx.id IS NULL AND v_identity ~ '^[0-9]{1,19}$' AND v_identity::numeric<=9223372036854775807 THEN
      v_source_id:=v_identity::bigint;
      SELECT array_agg(id ORDER BY id) INTO v_ids FROM eshop.transactions
        WHERE transaction_id=v_source_id AND ingest_source='fio_api'
          AND (bank_account_id=v_connection.bank_account_id OR bank_account_id IN
            (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=v_connection.id));
      IF cardinality(v_ids)>1 THEN v_outcome:='quarantined_conflict';
      ELSIF cardinality(v_ids)=1 THEN SELECT * INTO v_tx FROM eshop.transactions WHERE id=v_ids[1] FOR UPDATE;
      END IF;
    END IF;
    IF v_outcome IS NULL AND v_tx.id IS NOT NULL THEN
      IF NOT public.bank_sync_existing_facts_match(v_tx,v_data) THEN
        v_outcome:='quarantined_conflict';
      ELSE v_outcome:='already_ingested';
      END IF;
    END IF;
    IF v_outcome IS NULL THEN
      IF v_data->>'command_id' ~ '^[0-9]{1,19}$' AND (v_data->>'command_id')::numeric<=9223372036854775807 THEN
        v_command_id:=(v_data->>'command_id')::bigint;
      END IF;
      INSERT INTO eshop.transactions(transaction_id,bank_account_id,amount,currency,date,vs,ks,ss,
        command_id,payer_reference,message_for_recipient,counter_account,counter_account_name,bank_code,bank_name,
        user_identification,transaction_type,performed_by,comment,ingest_source)
        VALUES(v_source_id,v_connection.bank_account_id,v_amount,v_data->>'currency',v_date AT TIME ZONE 'UTC',
          nullif(v_data->>'raw_vs',''),nullif(v_data->>'ks',''),nullif(v_data->>'ss',''),v_command_id,
          v_data->>'payer_reference',v_data->>'message',v_data->>'counter_account',v_data->>'sender_name',
          v_data->>'bank_code',v_data->>'bank_name',v_data->>'user_identification',v_data->>'transaction_type',
          v_data->>'performed_by',v_data->>'comment','banksync_api') RETURNING * INTO v_tx;
      INSERT INTO eshop.bank_transaction_identities(instance_id,provider,physical_account,identity_kind,identity_value,transaction_id)
        VALUES(p_instance_id,v_connection.provider,v_connection.physical_account,'movement',v_identity,v_tx.id);
      IF v_amount<0 THEN v_outcome:='stored_outgoing';
      ELSIF v_amount=0 THEN v_outcome:='stored_zero';
      ELSE
        v_match:=public.match_bank_transaction(v_tx.id);
        v_outcome:=v_match->>'verdict';
        IF v_outcome NOT IN ('paired','unmatched','ambiguous','ineligible','already_paired') OR v_outcome IS NULL THEN
          RAISE EXCEPTION 'BANK_SYNC_MATCHER_INVALID_RESULT';
        END IF;
        IF v_outcome='already_paired' THEN v_outcome:='already_ingested'; END IF;
      END IF;
    END IF;
    IF v_outcome<>'quarantined_conflict' THEN
      INSERT INTO eshop.bank_transaction_identities(instance_id,provider,physical_account,identity_kind,identity_value,transaction_id)
        VALUES(p_instance_id,v_connection.provider,v_connection.physical_account,'movement',v_identity,v_tx.id)
        ON CONFLICT (instance_id,provider,physical_account,identity_kind,identity_value) DO UPDATE
          SET transaction_id=eshop.bank_transaction_identities.transaction_id
          WHERE eshop.bank_transaction_identities.transaction_id=EXCLUDED.transaction_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_IDENTITY_CONFLICT'; END IF;
      INSERT INTO eshop.bank_transaction_identities(instance_id,provider,physical_account,identity_kind,identity_value,transaction_id)
        VALUES(p_instance_id,v_connection.provider,v_connection.physical_account,'remote_transaction',v_data->>'id',v_tx.id)
        ON CONFLICT (instance_id,provider,physical_account,identity_kind,identity_value) DO UPDATE
          SET transaction_id=eshop.bank_transaction_identities.transaction_id
          WHERE eshop.bank_transaction_identities.transaction_id=EXCLUDED.transaction_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_IDENTITY_CONFLICT'; END IF;
    END IF;
  END IF;
  v_receipt:=jsonb_build_object('ok',true,'receipt_version',1,'delivery_id',v_delivery,'outcome',v_outcome);
  UPDATE eshop.bank_sync_inbox SET outcome=v_outcome,receipt=v_receipt,committed_at=now()
    WHERE instance_id=p_instance_id AND consumer_app_id=p_consumer_app_id AND delivery_id=v_delivery;
  UPDATE eshop.bank_sync_connections SET receiver_commit_at=now(),
    last_error=CASE WHEN v_outcome LIKE 'quarantined_%' THEN v_outcome ELSE last_error END WHERE id=v_connection.id;
  RETURN v_receipt;
END;
$$;
REVOKE ALL ON FUNCTION public.ingest_bank_sync_transaction(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ingest_bank_sync_transaction(text,text,text,jsonb) TO service_role;
CREATE OR REPLACE FUNCTION public.get_bank_sync_connection(p_bank_account_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb;
BEGIN
  PERFORM public.check_is_admin_for_bank_account(p_bank_account_id);
  SELECT jsonb_build_object('id',c.id,'remote_bank_account_id',c.remote_bank_account_id,'state',c.state,'mode',c.mode,
    'receiving_address',CASE WHEN c.pairing_code IS NOT NULL THEN c.pairing_code||'@banksync.festapp.net' END,
    'bank_pull_at',c.bank_pull_at,'receiver_commit_at',c.receiver_commit_at,'last_error',c.last_error,
    'token_expiry_at',c.token_expiry_at) INTO v_result FROM eshop.bank_sync_connections c
    WHERE c.bank_account_id=p_bank_account_id OR c.id IN
      (SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=p_bank_account_id);
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.get_bank_sync_connection(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_bank_sync_connection(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.begin_bank_sync_operation(p_id uuid,p_account_id bigint,p_operation text,p_hash text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_operation eshop.bank_sync_operations%ROWTYPE;
BEGIN
  PERFORM public.check_is_admin_for_bank_account(p_account_id);
  INSERT INTO eshop.bank_sync_operations(id,bank_account_id,actor,operation,payload_sha256,state)
    VALUES(p_id,p_account_id,auth.uid(),p_operation,p_hash,'pending') ON CONFLICT DO NOTHING;
  SELECT * INTO STRICT v_operation FROM eshop.bank_sync_operations WHERE id=p_id OR (bank_account_id=p_account_id AND actor=auth.uid() AND operation=p_operation
      AND payload_sha256=p_hash AND state IN ('pending','running','uncertain')) ORDER BY (id=p_id) DESC LIMIT 1 FOR UPDATE;
  IF v_operation.actor IS DISTINCT FROM auth.uid() OR v_operation.bank_account_id<>p_account_id
    OR v_operation.operation<>p_operation OR v_operation.payload_sha256<>p_hash THEN
    RAISE EXCEPTION 'BANK_SYNC_OPERATION_CONFLICT';
  END IF;
  RETURN jsonb_build_object('id',v_operation.id,'state',v_operation.state,'result',v_operation.result);
END;
$$;
REVOKE ALL ON FUNCTION public.begin_bank_sync_operation(uuid,bigint,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.begin_bank_sync_operation(uuid,bigint,text,text) TO authenticated;

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
REVOKE ALL ON FUNCTION public.claim_bank_sync_operation(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_bank_sync_operation(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.complete_bank_sync_operation(p_id uuid,p_state text,p_result jsonb,p_lease_token uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF p_state NOT IN ('uncertain','completed','failed') THEN RAISE EXCEPTION 'BANK_SYNC_OPERATION_STATE_INVALID'; END IF;
  UPDATE eshop.bank_sync_operations SET state=p_state,result=p_result,token_cipher=CASE WHEN p_state='completed' THEN NULL ELSE token_cipher END,updated_at=now() WHERE id=p_id AND state='running' AND lease_token=p_lease_token;
  IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_OPERATION_NOT_CLAIMED'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_bank_sync_operation(uuid,text,jsonb,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_bank_sync_operation(uuid,text,jsonb,uuid) TO service_role;

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
REVOKE ALL ON FUNCTION public.save_bank_sync_connection(uuid,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.save_bank_sync_connection(uuid,text,text,text,text) TO service_role;

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
GRANT EXECUTE ON FUNCTION public.update_bank_sync_connection_metadata(bigint,text,timestamptz,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.get_bank_sync_connections_for_unit(p_unit_id bigint)
RETURNS TABLE(connection_id bigint,remote_bank_account_id text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  RETURN QUERY SELECT DISTINCT c.id,c.remote_bank_account_id FROM eshop.bank_sync_connections c
    JOIN eshop.unit_bank_accounts uba ON uba.bank_account=c.bank_account_id OR uba.bank_account IN
      (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
    WHERE uba.unit=p_unit_id AND c.state IN ('connected','degraded') AND c.mode='api' AND c.legacy_blocked_at IS NOT NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.get_bank_sync_connections_for_unit(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_bank_sync_connections_for_unit(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.record_bank_sync_pull(p_id bigint,p_success_at timestamptz,p_error text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  UPDATE eshop.bank_sync_connections SET bank_pull_at=COALESCE(p_success_at,bank_pull_at),last_error=left(p_error,256),
    state=CASE WHEN state IN ('connected','degraded') THEN
      CASE WHEN p_error IS NOT NULL THEN 'degraded' WHEN p_success_at IS NOT NULL THEN 'connected' ELSE state END
      ELSE state END WHERE id=p_id;
END;
$$;
REVOKE ALL ON FUNCTION public.record_bank_sync_pull(bigint,timestamptz,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_bank_sync_pull(bigint,timestamptz,text) TO service_role;

CREATE OR REPLACE FUNCTION public.get_bank_sync_observations(p_bank_account_id bigint,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb;
BEGIN
  PERFORM public.check_is_admin_for_bank_account(p_bank_account_id);
  SELECT COALESCE(jsonb_agg(row_to_json(q)),'[]'::jsonb) INTO v_result FROM (
    SELECT i.delivery_id,i.received_at,i.outcome,i.payload->'data' AS bank_data
      FROM eshop.bank_sync_inbox i JOIN eshop.bank_sync_connections c ON c.id=i.connection_id
      WHERE (c.bank_account_id=p_bank_account_id OR c.id IN
        (SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=p_bank_account_id))
        AND i.outcome LIKE 'quarantined_%' AND i.resolution IS NULL ORDER BY i.received_at DESC,i.delivery_id LIMIT LEAST(GREATEST(p_limit,1),100)
  ) q;
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.get_bank_sync_observations(bigint,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_bank_sync_observations(bigint,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.stage_bank_sync_operation(p_id uuid,p_hash text,p_request jsonb,p_token_cipher jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF p_request ? 'token' OR p_request->>'operation_id' IS DISTINCT FROM p_id::text THEN
    RAISE EXCEPTION 'BANK_SYNC_REQUEST_INVALID';
  END IF;
  UPDATE eshop.bank_sync_operations SET request=COALESCE(request,p_request||jsonb_build_object('expected_pairing',
      (SELECT c.pairing_code FROM eshop.bank_sync_connections c WHERE c.bank_account_id=bank_sync_operations.bank_account_id))),
      token_cipher=COALESCE(token_cipher,p_token_cipher)
    WHERE id=p_id AND payload_sha256=p_hash AND state IN ('pending','uncertain');
  IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_OPERATION_NOT_STAGEABLE'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.stage_bank_sync_operation(uuid,text,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.stage_bank_sync_operation(uuid,text,jsonb,jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.get_recoverable_bank_sync_operations()
RETURNS TABLE(id uuid,request jsonb,token_cipher jsonb,payload_sha256 text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  RETURN QUERY SELECT o.id,o.request,o.token_cipher,o.payload_sha256 FROM eshop.bank_sync_operations o
    WHERE o.request IS NOT NULL AND o.state IN ('pending','uncertain','running')
      AND o.updated_at<now()-interval '5 minutes' ORDER BY o.updated_at,o.id LIMIT 10;
END;
$$;
REVOKE ALL ON FUNCTION public.get_recoverable_bank_sync_operations() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_recoverable_bank_sync_operations() TO service_role;

-- Only the authenticated management handler calls this after checking bank-admin rights.
CREATE OR REPLACE FUNCTION public.get_pending_bank_sync_details(p_bank_account_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  RETURN (SELECT jsonb_build_object('id',id,'request',request,'payload_sha256',payload_sha256)
    FROM eshop.bank_sync_operations WHERE bank_account_id=p_bank_account_id AND operation='update_details'
    AND state IN ('pending','running','uncertain') ORDER BY created_at LIMIT 1);
END;
$$;
REVOKE ALL ON FUNCTION public.get_pending_bank_sync_details(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_pending_bank_sync_details(bigint) TO service_role;

-- Keep the signed envelope and original transport receipt immutable. Record a
-- separate resolution only when the existing ledger facts now match exactly.
UPDATE eshop.bank_sync_inbox i SET resolved_at=now(),resolution=jsonb_build_object(
  'outcome','already_ingested','reason','legacy_fio_bank_date','transaction_id',t.id,'migration','20261004205000')
FROM eshop.bank_sync_connections c,eshop.bank_transaction_identities ident,eshop.transactions t
WHERE i.connection_id=c.id AND c.provider='FIO' AND i.outcome='quarantined_conflict' AND i.resolution IS NULL
  AND ident.instance_id=i.instance_id AND ident.provider=c.provider AND ident.physical_account=c.physical_account
  AND ident.identity_kind='movement' AND ident.identity_value=i.payload->'data'->>'transaction_id'
  AND t.id=ident.transaction_id AND t.ingest_source IN ('legacy','legacy_api','fio_api')
  AND public.bank_sync_existing_facts_match(t,i.payload->'data');
