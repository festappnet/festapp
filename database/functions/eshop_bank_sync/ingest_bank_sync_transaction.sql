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
      IF v_tx.amount IS DISTINCT FROM v_amount OR trim(v_tx.currency) IS DISTINCT FROM v_data->>'currency'
        OR v_tx.date::date IS DISTINCT FROM (v_date AT TIME ZONE 'UTC')::date
        OR nullif(trim(v_tx.vs),'') IS DISTINCT FROM nullif(v_data->>'raw_vs','')
        OR (v_tx.payer_reference IS NOT NULL AND v_tx.payer_reference IS DISTINCT FROM v_data->>'payer_reference') THEN
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
