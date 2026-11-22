-- Admin-confirmed email observations; no automatic email pairing.

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
  provider text NOT NULL CHECK(provider IN ('FIO','AIRBANK','CSOB','MONETA','CREDITAS','RAIFFEISENBANK','UNICREDIT','CSAS')),
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
-- Continuous failed observations drive UI warnings independently of email incidents.
ALTER TABLE eshop.bank_sync_connections ADD COLUMN IF NOT EXISTS failure_since timestamptz;
ALTER TABLE eshop.bank_sync_connections ADD COLUMN IF NOT EXISTS failure_observed_at timestamptz;

-- Tokens are issued before remote I/O, then accepted once in start order.
CREATE SEQUENCE IF NOT EXISTS eshop.bank_sync_observation_ids;
REVOKE ALL ON SEQUENCE eshop.bank_sync_observation_ids FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE eshop.bank_sync_connections ADD COLUMN IF NOT EXISTS observation_id bigint NOT NULL DEFAULT 0;

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
  resolution jsonb,
  diagnostics jsonb,
  resolved_at timestamptz,
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
  operation text NOT NULL CHECK(operation IN ('create','set_token','rotate_pairing','sync','suspend','resume','update_details')),
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

-- Supported notification providers; existing connection identities remain unchanged.
ALTER TABLE eshop.bank_sync_connections DROP CONSTRAINT IF EXISTS bank_sync_connections_provider_check;
ALTER TABLE eshop.bank_sync_connections ADD CONSTRAINT bank_sync_connections_provider_check CHECK(provider IN ('FIO','AIRBANK','CSOB','MONETA','CREDITAS','RAIFFEISENBANK','UNICREDIT','CSAS'));

-- Internal ingestion evidence is separate from the bounded BankSync receipt.
ALTER TABLE eshop.bank_sync_inbox ADD COLUMN IF NOT EXISTS diagnostics jsonb;
CREATE INDEX IF NOT EXISTS transactions_email_confirmed_adoption_idx
 ON eshop.transactions(bank_account_id,amount,date) WHERE ingest_source='banksync_email_confirmed';
CREATE INDEX IF NOT EXISTS transactions_bank_email_duplicate_idx
 ON eshop.transactions(bank_account_id,date)
 WHERE ingest_source IN ('banksync_email_confirmed','banksync_api','fio_api','legacy_api','legacy');
CREATE INDEX IF NOT EXISTS bank_sync_inbox_unresolved_queue_idx
 ON eshop.bank_sync_inbox(connection_id,received_at,delivery_id) WHERE resolution IS NULL;

-- SOURCE: eshop_transactions/match_bank_transaction.sql
-- One extraction owner for automatic matching, email suggestions and identity checks.
CREATE OR REPLACE FUNCTION public.bank_transaction_signals_internal(
 p_vs text,p_reference text,p_message text,p_identification text DEFAULT NULL,p_comment text DEFAULT NULL
) RETURNS TABLE(kind text,value text) LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 WITH raw_signals(kind, value) AS (
    SELECT 'vs', trim(p_vs)
      WHERE trim(COALESCE(p_vs, '')) ~ '^[0-9]{1,10}$'
    UNION ALL
    SELECT 'rf', public.normalize_creditor_reference(p_reference)
      WHERE p_reference IS NOT NULL
        AND public.is_valid_creditor_reference(p_reference)
    UNION ALL
    SELECT 'rf', public.normalize_creditor_reference(m.captures[2])
      FROM regexp_matches(
        upper(concat_ws(E'\n', p_message,
          p_identification, p_comment)),
        '(^|[^A-Z0-9])(RF[0-9]{2}[A-Z0-9[:space:]]{1,25})([^A-Z0-9]|$)', 'g'
      ) AS m(captures)
      WHERE public.is_valid_creditor_reference(m.captures[2])
    UNION ALL
    SELECT 'vs', trim(p_message)
      WHERE nullif(trim(COALESCE(p_vs, '')), '') IS NULL
        AND trim(COALESCE(p_message, '')) ~ '^[0-9]{1,10}$'
    UNION ALL
    SELECT 'vs', substring(p_message
      FROM '(?i)(?:VS|variabilní symbol)[[:space:]]*[:=-]?[[:space:]]*([0-9]{1,10})')
      WHERE nullif(trim(COALESCE(p_vs, '')), '') IS NULL
        AND substring(p_message
          FROM '(?i)(?:VS|variabilní symbol)[[:space:]]*[:=-]?[[:space:]]*([0-9]{1,10})') IS NOT NULL

 ) SELECT DISTINCT kind,CASE WHEN kind='vs' THEN value::bigint::text ELSE value END FROM raw_signals;
