-- Canonical sources: database/functions/eshop_bank_sync and listed legacy boundaries.

-- SOURCE: eshop_bank_sync/schema.sql
-- Automatic import authority is connection-scoped. Alias membership is an
-- explicit reviewed decision, never inferred from VS or account titles.
CREATE TABLE IF NOT EXISTS eshop.bank_sync_connections (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  instance_id text NOT NULL,
  consumer_app_id text NOT NULL CHECK (consumer_app_id = 'festapp'),
  remote_bank_account_id text NOT NULL,
  bank_account_id bigint NOT NULL UNIQUE REFERENCES eshop.bank_accounts(id),
  physical_account text NOT NULL,
  provider text NOT NULL CHECK(provider IN ('FIO','AIRBANK')),
  mode text NOT NULL CHECK(mode IN ('api','email')),
  state text NOT NULL CHECK(state IN ('provisioning','shadow','connected','degraded','suspended')),
  pairing_code text CHECK(pairing_code ~ '^[0-9a-f]{10}$'),
  pairing_history jsonb NOT NULL DEFAULT '[]',
  legacy_blocked_at timestamptz,
  epoch bigint NOT NULL DEFAULT 1,
  manifest_sha256 text NOT NULL CHECK(manifest_sha256 ~ '^[0-9a-f]{64}$'),
  token_expiry_at timestamptz,
  bank_pull_at timestamptz,
  receiver_commit_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(instance_id,consumer_app_id,remote_bank_account_id),
  UNIQUE(instance_id,provider,physical_account)
);
CREATE TABLE IF NOT EXISTS eshop.bank_sync_account_aliases (
  bank_account_id bigint PRIMARY KEY REFERENCES eshop.bank_accounts(id),
  connection_id bigint NOT NULL REFERENCES eshop.bank_sync_connections(id)
);
CREATE TABLE IF NOT EXISTS eshop.bank_sync_inbox (
  instance_id text NOT NULL,
  consumer_app_id text NOT NULL CHECK(consumer_app_id='festapp'),
  delivery_id text NOT NULL,
  body_sha256 text NOT NULL CHECK(body_sha256 ~ '^[0-9a-f]{64}$'),
  event_version text NOT NULL CHECK(event_version='2'),
  remote_transaction_id text NOT NULL,
  connection_id bigint REFERENCES eshop.bank_sync_connections(id),
  legacy_blocked_at timestamptz,
  epoch bigint,
  payload jsonb NOT NULL CHECK(octet_length(payload::text)<=65536),
  outcome text,
  receipt jsonb,
  received_at timestamptz NOT NULL DEFAULT now(),
  committed_at timestamptz,
  PRIMARY KEY(instance_id,consumer_app_id,delivery_id)
);
CREATE TABLE IF NOT EXISTS eshop.bank_transaction_identities (
  instance_id text NOT NULL,
  provider text NOT NULL,
  physical_account text NOT NULL,
  identity_kind text NOT NULL CHECK(identity_kind IN ('movement','remote_transaction')),
  identity_value text NOT NULL,
  transaction_id bigint NOT NULL REFERENCES eshop.transactions(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(instance_id,provider,physical_account,identity_kind,identity_value)
);
CREATE TABLE IF NOT EXISTS eshop.bank_sync_operations (
  id uuid PRIMARY KEY,
  bank_account_id bigint NOT NULL REFERENCES eshop.bank_accounts(id),
  actor uuid NOT NULL REFERENCES public.user_info(id),
  operation text NOT NULL CHECK(operation IN ('create','set_token','rotate_pairing','sync','suspend')),
  payload_sha256 text NOT NULL CHECK(payload_sha256 ~ '^[0-9a-f]{64}$'),
  state text NOT NULL CHECK(state IN ('pending','running','uncertain','completed','failed')),
  remote_reference text,
  request jsonb CHECK (request IS NULL OR octet_length(request::text)<=8192),
  token_cipher jsonb,
  lease_token uuid,
  result jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS bank_sync_operations_active_account_uidx ON eshop.bank_sync_operations(bank_account_id) WHERE state IN ('pending','running','uncertain');
ALTER TABLE eshop.bank_sync_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.bank_sync_account_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.bank_sync_inbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.bank_transaction_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.bank_sync_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.bank_sync_connections,eshop.bank_sync_account_aliases,eshop.bank_sync_inbox,
  eshop.bank_transaction_identities,eshop.bank_sync_operations FROM PUBLIC,anon,authenticated;


-- SOURCE: eshop_bank_sync/bank_sync_authority.sql
CREATE OR REPLACE FUNCTION public.require_legacy_bank_authority(p_bank_account_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  -- All old entry points hold this row through their ledger commit. Activation
  -- holds the same barrier, so an in-flight legacy SQL write cannot commit late.
  PERFORM 1 FROM eshop.bank_accounts WHERE id=p_bank_account_id FOR UPDATE;
  IF EXISTS (SELECT 1 FROM eshop.bank_sync_connections c WHERE c.legacy_blocked_at IS NOT NULL
    AND (c.bank_account_id=p_bank_account_id OR c.id IN
      (SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=p_bank_account_id))) THEN
    RAISE EXCEPTION 'BANK_SYNC_CANONICAL_CONNECTION_REQUIRED';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.require_legacy_bank_authority(bigint) FROM PUBLIC,anon,authenticated,service_role;

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
  UPDATE eshop.bank_accounts SET is_fetch_enabled=false WHERE id=v_connection.bank_account_id OR id IN
    (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection_id);
  UPDATE eshop.bank_sync_connections SET state='connected',legacy_blocked_at=COALESCE(legacy_blocked_at,now())
    WHERE id=p_connection_id AND manifest_sha256=p_manifest_sha256;
END;
$$;
REVOKE ALL ON FUNCTION public.activate_bank_sync_connection(bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.activate_bank_sync_connection(bigint,text) TO service_role;


-- SOURCE: eshop_bank_sync/bank_sync_manage.sql
CREATE OR REPLACE FUNCTION public.get_bank_sync_connection(p_bank_account_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb;
BEGIN
  PERFORM public.check_is_admin_for_bank_account(p_bank_account_id);
  SELECT jsonb_build_object('id',c.id,'state',c.state,'mode',c.mode,
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
  RETURN jsonb_build_object('lease_token',v_op.lease_token,'account_number',v_account.account_number,'provider',v_account.type,'title',v_account.title,
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
  -- Existing automated accounts require the separately reviewed cutover manifest.
  IF v_account.is_fetch_enabled OR EXISTS(SELECT 1 FROM eshop.transactions WHERE bank_account_id=v_account.id) THEN
    RAISE EXCEPTION 'BANK_SYNC_EXISTING_ACCOUNT_REQUIRES_CUTOVER_MANIFEST';
  END IF;
  INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,
    provider,mode,state,pairing_code,manifest_sha256)
    VALUES(p_instance_id,'festapp',p_remote_id,v_account.id,upper(regexp_replace(v_account.account_number,'\s','','g')),
      v_account.type,p_mode,'provisioning',p_pairing_code,v_op.payload_sha256)
    ON CONFLICT(bank_account_id) DO UPDATE SET pairing_code=EXCLUDED.pairing_code
    WHERE eshop.bank_sync_connections.remote_bank_account_id=EXCLUDED.remote_bank_account_id
      AND eshop.bank_sync_connections.instance_id=EXCLUDED.instance_id RETURNING id INTO v_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_CONNECTION_MAPPING_CONFLICT'; END IF;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.save_bank_sync_connection(uuid,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.save_bank_sync_connection(uuid,text,text,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.update_bank_sync_connection_metadata(p_id bigint,p_pairing_code text,p_expiry timestamptz,p_state text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  UPDATE eshop.bank_sync_connections SET pairing_history=CASE WHEN p_pairing_code IS NOT NULL AND pairing_code IS DISTINCT FROM p_pairing_code
      THEN pairing_history||jsonb_build_array(jsonb_build_object('code',pairing_code,'retired_at',now())) ELSE pairing_history END,
    pairing_code=COALESCE(p_pairing_code,pairing_code),token_expiry_at=COALESCE(p_expiry,token_expiry_at),state=p_state WHERE id=p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_CONNECTION_NOT_FOUND'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.update_bank_sync_connection_metadata(bigint,text,timestamptz,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.update_bank_sync_connection_metadata(bigint,text,timestamptz,text) TO service_role;

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
  UPDATE eshop.bank_sync_connections SET bank_pull_at=COALESCE(p_success_at,bank_pull_at),last_error=left(p_error,256) WHERE id=p_id;
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
        AND i.outcome LIKE 'quarantined_%' ORDER BY i.received_at DESC,i.delivery_id LIMIT LEAST(GREATEST(p_limit,1),100)
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


-- SOURCE: eshop_transactions/match_bank_transaction.sql
CREATE OR REPLACE FUNCTION public.match_bank_transaction(p_transaction_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_transaction eshop.transactions%ROWTYPE;
  v_candidate_ids bigint[];
  v_candidate_id bigint;
  v_signal_count integer := 0;
BEGIN
  PERFORM public.require_service_role();

  SELECT * INTO v_transaction
  FROM eshop.transactions
  WHERE id = p_transaction_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MATCH_TRANSACTION_NOT_FOUND'; END IF;

  IF v_transaction.payment_info IS NOT NULL THEN
    RETURN jsonb_build_object('verdict', 'already_paired',
      'transaction_id', p_transaction_id, 'payment_info_id', v_transaction.payment_info);
  END IF;
  IF v_transaction.amount <= 0
     OR v_transaction.bank_account_id IS NULL
     OR nullif(trim(v_transaction.currency::text), '') IS NULL THEN
    RETURN jsonb_build_object('verdict', 'ineligible', 'reason', 'invalid_direction_or_scope');
  END IF;
  IF v_transaction.ingest_source LIKE '%_email'
     AND v_transaction.transaction_id IS NULL
     AND v_transaction.command_id IS NULL THEN
    RETURN jsonb_build_object('verdict', 'ineligible', 'reason', 'unverified_identity');
  END IF;

  WITH raw_signals(kind, value) AS (
    SELECT 'vs', trim(v_transaction.vs::text)
      WHERE trim(COALESCE(v_transaction.vs::text, '')) ~ '^[0-9]{1,10}$'
    UNION ALL
    SELECT 'rf', public.normalize_creditor_reference(v_transaction.payer_reference)
      WHERE v_transaction.payer_reference IS NOT NULL
        AND public.is_valid_creditor_reference(v_transaction.payer_reference)
    UNION ALL
    SELECT 'rf', public.normalize_creditor_reference(m.captures[2])
      FROM regexp_matches(
        upper(concat_ws(E'\n', v_transaction.message_for_recipient,
          v_transaction.user_identification, v_transaction.comment)),
        '(^|[^A-Z0-9])(RF[0-9]{2}[A-Z0-9[:space:]]{1,25})([^A-Z0-9]|$)', 'g'
      ) AS m(captures)
      WHERE public.is_valid_creditor_reference(m.captures[2])
    UNION ALL
    SELECT 'vs', trim(v_transaction.message_for_recipient)
      WHERE nullif(trim(COALESCE(v_transaction.vs::text, '')), '') IS NULL
        AND trim(COALESCE(v_transaction.message_for_recipient, '')) ~ '^[0-9]{1,10}$'
    UNION ALL
    SELECT 'vs', substring(v_transaction.message_for_recipient
      FROM '(?i)(?:VS|variabilní symbol)[[:space:]]*[:=-]?[[:space:]]*([0-9]{1,10})')
      WHERE nullif(trim(COALESCE(v_transaction.vs::text, '')), '') IS NULL
        AND substring(v_transaction.message_for_recipient
          FROM '(?i)(?:VS|variabilní symbol)[[:space:]]*[:=-]?[[:space:]]*([0-9]{1,10})') IS NOT NULL
  ), signals AS (
    SELECT DISTINCT kind, value FROM raw_signals
  ), candidates AS (
    SELECT DISTINCT pi.id
    FROM signals s
    JOIN eshop.payment_info pi
      ON (s.kind = 'rf' AND pi.creditor_reference = s.value)
      OR (s.kind = 'vs' AND pi.variable_symbol = s.value::bigint)
    WHERE (pi.bank_account = v_transaction.bank_account_id
      OR public.bank_sync_accounts_match(p_transaction_id,pi.bank_account))
      AND upper(trim(pi.currency_code::text)) = upper(trim(v_transaction.currency::text))
  )
  SELECT (SELECT count(*) FROM signals), array_agg(c.id ORDER BY c.id)
  INTO v_signal_count, v_candidate_ids
  FROM candidates c;

  IF v_signal_count = 0 OR v_candidate_ids IS NULL THEN
    RETURN jsonb_build_object('verdict', 'unmatched', 'reason', 'no_unique_reference');
  END IF;
  IF cardinality(v_candidate_ids) <> 1 THEN
    RETURN jsonb_build_object('verdict', 'ambiguous', 'candidate_count', cardinality(v_candidate_ids));
  END IF;

  v_candidate_id := v_candidate_ids[1];
  PERFORM public.apply_transaction_pairing(
    p_transaction_id, v_candidate_id, 'automatic_reference', 'service',
    jsonb_build_object('signal_count', v_signal_count)
  );
  RETURN jsonb_build_object('verdict', 'paired', 'transaction_id', p_transaction_id,
    'payment_info_id', v_candidate_id);
END;
$$;

REVOKE ALL ON FUNCTION public.match_bank_transaction(bigint)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.match_bank_transaction(bigint) TO service_role;


-- SOURCE: eshop_orders/recalculate_order_payment_status.sql
CREATE OR REPLACE FUNCTION public.recalculate_order_payment_status(p_order_id bigint)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_payment_info_id bigint;
    v_paid numeric;
    v_deposit_amount numeric;
    v_price numeric;
    v_state text;
    v_transition jsonb;
BEGIN
    -- Get Order Details
    SELECT payment_info, price, state INTO v_payment_info_id, v_price, v_state
    FROM eshop.orders
    WHERE id = p_order_id;

    IF v_payment_info_id IS NULL THEN
        RETURN;
    END IF;

    -- Get Paid Amount and Deposit Amount from Payment Info
    SELECT paid, deposit_amount INTO v_paid, v_deposit_amount
    FROM eshop.payment_info
    WHERE id = v_payment_info_id;

    -- Update Logic
    IF COALESCE(v_paid, 0) >= COALESCE(v_deposit_amount, v_price) THEN
        -- Fully Paid (or Deposit Paid) -> Move to Paid
        IF v_state != 'paid' AND (v_state = 'ordered' OR v_state = 'created' OR v_state = 'expired') THEN
             -- The legacy JSON boundary reports failures instead of raising.
             -- Propagate them so payment, order, ticket intent and webhook receipt
             -- cannot commit independently of the canonical paid transition.
             v_transition := public.update_order_and_tickets_to_paid(p_order_id);
             IF (v_transition->>'code') IS DISTINCT FROM '200' THEN
                 RAISE EXCEPTION 'ORDER_PAID_TRANSITION_FAILED: %',
                     COALESCE(v_transition->>'message','invalid transition receipt');
             END IF;
        END IF;
    ELSE
        -- Underpaid -> Revert to Ordered (if currently Paid)
        IF v_state IN ('paid','sent') THEN
            PERFORM public.cancel_order_email_intents(p_order_id);
            -- Revert Order
            UPDATE eshop.orders
            SET state = 'ordered', updated_at = now(),email_payment_version=email_payment_version+1
            WHERE id = p_order_id;

            -- Revert Tickets (only those that are 'paid')
            UPDATE eshop.tickets
            SET state = 'ordered', updated_at = now() -- Reverted to 'ordered' as 'valid' is not a supported state

            FROM eshop.order_product_ticket
            WHERE eshop.order_product_ticket.ticket = eshop.tickets.id
            AND eshop.order_product_ticket."order" = p_order_id
            AND eshop.tickets.state IN ('paid','sent');
        END IF;
    END IF;
END;
$$;


-- SOURCE: eshop_transactions/apply_transaction_pairing.sql
CREATE OR REPLACE FUNCTION public.apply_transaction_pairing(
  p_transaction_id bigint,
  p_payment_info_id bigint,
  p_method text,
  p_actor_kind text DEFAULT 'system',
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_transaction eshop.transactions%ROWTYPE;
  v_target eshop.payment_info%ROWTYPE;
  v_old_payment_info_id bigint;
  v_order_id bigint;
BEGIN
  IF p_method IS NULL OR p_method !~ '^[a-z0-9_]{1,64}$' THEN
    RAISE EXCEPTION 'PAIRING_INVALID_METHOD';
  END IF;
  IF p_actor_kind NOT IN ('service', 'user', 'system') THEN
    RAISE EXCEPTION 'PAIRING_INVALID_ACTOR_KIND';
  END IF;

  SELECT * INTO v_transaction
  FROM eshop.transactions
  WHERE id = p_transaction_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_TRANSACTION_NOT_FOUND'; END IF;
  v_old_payment_info_id := v_transaction.payment_info;

  IF v_old_payment_info_id IS NOT DISTINCT FROM p_payment_info_id THEN
    RETURN jsonb_build_object('status', 'unchanged', 'transaction_id', p_transaction_id,
      'payment_info_id', p_payment_info_id);
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    SELECT * INTO v_target FROM eshop.payment_info WHERE id = p_payment_info_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_PAYMENT_INFO_NOT_FOUND'; END IF;
    IF upper(trim(v_transaction.currency::text)) <> upper(trim(v_target.currency_code::text)) THEN
      RAISE EXCEPTION 'PAIRING_CURRENCY_MISMATCH';
    END IF;
    IF v_transaction.transaction_type IS DISTINCT FROM 'manual'
       AND v_transaction.bank_account_id <> v_target.bank_account
       AND NOT public.bank_sync_accounts_match(p_transaction_id,v_target.bank_account) THEN
      RAISE EXCEPTION 'PAIRING_BANK_ACCOUNT_MISMATCH';
    END IF;
  END IF;

  UPDATE eshop.transactions SET payment_info = p_payment_info_id WHERE id = p_transaction_id;

  IF v_old_payment_info_id IS NOT NULL THEN
    UPDATE eshop.payment_info pi SET
      paid = COALESCE((SELECT sum(t.amount) FROM eshop.transactions t
        WHERE t.payment_info = pi.id AND t.transaction_type IS DISTINCT FROM 'return'), 0),
      returned = COALESCE((SELECT abs(sum(t.amount)) FROM eshop.transactions t
        WHERE t.payment_info = pi.id AND t.transaction_type = 'return'), 0)
    WHERE pi.id = v_old_payment_info_id;
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = v_old_payment_info_id;
    IF v_order_id IS NOT NULL THEN PERFORM public.recalculate_order_payment_status(v_order_id); END IF;
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    UPDATE eshop.payment_info pi SET
      paid = COALESCE((SELECT sum(t.amount) FROM eshop.transactions t
        WHERE t.payment_info = pi.id AND t.transaction_type IS DISTINCT FROM 'return'), 0),
      returned = COALESCE((SELECT abs(sum(t.amount)) FROM eshop.transactions t
        WHERE t.payment_info = pi.id AND t.transaction_type = 'return'), 0)
    WHERE pi.id = p_payment_info_id;
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = p_payment_info_id;
    IF v_order_id IS NOT NULL THEN PERFORM public.recalculate_order_payment_status(v_order_id); END IF;
  END IF;

  INSERT INTO eshop.transaction_pairing_events (
    transaction_snapshot_id, transaction_id, old_payment_info_id,
    new_payment_info_id, action, method, actor_id, actor_kind, details
  ) VALUES (
    p_transaction_id, p_transaction_id, v_old_payment_info_id,
    p_payment_info_id, CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    p_method, auth.uid(), p_actor_kind, COALESCE(p_details, '{}'::jsonb)
  );

  RETURN jsonb_build_object('status', CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    'transaction_id', p_transaction_id, 'payment_info_id', p_payment_info_id);
END;
$$;

REVOKE ALL ON FUNCTION public.apply_transaction_pairing(bigint,bigint,text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;


-- SOURCE: eshop_bank_sync/ingest_bank_sync_transaction.sql
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


-- SOURCE: eshop_transactions/insert_transactions.sql
CREATE OR REPLACE FUNCTION public.insert_transactions(transactions jsonb, bank_account_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_input jsonb;
  v_date timestamptz;
  v_id bigint;
  v_movement_id bigint;
  v_result jsonb;
  v_items jsonb := '[]'::jsonb;
  v_inserted integer := 0;
  v_skipped integer := 0;
BEGIN
  PERFORM public.require_service_role();
  PERFORM public.require_legacy_bank_authority(bank_account_id);
  IF jsonb_typeof(transactions) <> 'array' THEN RAISE EXCEPTION 'TRANSACTIONS_ARRAY_REQUIRED'; END IF;

  FOR v_input IN SELECT value FROM jsonb_array_elements(transactions) LOOP
    BEGIN
      v_date := (v_input->'column0'->>'value')::timestamptz;
      v_movement_id := nullif(v_input->'column22'->>'value', '')::bigint;
    EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN
      v_skipped := v_skipped + 1;
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'ingest_status', 'failed', 'reason', 'invalid_bank_payload'));
      CONTINUE;
    END;

    SELECT t.id INTO v_id FROM eshop.transactions t
    WHERE t.bank_account_id = insert_transactions.bank_account_id
      AND t.transaction_id = v_movement_id;
    IF v_id IS NOT NULL THEN
      v_skipped := v_skipped + 1;
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'source_id', v_movement_id, 'stored_id', v_id,
        'ingest_status', 'skipped', 'match_verdict', 'already_ingested'));
      CONTINUE;
    END IF;

    INSERT INTO eshop.transactions (
      transaction_id, date, amount, currency, counter_account, bank_code,
      bank_name, ks, vs, ss, user_identification, transaction_type,
      performed_by, comment, command_id, bank_account_id,
      message_for_recipient, counter_account_name, payer_reference, ingest_source
    ) VALUES (
      v_movement_id, v_date, (v_input->'column1'->>'value')::numeric,
      v_input->'column14'->>'value', v_input->'column2'->>'value',
      v_input->'column3'->>'value', v_input->'column12'->>'value',
      nullif(v_input->'column4'->>'value', ''), nullif(v_input->'column5'->>'value', ''),
      nullif(v_input->'column6'->>'value', ''), v_input->'column7'->>'value',
      v_input->'column8'->>'value', v_input->'column9'->>'value',
      v_input->'column25'->>'value', nullif(v_input->'column17'->>'value', '')::bigint,
      bank_account_id, v_input->'column16'->>'value', v_input->'column10'->>'value',
      v_input->'column27'->>'value', 'fio_api'
    ) RETURNING id INTO v_id;
    v_inserted := v_inserted + 1;

    BEGIN
      v_result := public.match_bank_transaction(v_id);
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'source_id', v_movement_id, 'stored_id', v_id, 'ingest_status', 'inserted',
        'match_verdict', v_result->>'verdict', 'reason', v_result->>'reason'));
    EXCEPTION WHEN OTHERS THEN
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'source_id', v_movement_id, 'stored_id', v_id, 'ingest_status', 'inserted',
        'match_verdict', 'failed', 'reason', SQLSTATE));
    END;
  END LOOP;

  RETURN jsonb_build_object('inserted', v_inserted, 'skipped', v_skipped, 'items', v_items);
END;
$$;

CREATE INDEX IF NOT EXISTS idx_transaction_id ON eshop.transactions (transaction_id);
REVOKE ALL ON FUNCTION public.insert_transactions(jsonb,bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.insert_transactions(jsonb,bigint) TO service_role;


-- SOURCE: eshop_transactions/process_email_transaction.sql
CREATE OR REPLACE FUNCTION public.process_email_transaction(p_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_bank_account_id bigint := (p_data->>'bank_account_id')::bigint;
  v_external_id text := nullif(p_data->>'external_id', '');
  v_movement_id bigint := nullif(p_data->>'movement_id', '')::bigint;
  v_command_id bigint := nullif(p_data->>'bank_command_id', '')::bigint;
  v_source text := COALESCE(nullif(p_data->>'ingest_source', ''), 'legacy_email');
  v_existing_id bigint;
  v_id bigint;
  v_match jsonb;
BEGIN
  PERFORM public.require_service_role();
  PERFORM public.require_legacy_bank_authority(v_bank_account_id);
  IF v_source NOT IN ('fio_email', 'airbank_email', 'legacy_email') THEN RAISE EXCEPTION 'EMAIL_SOURCE_INVALID'; END IF;

  UPDATE eshop.bank_accounts SET last_fetch_time = timezone('UTC', now()), updated_at = now()
  WHERE id = v_bank_account_id;

  IF v_external_id IS NOT NULL THEN
    SELECT id INTO v_existing_id FROM eshop.transactions
    WHERE bank_account_id = v_bank_account_id AND external_id = v_external_id;
    IF FOUND THEN
      RETURN jsonb_build_object('ingest_status', 'skipped', 'reason', 'transport_replay',
        'stored_id', v_existing_id, 'match_verdict', 'already_ingested');
    END IF;
  END IF;

  IF v_movement_id IS NOT NULL THEN
    SELECT id INTO v_existing_id FROM eshop.transactions
    WHERE bank_account_id = v_bank_account_id AND transaction_id = v_movement_id;
  ELSIF v_command_id IS NOT NULL THEN
    SELECT min(id) INTO v_existing_id FROM eshop.transactions
    WHERE bank_account_id = v_bank_account_id AND command_id = v_command_id
    HAVING count(*) = 1;
  END IF;

  IF v_existing_id IS NOT NULL THEN
    UPDATE eshop.transactions SET external_id = COALESCE(external_id, v_external_id)
    WHERE id = v_existing_id;
    RETURN jsonb_build_object('ingest_status', 'reconciled', 'stored_id', v_existing_id,
      'match_verdict', 'already_ingested');
  END IF;

  INSERT INTO eshop.transactions (
    bank_account_id, amount, currency, counter_account, bank_code, bank_name,
    vs, ks, ss, message_for_recipient, date, external_id, transaction_id,
    command_id, counter_account_name, payer_reference, ingest_source
  ) VALUES (
    v_bank_account_id, (p_data->>'amount')::numeric, upper(trim(p_data->>'currency')),
    p_data->>'counter_account', p_data->>'bank_code', p_data->>'bank_name',
    nullif(p_data->>'vs', ''), nullif(p_data->>'ks', ''), nullif(p_data->>'ss', ''),
    p_data->>'message', (p_data->>'date')::timestamptz, v_external_id, v_movement_id,
    v_command_id, p_data->>'sender_name', p_data->>'payer_reference', v_source
  ) RETURNING id INTO v_id;

  BEGIN
    v_match := public.match_bank_transaction(v_id);
  EXCEPTION WHEN OTHERS THEN
    v_match := jsonb_build_object('verdict', 'failed', 'reason', SQLSTATE);
  END;
  RETURN jsonb_build_object('ingest_status', 'inserted', 'stored_id', v_id,
    'match_verdict', v_match->>'verdict', 'reason', v_match->>'reason');
END;
$$;

REVOKE ALL ON FUNCTION public.process_email_transaction(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_email_transaction(jsonb) TO service_role;


-- SOURCE: eshop_transactions/get_bank_account_secret.sql
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


-- SOURCE: eshop_transactions/get_fetchable_bank_accounts_for_unit.sql
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
      AND (c.bank_account_id=ba.id OR c.id IN (SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=ba.id)))
    -- Ensure that the secret has not expired (if an expiry is set)
    AND (s.expiry_date IS NULL OR s.expiry_date > now());
END;
$$ LANGUAGE plpgsql;


-- SOURCE: eshop_transactions/get_fetchable_bank_accounts_with_t_count.sql
CREATE OR REPLACE FUNCTION public.get_fetchable_bank_accounts_with_t_count()
RETURNS TABLE (
    bank_account_id BIGINT,
    bank_secret TEXT,
    account_type TEXT,
    transaction_count_last_90_days INT
)
SET search_path = public, extensions AS $$
BEGIN
  RETURN QUERY
  SELECT
    ba.id,
    s.secret,
    ba.type,
    -- This subquery counts transactions for each fetchable bank account
    -- over the last 90 days.
    (SELECT COUNT(*)::INT
     FROM eshop.transactions t
     WHERE t.bank_account_id = ba.id
       -- The number of days has been hardcoded to 90.
       AND t."date" >= NOW() - MAKE_INTERVAL(days := 90)
    ) AS transaction_count_last_90_days
  FROM eshop.bank_accounts ba
  JOIN eshop.secrets s ON ba.secret = s.id
  WHERE ba.is_fetch_enabled = TRUE
    AND NOT EXISTS (SELECT 1 FROM eshop.bank_sync_connections c WHERE c.legacy_blocked_at IS NOT NULL
      AND (c.bank_account_id=ba.id OR c.id IN (SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=ba.id)))
    -- Check if last_fetch_time is either null or the waiting period has elapsed
    AND (ba.last_fetch_time IS NULL
         OR NOW() - ba.last_fetch_time >= (COALESCE(ba.min_fetch_wait_seconds, 0) || ' seconds')::INTERVAL)
    -- Ensure that the secret has not expired (if an expiry is set)
    AND (s.expiry_date IS NULL OR s.expiry_date > NOW());
END;
$$ LANGUAGE plpgsql;

-- SOURCE: eshop_bank_accounts/update_bank_account_token.sql
CREATE OR REPLACE FUNCTION public.update_bank_account_token(
    p_bank_account_id bigint,
    p_token text,
    p_valid_until timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_secret_id bigint;
BEGIN
  PERFORM public.require_legacy_bank_authority(p_bank_account_id);
    SELECT secret INTO v_secret_id FROM eshop.bank_accounts WHERE id = p_bank_account_id;

    -- Security Check: Caller must be an Admin of the bank account
    IF NOT EXISTS (
        SELECT 1 FROM eshop.bank_account_users 
        WHERE bank_account = p_bank_account_id AND "user" = auth.uid() AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Permission denied: Only bank account admins can update tokens.';
    END IF;

    -- Update validity date only if explicitly provided along with token or just standalone?
    -- Logic: If token is updated, invalidates expiry unless provided.
    
    IF p_token IS NOT NULL AND p_token <> '' THEN
        IF v_secret_id IS NOT NULL THEN
            UPDATE eshop.secrets
            SET secret = p_token, 
                created_at = now(),
                expiry_date = p_valid_until
            WHERE id = v_secret_id;
            
            UPDATE eshop.bank_accounts
            SET is_fetch_enabled = true,
                updated_at = NOW()
            WHERE id = p_bank_account_id;
        ELSE
            INSERT INTO eshop.secrets (secret, expiry_date)
            VALUES (p_token, p_valid_until)
            RETURNING id INTO v_secret_id;

            UPDATE eshop.bank_accounts
            SET secret = v_secret_id,
                is_fetch_enabled = true,
                updated_at = NOW()
            WHERE id = p_bank_account_id;
        END IF;
    ELSE
        -- If only updating validity date
        IF p_valid_until IS NOT NULL AND v_secret_id IS NOT NULL THEN
             UPDATE eshop.secrets
             SET expiry_date = p_valid_until
             WHERE id = v_secret_id;

             UPDATE eshop.bank_accounts
             SET is_fetch_enabled = true,
                 updated_at = NOW()
             WHERE id = p_bank_account_id;
        END IF;
    END IF;
END;
$$;


-- SOURCE: eshop_bank_accounts/regenerate_bank_account_pairing_code.sql
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


-- SOURCE: eshop_bank_accounts/update_bank_account.sql
DROP FUNCTION IF EXISTS public.update_bank_account(bigint,text,text,text,text[]);
DROP FUNCTION IF EXISTS public.update_bank_account(bigint,text,text,text,text[],text,bigint);
DROP FUNCTION IF EXISTS public.update_bank_account(bigint,text,text,text,text[],text,bigint,text);

CREATE FUNCTION public.update_bank_account(
    p_id bigint,
    p_account_number text,
    p_title text,
    p_type text DEFAULT 'FIO',
    p_supported_currencies text[] DEFAULT NULL,
    p_account_number_human_readable text DEFAULT NULL,
    p_unit_id bigint DEFAULT NULL,
    p_creditor_name text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_id bigint;
    v_account_number text;
BEGIN
    -- Prevent manual manipulation of CASH accounts
    IF p_type = 'CASH' THEN
        RAISE EXCEPTION 'CASH_ACCOUNT_MANUAL_UPDATE_FORBIDDEN';
    END IF;

    -- Input normalization
    v_account_number := TRIM(p_account_number);

    IF p_id IS NULL THEN
        -- Creation: If p_unit_id is provided, enforce that creator is Manager of that unit
        IF p_unit_id IS NOT NULL THEN
             PERFORM check_is_manager_on_unit(p_unit_id);
        END IF;

        -- Check for duplicate account number on insert
        IF EXISTS (SELECT 1 FROM eshop.bank_accounts WHERE account_number = v_account_number) THEN
             RAISE EXCEPTION 'ACCOUNT_NUMBER_EXISTS';
        END IF;

        INSERT INTO eshop.bank_accounts (account_number, title, type, supported_currencies, account_number_human_readable, creditor_name)
        VALUES (v_account_number, p_title, p_type, p_supported_currencies, p_account_number_human_readable, nullif(trim(p_creditor_name), ''))
        RETURNING id INTO v_id;

        -- Automatically make the creator an Admin
        INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin)
        VALUES (v_id, auth.uid(), true);

        -- Automatically link to unit if provided
        IF p_unit_id IS NOT NULL THEN
             INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
             VALUES (p_unit_id, v_id, 0);
        END IF;
    ELSE
        -- Check for duplicate account number on update (exclude current id)
        IF EXISTS (SELECT 1 FROM eshop.bank_accounts WHERE account_number = v_account_number AND id != p_id) THEN
             RAISE EXCEPTION 'ACCOUNT_NUMBER_EXISTS';
        END IF;

        -- Security Check: Caller must be an Admin of the bank account
        IF NOT EXISTS (
            SELECT 1 FROM eshop.bank_account_users 
            WHERE bank_account = p_id AND "user" = auth.uid() AND is_admin = true
        ) THEN
            RAISE EXCEPTION 'Permission denied: Only bank account admins can update details.';
        END IF;

        PERFORM 1 FROM eshop.bank_accounts WHERE id=p_id FOR UPDATE;
        IF EXISTS (SELECT 1 FROM eshop.bank_sync_connections WHERE bank_account_id=p_id)
          AND EXISTS (SELECT 1 FROM eshop.bank_accounts WHERE id=p_id
            AND (account_number IS DISTINCT FROM v_account_number OR type IS DISTINCT FROM p_type)) THEN
          RAISE EXCEPTION 'BANK_SYNC_ACCOUNT_IDENTITY_IMMUTABLE';
        END IF;
        UPDATE eshop.bank_accounts
        SET
            account_number = v_account_number,
            title = p_title,
            type = p_type,
            supported_currencies = p_supported_currencies,
            account_number_human_readable = p_account_number_human_readable,
            creditor_name = nullif(trim(p_creditor_name), ''),
            updated_at = NOW()
        WHERE id = p_id
        RETURNING id INTO v_id;
    END IF;
    RETURN v_id;
END;
$$;


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
        CASE WHEN s.secret IS NULL THEN NULL
             WHEN length(s.secret) <= 4 THEN '************'
             ELSE '************' || right(s.secret, 4)
        END as token_masked,
        s.expiry_date as token_expiry_date,
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
    LEFT JOIN eshop.secrets s ON ba.secret = s.id
    WHERE bau."user" = auth.uid() AND bau.is_admin = true
    AND ba.type != 'cash'
    ORDER BY ba.title;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_admin_bank_accounts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_admin_bank_accounts() TO authenticated, service_role;


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
        CASE 
            WHEN s.secret IS NOT NULL THEN 
                '************' || right(s.secret, 4)
            ELSE NULL 
        END as token_masked,
        s.expiry_date as token_expiry_date,
        ba.supported_currencies,
        ba.last_fio_fetch_time,
        CASE WHEN EXISTS(SELECT 1 FROM eshop.bank_account_users WHERE bank_account=ba.id AND "user"=auth.uid() AND is_admin)
          THEN public.get_bank_sync_connection(ba.id) ELSE (SELECT jsonb_build_object('state',state,'mode',mode) FROM eshop.bank_sync_connections WHERE bank_account_id=ba.id) END AS bank_sync
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    LEFT JOIN eshop.secrets s ON ba.secret = s.id
    WHERE uba.unit = p_unit_id
    AND ba.type != 'CASH'; -- Exclude Cash Accounts from management list
END;
$$;

REVOKE ALL ON FUNCTION public.get_bank_accounts_for_unit_management(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_bank_accounts_for_unit_management(bigint) TO authenticated, service_role;