$$;
REVOKE ALL ON FUNCTION public.bank_transaction_signals_internal(text,text,text,text,text) FROM PUBLIC,anon,authenticated,service_role;

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
  IF public.is_demo_bank_account((SELECT bank_account_id FROM eshop.transactions WHERE id=p_transaction_id)) THEN
    RETURN jsonb_build_object('outcome','skipped_demo');
  END IF;
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

  WITH signals AS (
    SELECT * FROM public.bank_transaction_signals_internal(v_transaction.vs,v_transaction.payer_reference,
      v_transaction.message_for_recipient,v_transaction.user_identification,v_transaction.comment)
  ), candidates AS (
    SELECT DISTINCT pi.id
    FROM signals s
    JOIN eshop.payment_info pi
      ON (s.kind = 'rf' AND pi.creditor_reference = s.value)
      OR (s.kind = 'vs' AND pi.variable_symbol = CASE WHEN s.kind='vs' THEN s.value::bigint END)
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

-- SOURCE: eshop_bank_sync/bank_sync_existing_facts_match.sql
-- Shared legacy-offset and bank-local date owner. Stored transaction dates are UTC.
CREATE OR REPLACE FUNCTION public.bank_sync_fact_dates_match_internal(p_tx eshop.transactions,p_data jsonb,p_days integer)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE tx_day date; incoming_day date; v_shift interval; v_offset integer;
BEGIN
 IF p_tx.ingest_source IN ('legacy','legacy_api','fio_api')
   AND p_data->>'date_offset_min' ~ '^-?[0-9]{1,3}$' THEN
  v_offset:=(p_data->>'date_offset_min')::integer;
 END IF;
 IF abs(v_offset)<=840 THEN
  v_shift:=make_interval(mins=>v_offset);
  tx_day:=(p_tx.date+v_shift)::date;
  incoming_day:=(((p_data->>'date')::timestamptz AT TIME ZONE 'UTC')+v_shift)::date;
 ELSE
  tx_day:=((p_tx.date AT TIME ZONE 'UTC') AT TIME ZONE 'Europe/Prague')::date;
  incoming_day:=((p_data->>'date')::timestamptz AT TIME ZONE 'Europe/Prague')::date;
 END IF;
 RETURN abs(tx_day-incoming_day)<=p_days;
END;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_fact_dates_match_internal(eshop.transactions,jsonb,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.bank_sync_fact_dates_match_internal(eshop.transactions,jsonb,integer) TO service_role;

-- Legacy Fio stored offset midnight as UTC; BankSync date-only statements use
-- noon UTC to retain the original bank date. Compare historical facts in the
-- bank's supplied offset, without rewriting either representation.
CREATE OR REPLACE FUNCTION public.bank_sync_existing_facts_match(p_tx eshop.transactions,p_data jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
BEGIN
  RETURN p_tx.amount IS NOT DISTINCT FROM (p_data->>'amount_cents')::numeric/100
    AND trim(p_tx.currency) IS NOT DISTINCT FROM p_data->>'currency'
    AND public.bank_sync_fact_dates_match_internal(p_tx,p_data,0)
    AND nullif(trim(p_tx.vs),'') IS NOT DISTINCT FROM nullif(p_data->>'raw_vs','')
    AND (p_tx.payer_reference IS NULL OR p_tx.payer_reference IS NOT DISTINCT FROM p_data->>'payer_reference');
END;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_existing_facts_match(eshop.transactions,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.bank_sync_existing_facts_match(eshop.transactions,jsonb) TO service_role;

-- SOURCE: eshop_bank_sync/bank_sync_email_confirmation.sql
CREATE OR REPLACE FUNCTION public.bank_sync_counter_account_internal(p_account text,p_code text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN nullif(a,'') IS NULL THEN NULL
  WHEN a LIKE '%/%' OR a ~ '^[A-Z]{2}' OR nullif(c,'') IS NULL THEN a ELSE a||'/'||c END
 FROM (SELECT upper(regexp_replace(coalesce(p_account,''),'[[:space:]]','','g')) a,
   regexp_replace(coalesce(p_code,''),'[[:space:]]','','g') c) x;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_counter_account_internal(text,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_email_possible_duplicate_internal(p_tx eshop.transactions,p_data jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT p_tx.amount IS NOT DISTINCT FROM (p_data->>'amount_cents')::numeric/100
  AND upper(trim(p_tx.currency)) IS NOT DISTINCT FROM upper(trim(p_data->>'currency'))
  AND public.bank_sync_fact_dates_match_internal(p_tx,p_data,1)
  AND (EXISTS(SELECT FROM public.bank_transaction_signals_internal(p_tx.vs,p_tx.payer_reference,
        p_tx.message_for_recipient,p_tx.user_identification,p_tx.comment) a
      JOIN public.bank_transaction_signals_internal(p_data->>'raw_vs',p_data->>'payer_reference',
        p_data->>'message',p_data->>'user_identification',p_data->>'comment') b USING(kind,value))
    OR (NOT EXISTS(SELECT FROM public.bank_transaction_signals_internal(p_tx.vs,p_tx.payer_reference,
        p_tx.message_for_recipient,p_tx.user_identification,p_tx.comment))
      AND NOT EXISTS(SELECT FROM public.bank_transaction_signals_internal(p_data->>'raw_vs',p_data->>'payer_reference',
        p_data->>'message',p_data->>'user_identification',p_data->>'comment'))
      AND public.bank_sync_counter_account_internal(p_tx.counter_account,p_tx.bank_code) IS NOT NULL
      AND public.bank_sync_counter_account_internal(p_tx.counter_account,p_tx.bank_code)
        =public.bank_sync_counter_account_internal(p_data->>'counter_account',p_data->>'bank_code')));

$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_possible_duplicate_internal(eshop.transactions,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_email_transaction_matches(p_tx eshop.transactions,p_data jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT public.bank_sync_email_possible_duplicate_internal(p_tx,p_data)
  AND public.bank_sync_fact_dates_match_internal(p_tx,p_data,0)
  AND public.bank_sync_counter_account_internal(p_tx.counter_account,p_tx.bank_code)
    IS NOT DISTINCT FROM public.bank_sync_counter_account_internal(p_data->>'counter_account',p_data->>'bank_code')
  AND (SELECT coalesce(jsonb_agg(jsonb_build_array(kind,value) ORDER BY kind,value),'[]')
    FROM public.bank_transaction_signals_internal(p_tx.vs,p_tx.payer_reference,p_tx.message_for_recipient,
       p_tx.user_identification,p_tx.comment))
    = (SELECT coalesce(jsonb_agg(jsonb_build_array(kind,value) ORDER BY kind,value),'[]')
    FROM public.bank_transaction_signals_internal(p_data->>'raw_vs',p_data->>'payer_reference',p_data->>'message',
       p_data->>'user_identification',p_data->>'comment'));
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_transaction_matches(eshop.transactions,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- The connection lock held by the caller serializes both sides of ingestion.
CREATE OR REPLACE FUNCTION public.bank_sync_email_duplicate_candidates_internal(p_connection bigint,p_data jsonb,p_unadopted boolean)
RETURNS bigint[] LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH accounts AS (
  SELECT bank_account_id FROM eshop.bank_sync_connections WHERE id=p_connection
  UNION SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection
 ), prefiltered AS MATERIALIZED (
  SELECT t AS fact FROM accounts a JOIN eshop.transactions t ON t.bank_account_id=a.bank_account_id
  WHERE t.amount=(p_data->>'amount_cents')::numeric/100
   AND t.date BETWEEN ((p_data->>'date')::timestamptz AT TIME ZONE 'UTC')-interval '2 days'
                  AND ((p_data->>'date')::timestamptz AT TIME ZONE 'UTC')+interval '2 days'
   AND upper(trim(t.currency))=upper(trim(p_data->>'currency'))
   AND CASE WHEN p_unadopted THEN t.ingest_source='banksync_email_confirmed'
      AND NOT EXISTS(SELECT FROM eshop.bank_transaction_identities i WHERE i.transaction_id=t.id AND i.identity_kind='movement')
     ELSE t.ingest_source IN ('banksync_email_confirmed','banksync_api','fio_api','legacy_api','legacy') END
 )
 SELECT coalesce(array_agg((fact).id::bigint ORDER BY (fact).id),'{}'::bigint[]) FROM prefiltered
 WHERE public.bank_sync_email_possible_duplicate_internal(fact,p_data);
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_duplicate_candidates_internal(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_email_duplicate_resolution_internal(p_transaction bigint,p_actor uuid)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('action','duplicate_of','actor_id',p_actor,'resolved_at',now(),
   'transaction_id',t.id,'transaction_paired',t.payment_info IS NOT NULL,'payment_info_id',t.payment_info,
   'delivery_id',(
    SELECT i.delivery_id FROM eshop.bank_sync_connections c JOIN eshop.bank_sync_inbox i ON i.connection_id=c.id
    WHERE (c.bank_account_id=t.bank_account_id OR EXISTS(SELECT FROM eshop.bank_sync_account_aliases a
       WHERE a.connection_id=c.id AND a.bank_account_id=t.bank_account_id))
     AND nullif(i.payload->'data'->>'date','') IS NOT NULL
     AND (i.payload->'data'->>'date')::timestamptz BETWEEN (t.date AT TIME ZONE 'UTC')-interval '2 days'
       AND (t.date AT TIME ZONE 'UTC')+interval '2 days'
     AND (i.diagnostics->>'transaction_id'=t.id::text OR
       (i.resolution->>'action'='confirmed' AND i.resolution->>'transaction_id'=t.id::text))
    ORDER BY i.received_at,i.delivery_id LIMIT 1))
 FROM eshop.transactions t WHERE t.id=p_transaction;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_duplicate_resolution_internal(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_email_possible_duplicates_view_internal(p_ids bigint[])
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('transaction_id',t.id,'ingest_source',t.ingest_source,
  'transaction_paired',t.payment_info IS NOT NULL,
  'order_symbol',CASE WHEN o.occasion IS NOT NULL AND public.can_read_orders(o.occasion) THEN o.order_symbol END,
  'order_number',CASE WHEN o.occasion IS NOT NULL AND public.can_read_orders(o.occasion) THEN o.order_sequence END,
  'facts',jsonb_build_object('amount_cents',round(t.amount*100)::bigint,'currency',trim(t.currency),
    'date',t.date AT TIME ZONE 'UTC','raw_vs',nullif(trim(t.vs),''),'counter_account',t.counter_account,
    'bank_code',t.bank_code,'payer_reference',t.payer_reference)) ORDER BY t.id),'[]')
 FROM eshop.transactions t LEFT JOIN eshop.orders o ON o.payment_info=t.payment_info WHERE t.id=ANY(p_ids);
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_possible_duplicates_view_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- Account authorization is completed before callers read any inbox facts,
-- digests or resolutions. In particular an alias alone grants no source access.
CREATE OR REPLACE FUNCTION public.bank_sync_email_authorized_connection_internal(p_bank_account bigint)
RETURNS eshop.bank_sync_connections LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE v_connection eshop.bank_sync_connections;
BEGIN
 PERFORM public.check_is_admin_for_bank_account(p_bank_account);
 SELECT bc.* INTO v_connection FROM eshop.bank_sync_connections bc WHERE bc.bank_account_id=p_bank_account
  OR EXISTS(SELECT FROM eshop.bank_sync_account_aliases a WHERE a.bank_account_id=p_bank_account AND a.connection_id=bc.id);
 IF v_connection.id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_OBSERVATION_NOT_FOUND'; END IF;
 PERFORM public.check_is_admin_for_bank_account(v_connection.bank_account_id);
 RETURN v_connection;
END;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_authorized_connection_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- One payable/editable target set for suggestions, manual lookup and mutation.
-- Paid/sent orders are excluded: this queue does not create overpayments there.
CREATE OR REPLACE FUNCTION public.bank_sync_email_payable_targets_for_ids_internal(p_account bigint,p_currency text,p_ids bigint[])
RETURNS TABLE(payment_info_id bigint,order_id bigint,occasion_id bigint,candidate jsonb)
LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH eligible AS MATERIALIZED (
  SELECT pi.id,pi.amount,pi.currency_code,o.id AS order_id,o.occasion,o.order_symbol,o.order_sequence,o.state,o.data
  FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id JOIN public.occasions oc ON oc.id=o.occasion
  WHERE pi.id=ANY(p_ids) AND pi.bank_account=p_account AND pi.payment_method='bank'
   AND upper(trim(pi.currency_code))=upper(trim(p_currency)) AND pi.amount>0
   AND o.state IN ('created','ordered','expired')
   AND NOT public.is_demo_occasion(o.occasion) AND NOT public.is_demo_bank_account(p_account)
   AND public.can_write_orders(o.occasion)
   AND EXISTS(SELECT FROM eshop.unit_bank_accounts a WHERE a.unit=oc.unit AND a.bank_account=p_account)
 ), totals AS MATERIALIZED (
  SELECT * FROM public.payment_financial_totals_bulk_internal((SELECT coalesce(array_agg(id::bigint),'{}'::bigint[]) FROM eligible))
 )
 SELECT e.id::bigint,e.order_id::bigint,e.occasion::bigint,jsonb_build_object(
  'payment_info_id',e.id,'order_id',e.order_id,'order_symbol',e.order_symbol,'order_number',e.order_sequence,
  'state',e.state,'customer_name',coalesce(e.data->>'name',concat_ws(' ',e.data->>'first_name',e.data->>'last_name')),
  'customer_email',e.data->>'email','remaining_due',greatest(e.amount-t.available,0),'currency',upper(trim(e.currency_code)))
 FROM eligible e JOIN totals t ON t.payment_id=e.id WHERE e.amount>t.available;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_payable_targets_for_ids_internal(bigint,text,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_email_lookup_signals_internal(p_query text)
RETURNS TABLE(kind text,value text) LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT 'vs',substring(trim(p_query) FROM '(?i)^(?:(?:VS|variabilní symbol)[[:space:]]*[:=-]?[[:space:]]*)?([0-9]{1,10})$')::bigint::text
 WHERE trim(coalesce(p_query,'')) ~ '(?i)^(?:(?:VS|variabilní symbol)[[:space:]]*[:=-]?[[:space:]]*)?[0-9]{1,10}$'
 UNION SELECT 'rf',public.normalize_creditor_reference(p_query)
 WHERE p_query IS NOT NULL AND public.is_valid_creditor_reference(p_query);
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_lookup_signals_internal(text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_email_candidates_internal(p_account bigint,p_facts jsonb,p_query text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH signals AS MATERIALIZED (
  SELECT * FROM public.bank_transaction_signals_internal(p_facts->>'raw_vs',p_facts->>'payer_reference',
    p_facts->>'message',p_facts->>'user_identification',p_facts->>'comment') WHERE p_query IS NULL
  UNION SELECT * FROM public.bank_sync_email_lookup_signals_internal(p_query) WHERE p_query IS NOT NULL
 ), matched AS MATERIALIZED (
  SELECT pi.id FROM signals s JOIN eshop.payment_info pi ON pi.variable_symbol=CASE WHEN s.kind='vs' THEN s.value::bigint END
   WHERE s.kind='vs' AND pi.bank_account=p_account AND pi.payment_method='bank'
    AND upper(trim(pi.currency_code))=upper(trim(p_facts->>'currency'))
  UNION SELECT pi.id FROM signals s JOIN eshop.payment_info pi ON pi.creditor_reference=s.value
   WHERE s.kind='rf' AND pi.bank_account=p_account AND pi.payment_method='bank'
    AND upper(trim(pi.currency_code))=upper(trim(p_facts->>'currency'))
  UNION SELECT pi.id FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
   WHERE p_query IS NOT NULL
    AND (o.order_symbol=trim(p_query) OR o.order_symbol=upper(trim(p_query))
      OR (trim(p_query) ~ '^[0-9]{1,18}$' AND o.order_sequence=trim(p_query)::bigint))
    AND pi.bank_account=p_account AND pi.payment_method='bank'
    AND upper(trim(pi.currency_code))=upper(trim(p_facts->>'currency'))
 )
 SELECT coalesce(jsonb_agg(target.candidate||jsonb_build_object('amount_matches',
  (target.candidate->>'remaining_due')::numeric=(p_facts->>'amount_cents')::numeric/100) ORDER BY target.order_id),'[]')
 FROM public.bank_sync_email_payable_targets_for_ids_internal(p_account,p_facts->>'currency',
   (SELECT coalesce(array_agg(id::bigint),'{}'::bigint[]) FROM matched)) target;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_candidates_internal(bigint,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.find_bank_sync_email_targets_v1(p_bank_account_id bigint,p_facts jsonb,p_query text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.bank_sync_email_authorized_connection_internal(p_bank_account_id);
 IF p_query IS NULL OR length(trim(p_query)) NOT BETWEEN 1 AND 100 OR octet_length(p_facts::text)>65536 THEN
  RAISE EXCEPTION 'BANK_SYNC_LOOKUP_INVALID'; END IF;
 RETURN public.bank_sync_email_candidates_internal(p_bank_account_id,p_facts,p_query);
END;
$$;
REVOKE ALL ON FUNCTION public.find_bank_sync_email_targets_v1(bigint,jsonb,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.find_bank_sync_email_targets_v1(bigint,jsonb,text) TO authenticated;

-- Keyset paging is stable when earlier rows are resolved by another admin.
CREATE OR REPLACE FUNCTION public.get_bank_sync_email_queue_page_v1(p_bank_account_id bigint,p_limit integer DEFAULT 50,p_cursor jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_connection eshop.bank_sync_connections; v_result jsonb; v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
BEGIN
 v_connection:=public.bank_sync_email_authorized_connection_internal(p_bank_account_id);
 SELECT coalesce(jsonb_agg(item ORDER BY received_at,delivery_id),'[]') INTO v_result FROM (
  SELECT i.received_at,i.delivery_id,jsonb_build_object('delivery_id',i.delivery_id,'body_sha256',i.body_sha256,
   'facts',i.payload->'data','received_at',i.received_at,'confirmable',true,
   'exact_duplicate',cardinality(d.ids)=1 AND (SELECT t.ingest_source<>'banksync_email_confirmed'
     AND public.bank_sync_email_transaction_matches(t,i.payload->'data') FROM eshop.transactions t WHERE t.id=d.ids[1]),
   'possible_duplicates',public.bank_sync_email_possible_duplicates_view_internal(
      d.ids),
   'candidates',public.bank_sync_email_candidates_internal(p_bank_account_id,i.payload->'data')) AS item
  FROM eshop.bank_sync_inbox i
  CROSS JOIN LATERAL (SELECT public.bank_sync_email_duplicate_candidates_internal(
    v_connection.id,i.payload->'data',false) AS ids) d
  WHERE i.connection_id=v_connection.id
   AND (i.payload->'data'->>'source' ~ '(^|_)email$')
   AND i.outcome IN ('quarantined_identity','quarantined_conflict') AND i.resolution IS NULL
   AND (i.payload->'data'->>'amount_cents')::numeric>0
   AND (p_cursor IS NULL OR (i.received_at,i.delivery_id)>
     ((p_cursor->>'received_at')::timestamptz,p_cursor->>'delivery_id'))
  ORDER BY i.received_at,i.delivery_id LIMIT v_limit+1
 ) q;
 RETURN jsonb_build_object('items',(SELECT coalesce(jsonb_agg(value ORDER BY ordinality),'[]')
   FROM jsonb_array_elements(v_result) WITH ORDINALITY WHERE ordinality<=v_limit),
  'next_cursor',CASE WHEN jsonb_array_length(v_result)>v_limit THEN jsonb_build_object(
    'received_at',v_result->(v_limit-1)->'received_at','delivery_id',v_result->(v_limit-1)->'delivery_id') END);
END;
$$;
REVOKE ALL ON FUNCTION public.get_bank_sync_email_queue_page_v1(bigint,integer,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_sync_email_queue_page_v1(bigint,integer,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.confirm_bank_sync_email_observation(
 p_bank_account_id bigint,p_delivery_id text,p_payment_info_id bigint,
 p_expected_body_sha256 text,p_checked_internet_banking boolean,p_not_duplicate boolean DEFAULT false
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE
 v_connection eshop.bank_sync_connections; v_inbox eshop.bank_sync_inbox; v_payment eshop.payment_info;
 v_data jsonb; v_transaction_id bigint; v_result jsonb; v_organization bigint; v_unit bigint; v_occasion bigint; v_order bigint; v_ids bigint[];
BEGIN
 v_connection:=public.bank_sync_email_authorized_connection_internal(p_bank_account_id);
 -- Order authorization also precedes inbox access, digest tests and replay.
 SELECT oc.organization,oc.unit,oc.id,o.id INTO v_organization,v_unit,v_occasion,v_order FROM eshop.orders o
 JOIN public.occasions oc ON oc.id=o.occasion WHERE o.payment_info=p_payment_info_id;
 IF v_occasion IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 PERFORM public.check_is_editor_order_on_occasion(v_occasion);
 IF p_checked_internet_banking IS DISTINCT FROM true THEN RAISE EXCEPTION 'BANK_SYNC_ATTESTATION_REQUIRED'; END IF;
 -- Recovery of an existing bank receipt is independent of new-sales policy.
 PERFORM public.payment_policy_fence_internal(v_organization);
 PERFORM pg_advisory_xact_lock(hashtextextended(v_connection.instance_id||':'||v_connection.consumer_app_id||':'||p_delivery_id,0));
 SELECT * INTO v_connection FROM eshop.bank_sync_connections WHERE id=v_connection.id FOR UPDATE;
 PERFORM public.check_is_admin_for_bank_account(v_connection.bank_account_id);
 SELECT * INTO v_inbox FROM eshop.bank_sync_inbox WHERE instance_id=v_connection.instance_id
  AND consumer_app_id=v_connection.consumer_app_id AND delivery_id=p_delivery_id AND connection_id=v_connection.id FOR UPDATE;
 IF v_inbox.delivery_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_OBSERVATION_NOT_FOUND'; END IF;
 IF v_inbox.body_sha256 IS DISTINCT FROM p_expected_body_sha256 THEN RAISE EXCEPTION 'BANK_SYNC_DELIVERY_CONFLICT'; END IF;
 IF (v_inbox.payload->'data'->>'source' ~ '(^|_)email$') IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'BANK_SYNC_NOT_CONFIRMABLE'; END IF;
 IF v_inbox.resolution IS NOT NULL THEN
  IF (v_inbox.resolution->>'action'='confirmed' AND (v_inbox.resolution->>'payment_info_id')::bigint=p_payment_info_id)
    OR v_inbox.resolution->>'action'='duplicate_of' THEN
   RETURN v_inbox.resolution||jsonb_build_object('transaction_paired',coalesce((SELECT t.payment_info IS NOT NULL
     FROM eshop.transactions t WHERE t.id=(v_inbox.resolution->>'transaction_id')::bigint),false));
  END IF;
  RAISE EXCEPTION 'BANK_SYNC_ALREADY_RESOLVED';
 END IF;
 v_data:=v_inbox.payload->'data';
 IF v_inbox.outcome IS NULL OR v_inbox.outcome NOT IN ('quarantined_identity','quarantined_conflict')
  OR (v_data->>'source' ~ '(^|_)email$') IS DISTINCT FROM true
  OR ((v_data->>'amount_cents')::numeric>0) IS DISTINCT FROM true OR v_connection.legacy_blocked_at IS NULL THEN
  RAISE EXCEPTION 'BANK_SYNC_NOT_CONFIRMABLE'; END IF;
 SELECT * INTO v_payment FROM eshop.payment_info WHERE id=p_payment_info_id;
 IF v_payment.bank_account IS DISTINCT FROM p_bank_account_id OR v_payment.payment_method IS DISTINCT FROM 'bank'
   OR upper(trim(v_payment.currency_code)) IS DISTINCT FROM upper(trim(v_data->>'currency')) THEN
  RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 v_ids:=public.bank_sync_email_duplicate_candidates_internal(v_connection.id,v_data,false);
 IF cardinality(v_ids)=1 AND (SELECT t.ingest_source<>'banksync_email_confirmed'
    AND public.bank_sync_email_transaction_matches(t,v_data) FROM eshop.transactions t WHERE t.id=v_ids[1]) THEN
  v_result:=public.bank_sync_email_duplicate_resolution_internal(v_ids[1],auth.uid())
    ||jsonb_build_object('facts',v_data,'actor_kind','user','checked_internet_banking',true);
  UPDATE eshop.bank_sync_inbox SET resolution=v_result,resolved_at=now()
   WHERE instance_id=v_inbox.instance_id AND consumer_app_id=v_inbox.consumer_app_id AND delivery_id=v_inbox.delivery_id;
  RETURN v_result;
 END IF;
 IF cardinality(v_ids)>0 AND p_not_duplicate IS DISTINCT FROM true THEN
  RETURN jsonb_build_object('action','possible_duplicate','transaction_paired',false,
    'possible_duplicates',public.bank_sync_email_possible_duplicates_view_internal(v_ids));
 END IF;
 IF NOT EXISTS(SELECT FROM public.bank_sync_email_payable_targets_for_ids_internal(p_bank_account_id,v_data->>'currency',ARRAY[p_payment_info_id])
   WHERE payment_info_id=p_payment_info_id AND occasion_id=v_occasion) THEN RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,vs,ks,ss,payer_reference,
  message_for_recipient,counter_account,counter_account_name,bank_code,bank_name,user_identification,comment,ingest_source)
 VALUES(v_connection.bank_account_id,(v_data->>'amount_cents')::numeric/100,upper(trim(v_data->>'currency')),
  (v_data->>'date')::timestamptz AT TIME ZONE 'UTC',nullif(v_data->>'raw_vs',''),v_data->>'ks',v_data->>'ss',
  v_data->>'payer_reference',v_data->>'message',v_data->>'counter_account',v_data->>'sender_name',v_data->>'bank_code',v_data->>'bank_name',v_data->>'user_identification',v_data->>'comment',
  'banksync_email_confirmed') RETURNING id INTO v_transaction_id;
 -- Acquire the same order/payment locks as pairing, then validate eligibility
 -- again. A concurrent confirmation cannot turn a paid order into an overpayment.
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[v_order]);
 PERFORM 1 FROM eshop.payment_info WHERE id=p_payment_info_id FOR UPDATE;
 IF NOT EXISTS(SELECT FROM public.bank_sync_email_payable_targets_for_ids_internal(p_bank_account_id,v_data->>'currency',ARRAY[p_payment_info_id])
   WHERE payment_info_id=p_payment_info_id AND occasion_id=v_occasion) THEN RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 v_result:=jsonb_build_object('action','confirmed','actor_id',auth.uid(),'confirmed_at',now(),
  'payment_info_id',p_payment_info_id,'transaction_id',v_transaction_id,'facts',v_data,'checked_internet_banking',true,
  'not_duplicate',p_not_duplicate IS TRUE,'possible_duplicate_transaction_ids',coalesce(to_jsonb(v_ids),'[]'),
  'transaction_paired',true);
 UPDATE eshop.bank_sync_inbox SET resolution=v_result,resolved_at=now()
 WHERE instance_id=v_inbox.instance_id AND consumer_app_id=v_inbox.consumer_app_id AND delivery_id=v_inbox.delivery_id;
 PERFORM public.apply_transaction_pairing(v_transaction_id,p_payment_info_id,'email_admin_confirmation','user',
  jsonb_build_object('delivery_id',p_delivery_id,'checked_internet_banking',true,'not_duplicate',p_not_duplicate IS TRUE));
 -- Pairing locked the stored order and payment. Recheck scope and permissions;
 -- payable state was intentionally consumed by the successful paid transition.
 PERFORM public.check_is_editor_order_on_occasion(v_occasion);
 IF NOT EXISTS(SELECT FROM eshop.payment_info target_payment JOIN eshop.orders o ON o.payment_info=target_payment.id
   JOIN public.occasions oc ON oc.id=o.occasion JOIN eshop.unit_bank_accounts a ON a.unit=oc.unit AND a.bank_account=target_payment.bank_account
   WHERE target_payment.id=p_payment_info_id AND target_payment.bank_account=p_bank_account_id AND target_payment.payment_method='bank'
    AND upper(trim(target_payment.currency_code))=upper(trim(v_data->>'currency')) AND oc.id=v_occasion AND oc.unit=v_unit AND oc.organization=v_organization) THEN
  RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_bank_sync_email_observation(bigint,text,bigint,text,boolean,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.confirm_bank_sync_email_observation(bigint,text,bigint,text,boolean,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.dismiss_bank_sync_email_observation(p_bank_account_id bigint,p_delivery_id text,p_expected_body_sha256 text,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_connection eshop.bank_sync_connections; v_inbox eshop.bank_sync_inbox; v_result jsonb;
BEGIN
 v_connection:=public.bank_sync_email_authorized_connection_internal(p_bank_account_id);
 IF length(trim(p_reason)) NOT BETWEEN 1 AND 240 OR p_reason IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_DISMISS_REASON_REQUIRED'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(v_connection.instance_id||':'||v_connection.consumer_app_id||':'||p_delivery_id,0));
 SELECT * INTO v_connection FROM eshop.bank_sync_connections WHERE id=v_connection.id FOR UPDATE;
 PERFORM public.check_is_admin_for_bank_account(v_connection.bank_account_id);
 SELECT * INTO v_inbox FROM eshop.bank_sync_inbox WHERE instance_id=v_connection.instance_id AND consumer_app_id=v_connection.consumer_app_id
  AND connection_id=v_connection.id AND delivery_id=p_delivery_id FOR UPDATE;
 IF v_inbox.delivery_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_OBSERVATION_NOT_FOUND'; END IF;
 IF v_inbox.body_sha256 IS DISTINCT FROM p_expected_body_sha256 THEN RAISE EXCEPTION 'BANK_SYNC_DELIVERY_CONFLICT'; END IF;
 IF (v_inbox.payload->'data'->>'source' ~ '(^|_)email$') IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'BANK_SYNC_NOT_CONFIRMABLE'; END IF;
 IF v_inbox.resolution IS NOT NULL THEN
  IF v_inbox.resolution->>'action'='dismissed' AND v_inbox.resolution->>'reason'=trim(p_reason) THEN RETURN v_inbox.resolution; END IF;
  RAISE EXCEPTION 'BANK_SYNC_ALREADY_RESOLVED';
 END IF;
 IF (v_inbox.payload->'data'->>'source' ~ '(^|_)email$') IS DISTINCT FROM true OR v_inbox.outcome IS NULL OR v_inbox.outcome NOT IN ('quarantined_identity','quarantined_conflict') THEN RAISE EXCEPTION 'BANK_SYNC_NOT_CONFIRMABLE'; END IF;
 v_result:=jsonb_build_object('action','dismissed','actor_id',auth.uid(),'resolved_at',now(),'reason',trim(p_reason),'facts',v_inbox.payload->'data');
 UPDATE eshop.bank_sync_inbox SET resolution=v_result,resolved_at=now()
  WHERE instance_id=v_inbox.instance_id AND consumer_app_id=v_inbox.consumer_app_id AND delivery_id=v_inbox.delivery_id;
 RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.dismiss_bank_sync_email_observation(bigint,text,text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.dismiss_bank_sync_email_observation(bigint,text,text,text) TO authenticated;

-- SOURCE: eshop_bank_sync/bank_sync_authority.sql
CREATE OR REPLACE FUNCTION public.bank_sync_accounts_match(p_transaction_id bigint,p_target_account bigint)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
  SELECT EXISTS (
    SELECT 1 FROM eshop.transactions t
    JOIN eshop.bank_transaction_identities i ON i.transaction_id=t.id AND i.identity_kind='movement'
    JOIN eshop.bank_sync_connections c ON c.instance_id=i.instance_id AND c.provider=i.provider
      AND c.physical_account=i.physical_account AND c.bank_account_id=t.bank_account_id
    WHERE t.id=p_transaction_id AND t.ingest_source IN ('banksync_api','banksync_email_confirmed') AND c.legacy_blocked_at IS NOT NULL
      AND (p_target_account=c.bank_account_id OR p_target_account IN
        (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id))
  ) OR EXISTS (
    SELECT 1 FROM eshop.transactions t
    JOIN eshop.bank_sync_inbox i ON (i.resolution->>'transaction_id')::bigint=t.id
      AND i.resolution->>'action'='confirmed'
    JOIN eshop.bank_sync_connections c ON c.id=i.connection_id AND c.bank_account_id=t.bank_account_id
    WHERE t.id=p_transaction_id AND t.ingest_source='banksync_email_confirmed'
      AND c.legacy_blocked_at IS NOT NULL
      AND (p_target_account=c.bank_account_id OR EXISTS(SELECT 1 FROM eshop.bank_sync_account_aliases a
        WHERE a.connection_id=c.id AND a.bank_account_id=p_target_account))
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
  PERFORM public.notification_center_bank_incident_internal(p_connection_id);
END;
$$;
REVOKE ALL ON FUNCTION public.activate_bank_sync_connection(bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.activate_bank_sync_connection(bigint,text) TO service_role;

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
  v_refund jsonb;
  v_resolution jsonb;
  v_possible_duplicate_ids bigint[];
  v_skip_matching boolean:=false;
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
    IF (v_data->>'source' ~ '(^|_)email$') AND v_amount>0 THEN
      v_ids:=public.bank_sync_email_duplicate_candidates_internal(v_connection.id,v_data,false);
      IF cardinality(v_ids)=1 AND (SELECT t.ingest_source<>'banksync_email_confirmed' AND public.bank_sync_email_transaction_matches(t,v_data)
        FROM eshop.transactions t WHERE id=v_ids[1]) THEN
        v_resolution:=public.bank_sync_email_duplicate_resolution_internal(v_ids[1],auth.uid())
          ||jsonb_build_object('actor_kind','service','facts',v_data);
      ELSIF cardinality(v_ids)>0 THEN
        v_possible_duplicate_ids:=v_ids;
      END IF;
    END IF;
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
    -- A manually verified email is already a credit. Adopt its first proven
    -- movement identity without pairing again or emitting another paid event.
    IF v_outcome IS NULL AND v_tx.id IS NULL AND v_amount>0 THEN
      v_ids:=public.bank_sync_email_duplicate_candidates_internal(v_connection.id,v_data,true);
      IF cardinality(v_ids)>0 THEN
        IF cardinality(v_ids)=1 AND (SELECT public.bank_sync_email_transaction_matches(t,v_data)
          FROM eshop.transactions t WHERE id=v_ids[1]) THEN
          SELECT * INTO v_tx FROM eshop.transactions WHERE id=v_ids[1] FOR UPDATE;
          v_outcome:='already_ingested';
        ELSE v_skip_matching:=true; v_possible_duplicate_ids:=v_ids; END IF;
      END IF;
    END IF;
    IF v_outcome IS NULL AND v_tx.id IS NOT NULL THEN
      IF NOT (CASE WHEN v_tx.ingest_source='banksync_email_confirmed'
        THEN public.bank_sync_email_transaction_matches(v_tx,v_data)
        ELSE public.bank_sync_existing_facts_match(v_tx,v_data) END) THEN
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
      ELSIF v_skip_matching THEN v_outcome:='unmatched';
      ELSE
        v_match:=public.payment_provider_call_internal('bank','observe_payment',jsonb_build_object('transactionId',v_tx.id));
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
  IF v_tx.id IS NOT NULL AND v_tx.amount<0 AND v_outcome IN ('stored_outgoing','already_ingested') THEN
    v_refund:=public.payment_provider_call_internal('bank','observe_refund',jsonb_build_object('transactionId',v_tx.id));
  END IF;
  v_receipt:=jsonb_build_object('ok',true,'receipt_version',1,'delivery_id',v_delivery,'outcome',v_outcome,'refund',v_refund);
  UPDATE eshop.bank_sync_inbox SET outcome=v_outcome,receipt=v_receipt,committed_at=now(),
    diagnostics=jsonb_build_object('transaction_id',v_tx.id,
      'possible_duplicate_transaction_ids',coalesce(to_jsonb(v_possible_duplicate_ids),'[]'),
      'reason',CASE WHEN v_skip_matching THEN 'stored_unpaired_possible_duplicate' END),
    resolution=v_resolution,resolved_at=CASE WHEN v_resolution IS NOT NULL THEN now() END
    WHERE instance_id=p_instance_id AND consumer_app_id=p_consumer_app_id AND delivery_id=v_delivery;
  UPDATE eshop.bank_sync_connections SET receiver_commit_at=now(),
    last_error=CASE WHEN v_outcome LIKE 'quarantined_%' THEN v_outcome ELSE last_error END WHERE id=v_connection.id;
  RETURN v_receipt;
END;
$$;
REVOKE ALL ON FUNCTION public.ingest_bank_sync_transaction(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ingest_bank_sync_transaction(text,text,text,jsonb) TO service_role;
