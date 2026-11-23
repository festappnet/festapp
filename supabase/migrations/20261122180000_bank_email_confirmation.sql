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
CREATE INDEX IF NOT EXISTS transactions_email_confirmed_review_idx
 ON eshop.transactions(bank_account_id,amount,date) WHERE ingest_source='banksync_email_confirmed';
CREATE INDEX IF NOT EXISTS transactions_bank_email_duplicate_idx
 ON eshop.transactions(bank_account_id,date)
 WHERE ingest_source IN ('banksync_email_confirmed','banksync_api','fio_api','legacy_api','legacy');
CREATE INDEX IF NOT EXISTS bank_sync_inbox_unresolved_queue_idx
 ON eshop.bank_sync_inbox(connection_id,received_at,delivery_id) WHERE resolution IS NULL;
CREATE INDEX IF NOT EXISTS bank_sync_inbox_email_observation_idx
 ON eshop.bank_sync_inbox(connection_id,remote_transaction_id,received_at,delivery_id)
 WHERE (payload->'data'->>'source') ~ '(^|_)email$';
CREATE INDEX IF NOT EXISTS bank_sync_inbox_api_review_idx
 ON eshop.bank_sync_inbox(((diagnostics->>'transaction_id')::bigint))
 WHERE diagnostics->>'reason'='stored_unpaired_possible_duplicate';

CREATE UNIQUE INDEX IF NOT EXISTS bank_sync_inbox_reviewed_email_receipt_uidx
 ON eshop.bank_sync_inbox(((resolution->>'existing_transaction_id')::bigint))
 WHERE resolution->>'action'='api_same_movement';

CREATE TABLE IF NOT EXISTS eshop.bank_sync_review_signing_key (
 singleton boolean PRIMARY KEY CHECK(singleton),
 secret bytea NOT NULL DEFAULT extensions.gen_random_bytes(32)
);
INSERT INTO eshop.bank_sync_review_signing_key(singleton) VALUES(true) ON CONFLICT DO NOTHING;
ALTER TABLE eshop.bank_sync_review_signing_key ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.bank_sync_review_signing_key FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS eshop.bank_sync_api_review_events (
 instance_id text NOT NULL,
 consumer_app_id text NOT NULL,
 delivery_id text NOT NULL,
 revision integer NOT NULL CHECK(revision>0),
 decision jsonb NOT NULL,
 PRIMARY KEY(instance_id,consumer_app_id,delivery_id,revision),
 FOREIGN KEY(instance_id,consumer_app_id,delivery_id)
   REFERENCES eshop.bank_sync_inbox(instance_id,consumer_app_id,delivery_id)
);
ALTER TABLE eshop.bank_sync_api_review_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.bank_sync_api_review_events FROM PUBLIC,anon,authenticated,service_role;

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
-- Compare possible email duplicates by bank-local date.
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

-- SOURCE: eshop_bank_sync/bank_sync_email_confirmation.sql
CREATE OR REPLACE FUNCTION public.bank_sync_counter_account_internal(p_account text,p_code text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 WITH parts AS (
  SELECT nullif(upper(regexp_replace(coalesce(p_account,''),'[[:space:]]','','g')),'') AS account,
    nullif(regexp_replace(coalesce(p_code,''),'[[:space:]]','','g'),'') AS code
 ), formatted AS (
  SELECT CASE WHEN code IS NULL OR account LIKE '%/%' OR account ~ '^[A-Z]{2}'
    THEN account ELSE account||'/'||code END AS account
  FROM parts
 )
 SELECT CASE WHEN account IS NOT NULL THEN coalesce(public.try_payment_reference_account_internal(account),account) END
 FROM formatted;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_counter_account_internal(text,text) FROM PUBLIC,anon,authenticated,service_role;

-- A match is a review hint. These fields can be identical for separate
-- transfers, and email can omit references or counter-account details.
CREATE OR REPLACE FUNCTION public.bank_sync_email_possible_duplicate_internal(p_tx eshop.transactions,p_data jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 WITH stored_signals AS MATERIALIZED (
   SELECT * FROM public.bank_transaction_signals_internal(p_tx.vs,p_tx.payer_reference,
     p_tx.message_for_recipient,p_tx.user_identification,p_tx.comment)
 ), incoming_signals AS MATERIALIZED (
   SELECT * FROM public.bank_transaction_signals_internal(p_data->>'raw_vs',p_data->>'payer_reference',
     p_data->>'message',p_data->>'user_identification',p_data->>'comment')
 ), accounts AS (
   SELECT public.bank_sync_counter_account_internal(p_tx.counter_account,p_tx.bank_code) AS stored,
     public.bank_sync_counter_account_internal(p_data->>'counter_account',p_data->>'bank_code') AS incoming
 )
 SELECT p_tx.amount IS NOT DISTINCT FROM (p_data->>'amount_cents')::numeric/100
  AND upper(trim(p_tx.currency)) IS NOT DISTINCT FROM upper(trim(p_data->>'currency'))
  AND public.bank_sync_fact_dates_match_internal(p_tx,p_data,1)
  AND (EXISTS(SELECT FROM stored_signals JOIN incoming_signals USING(kind,value))
    OR (NOT EXISTS(SELECT FROM stored_signals JOIN incoming_signals USING(kind))
      AND (stored=incoming OR stored IS NULL OR incoming IS NULL)))
 FROM accounts;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_possible_duplicate_internal(eshop.transactions,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- The connection lock held by the caller serializes both sides of ingestion.
CREATE OR REPLACE FUNCTION public.bank_sync_email_duplicate_candidates_internal(p_connection bigint,p_data jsonb,p_confirmed_only boolean)
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
   AND CASE WHEN p_confirmed_only THEN t.ingest_source='banksync_email_confirmed'
      AND NOT EXISTS(SELECT FROM eshop.bank_sync_inbox r
       WHERE r.resolution->>'action'='api_same_movement'
         AND (r.resolution->>'existing_transaction_id')::bigint=t.id)
     ELSE t.ingest_source IN ('banksync_email_confirmed','banksync_api','fio_api','legacy_api','legacy') END
 )
 SELECT coalesce(array_agg((fact).id::bigint ORDER BY (fact).id),'{}'::bigint[]) FROM prefiltered
 WHERE public.bank_sync_email_possible_duplicate_internal(fact,p_data);
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_duplicate_candidates_internal(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Compare across aliases internally. Project only the details the actor can
-- read on each ledger account. A single redacted hint keeps the review visible.
CREATE OR REPLACE FUNCTION public.bank_sync_email_possible_duplicates_view_internal(p_ids bigint[])
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH candidates AS MATERIALIZED (
   SELECT t.*,public.can_read_bank_transactions(t.bank_account_id) AS can_read
   FROM eshop.transactions t WHERE t.id=ANY(p_ids)
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object('transaction_id',t.id,'ingest_source',t.ingest_source,
  'transaction_paired',t.payment_info IS NOT NULL,
  'order_symbol',CASE WHEN o.occasion IS NOT NULL AND public.can_read_orders(o.occasion) THEN o.order_symbol END,
  'order_number',CASE WHEN o.occasion IS NOT NULL AND public.can_read_orders(o.occasion) THEN o.order_sequence END,
  'facts',jsonb_build_object('amount_cents',round(t.amount*100)::bigint,'currency',trim(t.currency),
    'date',t.date AT TIME ZONE 'UTC','raw_vs',nullif(trim(t.vs),''),'counter_account',t.counter_account,
    'bank_code',t.bank_code,'payer_reference',t.payer_reference)) ORDER BY t.id),'[]'::jsonb)
  || CASE WHEN EXISTS(SELECT FROM candidates WHERE NOT can_read)
    THEN '[{"restricted":true}]'::jsonb ELSE '[]'::jsonb END
 FROM candidates t LEFT JOIN eshop.orders o ON o.payment_info=t.payment_info WHERE t.can_read;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_possible_duplicates_view_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- Bind decisions to the current candidates without exposing restricted IDs.
CREATE OR REPLACE FUNCTION public.bank_sync_review_token_internal(p_inbox eshop.bank_sync_inbox,p_ids bigint[])
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT encode(extensions.hmac(convert_to(jsonb_build_array(auth.uid(),p_inbox.connection_id,
   p_inbox.delivery_id,p_inbox.body_sha256,p_inbox.resolution,p_ids,
   (SELECT jsonb_agg(jsonb_build_array(t.id,t.payment_info) ORDER BY t.id)
    FROM eshop.transactions t WHERE t.id=ANY(p_ids)))::text,'UTF8'),secret,'sha256'),'hex')
 FROM eshop.bank_sync_review_signing_key WHERE singleton;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_review_token_internal(eshop.bank_sync_inbox,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- A BankSync observation can have more than one transport delivery.
CREATE OR REPLACE FUNCTION public.bank_sync_email_source_row_internal(p_connection bigint,p_remote_id text)
RETURNS eshop.bank_sync_inbox LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT i FROM eshop.bank_sync_inbox i
 WHERE i.connection_id=p_connection AND i.remote_transaction_id=p_remote_id
  AND i.payload->'data'->>'source' ~ '(^|_)email$'
  AND i.outcome IN ('quarantined_identity','quarantined_conflict')
  AND (i.payload->'data'->>'amount_cents')::numeric>0
 ORDER BY (i.resolution IS NULL),i.received_at,i.delivery_id LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_source_row_internal(bigint,text) FROM PUBLIC,anon,authenticated,service_role;

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
-- Paid/sent deposit orders remain eligible while a balance is outstanding.
CREATE OR REPLACE FUNCTION public.bank_sync_email_payable_targets_for_ids_internal(p_account bigint,p_currency text,p_ids bigint[])
RETURNS TABLE(payment_info_id bigint,order_id bigint,occasion_id bigint,candidate jsonb)
LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH eligible AS MATERIALIZED (
  SELECT pi.id,pi.amount,pi.currency_code,o.id AS order_id,o.occasion,o.order_symbol,o.order_sequence,o.state,o.data
  FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id JOIN public.occasions oc ON oc.id=o.occasion
  WHERE pi.id=ANY(p_ids) AND pi.bank_account=p_account AND pi.payment_method='bank'
   AND upper(trim(pi.currency_code))=upper(trim(p_currency)) AND pi.amount>0
   AND (o.state IN ('created','ordered','expired')
     OR (o.state IN ('paid','sent') AND pi.deposit_amount>0))
   AND NOT public.is_demo_occasion(o.occasion) AND NOT public.is_demo_bank_account(p_account)
   AND public.can_write_orders(o.occasion)
   AND EXISTS(SELECT FROM eshop.unit_bank_accounts a WHERE a.unit=oc.unit AND a.bank_account=p_account)
 ), totals AS MATERIALIZED (
  SELECT * FROM public.payment_financial_totals_bulk_internal((SELECT coalesce(array_agg(id::bigint),'{}'::bigint[]) FROM eligible))
 )
 SELECT e.id::bigint,e.order_id::bigint,e.occasion::bigint,jsonb_build_object(
  'payment_info_id',e.id,'order_id',e.order_id,'order_symbol',e.order_symbol,'order_number',e.order_sequence,
  'state',e.state,'customer_name',concat_ws(' ',coalesce(e.data->>'name',e.data->>'first_name'),coalesce(e.data->>'surname',e.data->>'last_name')),
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
   'possible_duplicates',public.bank_sync_email_possible_duplicates_view_internal(d.ids),
   'duplicate_review_token',CASE WHEN cardinality(d.ids)>0 THEN public.bank_sync_review_token_internal(i,d.ids) END,
   'candidates',public.bank_sync_email_candidates_internal(p_bank_account_id,i.payload->'data')) AS item
  FROM eshop.bank_sync_inbox i
  CROSS JOIN LATERAL (SELECT public.bank_sync_email_duplicate_candidates_internal(
    v_connection.id,i.payload->'data',false) AS ids) d
  WHERE i.connection_id=v_connection.id
   AND (i.payload->'data'->>'source' ~ '(^|_)email$')
   AND i.outcome IN ('quarantined_identity','quarantined_conflict') AND i.resolution IS NULL
   AND (i.payload->'data'->>'amount_cents')::numeric>0
   AND i.delivery_id=(public.bank_sync_email_source_row_internal(i.connection_id,i.remote_transaction_id)).delivery_id
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
 p_expected_body_sha256 text,p_checked_internet_banking boolean,p_not_duplicate boolean DEFAULT false,
 p_duplicate_review_token text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE
 v_connection eshop.bank_sync_connections; v_inbox eshop.bank_sync_inbox; v_payment eshop.payment_info;
 v_source eshop.bank_sync_inbox; v_review_token text;
 v_data jsonb; v_transaction_id bigint; v_result jsonb; v_organization bigint; v_unit bigint; v_occasion bigint; v_order bigint; v_ids bigint[];
BEGIN
 v_connection:=public.bank_sync_email_authorized_connection_internal(p_bank_account_id);
 -- Order authorization also precedes inbox access, digest tests and replay.
 SELECT oc.organization,oc.unit,oc.id,o.id INTO v_organization,v_unit,v_occasion,v_order FROM eshop.orders o
 JOIN public.occasions oc ON oc.id=o.occasion WHERE o.payment_info=p_payment_info_id;
 IF v_occasion IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 PERFORM public.check_is_editor_order_on_occasion(v_occasion);
 IF NOT EXISTS(SELECT FROM eshop.payment_info WHERE id=p_payment_info_id AND bank_account=p_bank_account_id) THEN
  RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH';
 END IF;
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
 v_source:=public.bank_sync_email_source_row_internal(v_inbox.connection_id,v_inbox.remote_transaction_id);
 IF v_source.delivery_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_NOT_CONFIRMABLE'; END IF;
 IF v_source.payload->'data' IS DISTINCT FROM v_inbox.payload->'data' THEN
  RAISE EXCEPTION 'BANK_SYNC_OBSERVATION_CONFLICT';
 END IF;
 v_inbox:=v_source;
 IF v_inbox.resolution IS NOT NULL THEN
  IF v_inbox.resolution->>'action'='confirmed' AND (v_inbox.resolution->>'payment_info_id')::bigint=p_payment_info_id THEN
   RETURN (v_inbox.resolution-'possible_duplicate_transaction_ids')||jsonb_build_object('transaction_paired',coalesce((SELECT t.payment_info IS NOT NULL
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
 IF cardinality(v_ids)>0 OR p_not_duplicate IS TRUE THEN
  PERFORM 1 FROM eshop.transactions WHERE id=ANY(v_ids) ORDER BY id FOR UPDATE;
  v_review_token:=public.bank_sync_review_token_internal(v_inbox,v_ids);
  IF p_not_duplicate IS DISTINCT FROM true OR p_duplicate_review_token IS DISTINCT FROM v_review_token THEN
   RETURN jsonb_build_object('action','possible_duplicate','transaction_paired',false,
     'duplicate_review_token',v_review_token,
     'possible_duplicates',public.bank_sync_email_possible_duplicates_view_internal(v_ids));
  END IF;
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
 RETURN v_result-'possible_duplicate_transaction_ids';
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_bank_sync_email_observation(bigint,text,bigint,text,boolean,boolean,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.confirm_bank_sync_email_observation(bigint,text,bigint,text,boolean,boolean,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.dismiss_bank_sync_email_observation(p_bank_account_id bigint,p_delivery_id text,p_expected_body_sha256 text,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_connection eshop.bank_sync_connections; v_inbox eshop.bank_sync_inbox; v_source eshop.bank_sync_inbox; v_result jsonb;
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
 -- Dismiss the same source observation for all of its transport deliveries.
 v_source:=public.bank_sync_email_source_row_internal(v_inbox.connection_id,v_inbox.remote_transaction_id);
 IF v_source.delivery_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_NOT_CONFIRMABLE'; END IF;
 IF v_source.payload->'data' IS DISTINCT FROM v_inbox.payload->'data' THEN
  RAISE EXCEPTION 'BANK_SYNC_OBSERVATION_CONFLICT';
 END IF;
 v_inbox:=v_source;
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
    WHERE t.id=p_transaction_id AND t.ingest_source='banksync_api' AND c.legacy_blocked_at IS NOT NULL
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

-- SOURCE: eshop_bank_sync/bank_sync_api_review.sql
-- A reviewed API movement retains its own ledger row and bank identity.
CREATE OR REPLACE FUNCTION public.bank_sync_api_review_row_internal(p_transaction bigint)
RETURNS eshop.bank_sync_inbox LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT i FROM eshop.bank_sync_inbox i
 WHERE i.diagnostics->>'reason'='stored_unpaired_possible_duplicate'
  AND (i.diagnostics->>'transaction_id')::bigint=p_transaction
 ORDER BY i.received_at,i.delivery_id LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_api_review_row_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_recovery_account_internal(p_account bigint,p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT public.can_manage_bank_account(p_account)
  AND EXISTS(SELECT FROM eshop.unit_bank_accounts l WHERE l.unit=p_unit AND l.bank_account=p_account)
  AND EXISTS(SELECT FROM eshop.bank_sync_connections c
   WHERE c.legacy_blocked_at IS NOT NULL AND public.can_manage_bank_account(c.bank_account_id)
    AND (c.bank_account_id=p_account OR EXISTS(SELECT FROM eshop.bank_sync_account_aliases a
     WHERE a.connection_id=c.id AND a.bank_account_id=p_account)));
$$;
REVOKE ALL ON FUNCTION public.bank_sync_recovery_account_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_recovery_receipt_internal(p_tx eshop.transactions)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT p_tx.ingest_source='banksync_email_confirmed' OR
  (p_tx.ingest_source='banksync_api' AND (public.bank_sync_api_review_row_internal(p_tx.id)).delivery_id IS NOT NULL);
$$;
REVOKE ALL ON FUNCTION public.bank_sync_recovery_receipt_internal(eshop.transactions) FROM PUBLIC,anon,authenticated,service_role;

-- The same candidate set serves repair availability and the actual picker.
CREATE OR REPLACE FUNCTION public.bank_sync_pairing_candidates_internal(p_account bigint,p_recovery_only boolean)
RETURNS TABLE(movement eshop.transactions,review eshop.bank_sync_inbox)
LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT t,r FROM eshop.transactions t
 LEFT JOIN LATERAL public.bank_sync_api_review_row_internal(
   CASE WHEN t.ingest_source='banksync_api' THEN t.id END) r ON true
 WHERE t.bank_account_id IN (
  SELECT p_account
  UNION SELECT c.bank_account_id FROM eshop.bank_sync_connections c
  JOIN eshop.bank_sync_account_aliases a ON a.connection_id=c.id
  WHERE a.bank_account_id=p_account AND public.can_manage_bank_account(c.bank_account_id)
 )
 AND (t.bank_account_id=p_account OR public.bank_sync_accounts_match(t.id,p_account))
 AND (NOT p_recovery_only OR t.ingest_source='banksync_email_confirmed' OR r.delivery_id IS NOT NULL)
 AND t.payment_info IS NULL AND t.amount>0
 AND NOT EXISTS(SELECT FROM eshop.refund_settlements s WHERE s.transaction_id=t.id);
$$;
REVOKE ALL ON FUNCTION public.bank_sync_pairing_candidates_internal(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_api_review_candidates_internal(p_inbox eshop.bank_sync_inbox)
RETURNS bigint[] LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]) FROM (
  SELECT unnest(public.bank_sync_email_duplicate_candidates_internal(
    p_inbox.connection_id,p_inbox.payload->'data',true)) AS id
  -- The current counterpart is unavailable to other API movements. It remains
  -- selectable when reconsidering this movement's decision.
  UNION SELECT (p_inbox.resolution->>'existing_transaction_id')::bigint
   WHERE p_inbox.resolution->>'action'='api_same_movement'
 ) candidates WHERE id IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_api_review_candidates_internal(eshop.bank_sync_inbox) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_api_review_view_internal(p_inbox eshop.bank_sync_inbox)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('review_token',public.bank_sync_review_token_internal(p_inbox,candidate_ids),
  'previous_action',p_inbox.resolution->>'action',
  'possible_duplicates',public.bank_sync_email_possible_duplicates_view_internal(candidate_ids))
 FROM (SELECT public.bank_sync_api_review_candidates_internal(p_inbox) AS candidate_ids) c;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_api_review_view_internal(eshop.bank_sync_inbox) FROM PUBLIC,anon,authenticated,service_role;

-- Review an unpaired API movement. Keep the financial credit on its verified
-- counterpart for a same-movement decision and use the API row for a separate
-- payment. Corrections use the same command and append to the decision history.
CREATE OR REPLACE FUNCTION public.resolve_bank_sync_api_duplicate_v1(
 p_transaction_id bigint,p_payment_info_id bigint,p_review_token text,p_existing_transaction_id bigint DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_tx eshop.transactions; v_inbox eshop.bank_sync_inbox; v_target record;
 v_ids bigint[]; v_review jsonb; v_result jsonb; v_counterpart eshop.transactions;
 v_paired_now boolean:=false; v_revision integer;
 v_request_hash text:=encode(extensions.digest(p_review_token,'sha256'),'hex');
BEGIN
 SELECT pi.bank_account,pi.currency_code,oc.id AS occasion_id,oc.organization,oc.unit INTO v_target
 FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id
 JOIN public.occasions oc ON oc.id=o.occasion
 WHERE pi.id=p_payment_info_id AND pi.payment_method='bank';
 IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 PERFORM public.check_is_admin_for_bank_account(v_target.bank_account);
 PERFORM public.check_is_editor_order_on_occasion(v_target.occasion_id);
 IF NOT public.bank_sync_recovery_account_internal(v_target.bank_account,v_target.unit)
 THEN RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 PERFORM public.payment_policy_fence_internal(v_target.organization);

 SELECT * INTO v_tx FROM eshop.transactions WHERE id=p_transaction_id;
 PERFORM public.check_is_admin_for_bank_account(v_tx.bank_account_id);
 v_inbox:=public.bank_sync_api_review_row_internal(v_tx.id);
 IF v_inbox.delivery_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_REVIEW_NOT_FOUND'; END IF;
 -- Match ingest's connection-before-transaction lock order.
 PERFORM 1 FROM eshop.bank_sync_connections WHERE id=v_inbox.connection_id FOR UPDATE;
 SELECT * INTO v_tx FROM eshop.transactions WHERE id=p_transaction_id FOR UPDATE;
 PERFORM public.check_is_admin_for_bank_account(v_tx.bank_account_id);
 IF v_tx.ingest_source IS DISTINCT FROM 'banksync_api'
  OR upper(trim(v_tx.currency)) IS DISTINCT FROM upper(trim(v_target.currency_code))
  OR (v_tx.bank_account_id<>v_target.bank_account AND NOT public.bank_sync_accounts_match(v_tx.id,v_target.bank_account))
 THEN RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 v_inbox:=public.bank_sync_api_review_row_internal(v_tx.id);
 IF v_inbox.delivery_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_REVIEW_NOT_FOUND'; END IF;
 -- A transport retry reuses the recorded outcome. A deliberate correction
 -- supplies the current review token, which includes the last decision.
 IF v_inbox.resolution->>'review_request_sha256'=v_request_hash
  AND v_inbox.resolution->>'actor_id'=auth.uid()::text
  AND (v_inbox.resolution->>'payment_info_id')::bigint=p_payment_info_id
  AND (v_inbox.resolution->>'existing_transaction_id')::bigint IS NOT DISTINCT FROM p_existing_transaction_id THEN
  RETURN jsonb_build_object('action',v_inbox.resolution->>'action',
    'paired_now',coalesce((v_inbox.resolution->>'paired_now')::boolean,false));
 END IF;
 IF v_tx.payment_info IS NOT NULL THEN RAISE EXCEPTION 'BANK_SYNC_ALREADY_RESOLVED'; END IF;

 v_ids:=public.bank_sync_api_review_candidates_internal(v_inbox);
 PERFORM 1 FROM eshop.transactions WHERE id=ANY(v_ids) ORDER BY id FOR UPDATE;
 IF p_review_token IS NULL OR p_review_token IS DISTINCT FROM public.bank_sync_review_token_internal(v_inbox,v_ids) THEN
  v_review:=public.bank_sync_api_review_view_internal(v_inbox);
  RETURN v_review||jsonb_build_object('action','review_changed');
 END IF;
 IF p_existing_transaction_id IS NOT NULL THEN
  SELECT * INTO v_counterpart FROM eshop.transactions t
  WHERE t.id=p_existing_transaction_id AND t.id=ANY(v_ids)
   AND t.ingest_source='banksync_email_confirmed' AND public.can_read_bank_transactions(t.bank_account_id);
  IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_REVIEW_CANDIDATE_INVALID'; END IF;
  IF v_counterpart.payment_info IS NULL THEN
   PERFORM public.add_transaction_to_payment_info_ws(v_counterpart.id,p_payment_info_id);
   v_paired_now:=true;
  END IF;
 ELSE
  v_paired_now:=true;
 END IF;

 v_revision:=coalesce((v_inbox.resolution->>'revision')::integer,0)+1;
 v_result:=jsonb_build_object(
   'action',CASE WHEN p_existing_transaction_id IS NULL THEN 'api_distinct' ELSE 'api_same_movement' END,
   'actor_id',auth.uid(),'resolved_at',now(),'payment_info_id',p_payment_info_id,
   'existing_transaction_id',p_existing_transaction_id,'reviewed_transaction_ids',to_jsonb(v_ids),
   'revision',v_revision,'review_request_sha256',v_request_hash,'paired_now',v_paired_now);
 INSERT INTO eshop.bank_sync_api_review_events(instance_id,consumer_app_id,delivery_id,revision,decision)
 VALUES(v_inbox.instance_id,v_inbox.consumer_app_id,v_inbox.delivery_id,v_revision,v_result);
 UPDATE eshop.bank_sync_inbox SET resolution=v_result,resolved_at=now()
 WHERE instance_id=v_inbox.instance_id AND consumer_app_id=v_inbox.consumer_app_id AND delivery_id=v_inbox.delivery_id;
 IF p_existing_transaction_id IS NULL THEN
  PERFORM public.add_transaction_to_payment_info_ws(p_transaction_id,p_payment_info_id);
 END IF;
 RETURN jsonb_build_object('action',v_result->>'action','paired_now',v_paired_now);
END;
$$;
REVOKE ALL ON FUNCTION public.resolve_bank_sync_api_duplicate_v1(bigint,bigint,text,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_bank_sync_api_duplicate_v1(bigint,bigint,text,bigint) TO authenticated;

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
      v_possible_duplicate_ids:=public.bank_sync_email_duplicate_candidates_internal(v_connection.id,v_data,false);
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
    -- Keep each proven API movement and its own identity. If a manually
    -- confirmed email might describe it, leave the new credit for review.
    IF v_outcome IS NULL AND v_tx.id IS NULL AND v_amount>0 THEN
      v_possible_duplicate_ids:=public.bank_sync_email_duplicate_candidates_internal(v_connection.id,v_data,true);
      v_skip_matching:=cardinality(v_possible_duplicate_ids)>0;
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
      'reason',CASE WHEN v_skip_matching THEN 'stored_unpaired_possible_duplicate' END)
    WHERE instance_id=p_instance_id AND consumer_app_id=p_consumer_app_id AND delivery_id=v_delivery;
  UPDATE eshop.bank_sync_connections SET receiver_commit_at=now(),
    last_error=CASE WHEN v_outcome LIKE 'quarantined_%' THEN v_outcome ELSE last_error END WHERE id=v_connection.id;
  RETURN v_receipt;
END;
$$;
REVOKE ALL ON FUNCTION public.ingest_bank_sync_transaction(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ingest_bank_sync_transaction(text,text,text,jsonb) TO service_role;

-- SOURCE: eshop_transactions/add_transaction_to_payment_info_ws.sql
CREATE OR REPLACE FUNCTION public.add_transaction_to_payment_info_ws(
    p_transaction_id bigint,
    p_payment_info_id bigint
)
RETURNS jsonb SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    bank_acc bigint;
    occasion_id bigint;
    v_transaction eshop.transactions;
BEGIN
    -- Retrieve the associated order_id from payment_info
    SELECT pi.bank_account INTO bank_acc
    FROM eshop.payment_info pi
    WHERE pi.id = p_payment_info_id
    LIMIT 1;

    IF NOT public.can_manage_bank_account(bank_acc) THEN
    RAISE insufficient_privilege USING MESSAGE='Bank transaction write access denied'; END IF;

    SELECT * INTO v_transaction FROM eshop.transactions WHERE id=p_transaction_id;
    IF NOT public.can_manage_bank_account(v_transaction.bank_account_id) THEN
      RAISE insufficient_privilege USING MESSAGE='Source bank transaction write access denied'; END IF;

    SELECT o.occasion
    INTO occasion_id
    FROM eshop.orders o
    WHERE o.payment_info = p_payment_info_id
    LIMIT 1;

    PERFORM public.check_is_editor_order_on_occasion(occasion_id);
  PERFORM public.payment_policy_fence_internal(oc.organization) FROM public.occasions oc WHERE oc.id=occasion_id;
  -- Stabilize the existing receipt before applying the recovery policy.
  SELECT * INTO v_transaction FROM eshop.transactions WHERE id=p_transaction_id FOR UPDATE;
  IF NOT public.can_manage_bank_account(v_transaction.bank_account_id) THEN
    RAISE insufficient_privilege USING MESSAGE='Source bank transaction write access denied';
  END IF;
  -- Recovery after closing bank sales applies only to an existing verified
  -- receipt and bank instructions already issued on a linked account.
  IF NOT coalesce((SELECT public.payment_method_policy_enabled_internal(oc.unit,'bank')
      FROM public.occasions oc WHERE oc.id=occasion_id),false) THEN
    IF NOT EXISTS(
      SELECT FROM eshop.payment_info pi
      JOIN public.occasions oc ON oc.id=occasion_id
      JOIN eshop.unit_bank_accounts link ON link.unit=oc.unit AND link.bank_account=pi.bank_account
      WHERE pi.id=p_payment_info_id AND pi.payment_method='bank'
       AND public.bank_sync_recovery_receipt_internal(v_transaction)
    ) THEN RAISE EXCEPTION 'PAYMENT_METHOD_POLICY_DISABLED'; END IF;
  END IF;

    PERFORM public.apply_transaction_pairing(
      p_transaction_id, p_payment_info_id, 'manual_attach', 'user'
    );

    -- Return success message
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Transaction added successfully.'
    );

END;
$$ LANGUAGE plpgsql;

REVOKE ALL ON FUNCTION public.add_transaction_to_payment_info_ws(bigint,bigint)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.add_transaction_to_payment_info_ws(bigint,bigint)
  TO authenticated;

-- SOURCE: eshop_transactions/remove_transaction_from_payment_info_ws.sql
CREATE OR REPLACE FUNCTION public.remove_transaction_from_payment_info_ws(
  p_transaction_id bigint,
  p_payment_info_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_bank_account_id bigint;
  v_occasion_id bigint;
  v_transaction eshop.transactions;
BEGIN
  SELECT pi.bank_account, o.occasion INTO v_bank_account_id, v_occasion_id
  FROM eshop.payment_info pi
  JOIN eshop.orders o ON o.payment_info = pi.id
  WHERE pi.id = p_payment_info_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PAYMENT_INFO_NOT_FOUND'; END IF;
  IF NOT public.can_manage_bank_account(v_bank_account_id) THEN
    RAISE insufficient_privilege USING MESSAGE='Bank transaction write access denied'; END IF;
  IF NOT public.can_manage_bank_account((SELECT bank_account_id FROM eshop.transactions WHERE id=p_transaction_id)) THEN
    RAISE insufficient_privilege USING MESSAGE='Source bank transaction write access denied'; END IF;
  PERFORM public.check_is_editor_order_on_occasion(v_occasion_id);
  PERFORM public.payment_policy_fence_internal(oc.organization) FROM public.occasions oc WHERE oc.id=v_occasion_id;
  SELECT * INTO v_transaction FROM eshop.transactions WHERE id=p_transaction_id FOR UPDATE;
  IF v_transaction.payment_info IS DISTINCT FROM p_payment_info_id THEN
    RAISE EXCEPTION 'TRANSACTION_PAIRING_MISMATCH';
  END IF;
  -- Closing bank sales still allows correcting a previously verified receipt.
  IF NOT coalesce((SELECT public.payment_method_policy_enabled_internal(oc.unit,'bank')
      FROM public.occasions oc WHERE oc.id=v_occasion_id),false)
    AND NOT coalesce(public.bank_sync_recovery_receipt_internal(v_transaction),false) THEN
    RAISE EXCEPTION 'PAYMENT_METHOD_POLICY_DISABLED';
  END IF;
  PERFORM public.apply_transaction_pairing(
    p_transaction_id, NULL, 'manual_unlink', 'user'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.remove_transaction_from_payment_info_ws(bigint,bigint)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.remove_transaction_from_payment_info_ws(bigint,bigint)
  TO authenticated;

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
  v_order_ids bigint[];
  v_order_bindings jsonb;
  v_locked_order_bindings jsonb;
  v_api_review eshop.bank_sync_inbox;
BEGIN
  PERFORM public.check_bank_account_writable((SELECT bank_account_id FROM eshop.transactions WHERE id=p_transaction_id));
  PERFORM public.check_bank_account_writable((SELECT bank_account FROM eshop.payment_info WHERE id=p_payment_info_id));
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

  IF p_payment_info_id IS NOT NULL AND v_transaction.ingest_source='banksync_api' THEN
    v_api_review:=public.bank_sync_api_review_row_internal(p_transaction_id);
    IF v_api_review.delivery_id IS NOT NULL AND
      v_api_review.resolution->>'action' IS DISTINCT FROM 'api_distinct' THEN
      RAISE EXCEPTION 'BANK_SYNC_API_DUPLICATE_REVIEW_REQUIRED';
    END IF;
  END IF;

  -- The transaction row stabilizes the old target (also held by ingest/matcher).
  -- Acquire every stored old/new form and order before either payment row,
  -- matching product edit and cancellation. Never trust a caller's scope list.
  SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]),
    coalesce(jsonb_agg(jsonb_build_array(id,form,payment_info) ORDER BY id),'[]'::jsonb)
  INTO v_order_ids,v_order_bindings
  FROM eshop.orders WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id);
  PERFORM public.lock_order_capacity_scope_internal(v_order_ids);
  SELECT coalesce(jsonb_agg(jsonb_build_array(id,form,payment_info) ORDER BY id),'[]'::jsonb)
  INTO v_locked_order_bindings
  FROM eshop.orders WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id);
  IF v_order_bindings IS DISTINCT FROM v_locked_order_bindings THEN
    RAISE EXCEPTION 'PAIRING_ORDER_SCOPE_CHANGED' USING ERRCODE='40001';
  END IF;
  PERFORM 1 FROM eshop.payment_info WHERE id IN (v_old_payment_info_id,p_payment_info_id)
  ORDER BY id FOR UPDATE;

  -- A settled movement is immutable through the generic attach/unlink API.
  -- Cash voids and evidenced bank reclassification have their explicit owner.
  IF EXISTS(SELECT 1 FROM eshop.refund_settlements WHERE transaction_id=p_transaction_id)
     AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    RAISE EXCEPTION 'REFUND_SETTLEMENT_REQUIRES_EXPLICIT_CORRECTION';
  END IF;
  IF p_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id AND v_transaction.amount<0
     AND NOT EXISTS(SELECT 1 FROM eshop.bank_accounts b WHERE b.id=v_transaction.bank_account_id
       AND upper(b.type)='CASH' AND v_transaction.transaction_type='manual'
       AND v_transaction.ingest_source='manual') THEN
    RAISE EXCEPTION 'OUTGOING_REQUIRES_REFUND_CLASSIFICATION';
  END IF;
  IF v_old_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    PERFORM public.assert_payment_refund_reservations_internal(v_old_payment_info_id,greatest(v_transaction.amount,0));
  END IF;
  IF p_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id AND v_transaction.amount<0 THEN
    PERFORM public.assert_payment_refund_reservations_internal(p_payment_info_id,-v_transaction.amount);
  END IF;

  IF p_actor_kind='user' THEN
    -- The manual bank commands mutate the current and requested bindings.
    -- Authorize the stored orders and their payment accounts under their locks.
    IF v_old_payment_info_id IS NOT NULL AND p_method IN ('manual_attach','manual_unlink') THEN
      PERFORM public.check_is_admin_for_bank_account(pi.bank_account)
      FROM eshop.payment_info pi WHERE pi.id IN (v_old_payment_info_id,p_payment_info_id);
      PERFORM public.check_is_editor_order_on_occasion(o.occasion)
      FROM eshop.orders o WHERE o.payment_info IN (v_old_payment_info_id,p_payment_info_id);
    END IF;
    FOR v_order_id IN SELECT id FROM eshop.orders
      WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id) ORDER BY id LOOP
      PERFORM public.check_order_is_mutable(v_order_id);
    END LOOP;
  END IF;

  IF v_old_payment_info_id IS NOT DISTINCT FROM p_payment_info_id THEN
    RETURN jsonb_build_object('status', 'unchanged', 'transaction_id', p_transaction_id,
      'payment_info_id', p_payment_info_id);
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    SELECT * INTO v_target FROM eshop.payment_info WHERE id = p_payment_info_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_PAYMENT_INFO_NOT_FOUND'; END IF;
    IF public.payment_method_is_online_internal(v_target.payment_method) THEN RAISE EXCEPTION 'STRIPE_BANK_PAIRING_UNSUPPORTED'; END IF;
    IF v_target.payment_method='cash' AND NOT EXISTS(SELECT 1 FROM eshop.bank_accounts b
      WHERE b.id=v_transaction.bank_account_id AND b.type='CASH' AND v_transaction.transaction_type='manual') THEN
      RAISE EXCEPTION 'CASH_BANK_PAIRING_UNSUPPORTED'; END IF;
    IF v_transaction.transaction_type='manual' THEN
      IF NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link JOIN public.occasions oc ON oc.unit=link.unit
        JOIN eshop.orders o ON o.occasion=oc.id JOIN eshop.bank_accounts b ON b.id=link.bank_account
        WHERE o.payment_info=v_target.id AND b.id=v_transaction.bank_account_id ) THEN
        RAISE EXCEPTION 'CASH_ORDER_SCOPE_MISMATCH'; END IF;
    END IF;
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
    PERFORM public.refresh_payment_info_totals_internal(v_old_payment_info_id);
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = v_old_payment_info_id;
    IF v_order_id IS NOT NULL THEN PERFORM public.recalculate_order_payment_status(v_order_id); END IF;
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    PERFORM public.refresh_payment_info_totals_internal(p_payment_info_id);
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = p_payment_info_id;
    IF v_order_id IS NOT NULL THEN
      PERFORM public.recalculate_order_payment_status(v_order_id);
      IF v_transaction.amount>0 AND v_transaction.transaction_type IS DISTINCT FROM 'manual'
        AND v_transaction.ingest_source IS DISTINCT FROM 'manual' THEN
        PERFORM public.publish_form_measurement_event_internal('order_fully_paid',v_order_id);
      END IF;
    END IF;
  END IF;


  IF v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    PERFORM public.notification_center_prepared_invalidate(e.id) FROM public.notification_center_events e
     JOIN eshop.orders o ON o.occasion=e.occasion AND o.id=(e.data->>'orderId')::bigint
     WHERE e.kind='order_payment_received' AND e.data->>'paymentFact'='transaction:'||p_transaction_id AND o.payment_info=v_old_payment_info_id;
    UPDATE public.notification_center_events e SET status='resolved' FROM eshop.orders o
     WHERE e.kind='order_payment_received' AND e.data->>'paymentFact'='transaction:'||p_transaction_id
      AND o.id=(e.data->>'orderId')::bigint AND o.occasion=e.occasion AND o.payment_info=v_old_payment_info_id;
    IF p_payment_info_id IS NOT NULL AND v_transaction.amount>0 THEN
      FOR v_order_id IN SELECT id FROM eshop.orders WHERE payment_info=p_payment_info_id LOOP
       PERFORM public.notification_center_payment_fact_internal(v_order_id,'transaction',p_transaction_id::text,
        v_transaction.amount,v_transaction.currency::text,coalesce(v_transaction.date,now()),
        EXISTS(SELECT 1 FROM eshop.transaction_pairing_events WHERE transaction_id=p_transaction_id AND new_payment_info_id IS NOT NULL));
      END LOOP;
    END IF;
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

-- SOURCE: eshop_transactions/get_transactions_for_order.sql
CREATE OR REPLACE FUNCTION public.get_transactions_for_order(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_occasion_id bigint; bank_allowed boolean; bank_configured boolean; payment_context jsonb; provider_rows jsonb:='[]'; provider_complete boolean:=true; method text; movement jsonb;
BEGIN

  SELECT occasion INTO v_occasion_id FROM eshop.orders WHERE id = order_id;
  IF NOT can_read_orders(v_occasion_id) THEN
    RAISE EXCEPTION 'User is not authorized to view transactions for this occasion.' USING ERRCODE = 'P0001';
  END IF;

  SELECT pi.payment_method='bank' AND public.payment_method_policy_enabled_internal(oc.unit,'bank'),
   EXISTS(SELECT 1 FROM eshop.unit_bank_accounts l JOIN eshop.bank_accounts b ON b.id=l.bank_account
    WHERE l.unit=oc.unit AND upper(b.type)<>'CASH')
  INTO bank_allowed,bank_configured
  FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=order_id;
  payment_context:=public.payment_method_context_internal(order_id);
  SELECT pi.payment_method INTO method FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=order_id;
  IF public.payment_method_is_online_internal(method) THEN
   BEGIN
    SELECT public.payment_provider_call_internal(method,'movements',jsonb_build_object('paymentId',o.payment_info)) INTO movement FROM eshop.orders o WHERE o.id=order_id;
    SELECT coalesce(jsonb_agg(jsonb_build_object('source','provider','sourceId',m->>'sourceId','provider',method,
     'date',m->'occurred_at','amount',CASE WHEN m->>'kind'='dispute' THEN NULL ELSE CASE WHEN m->>'kind'='refund' THEN -1 ELSE 1 END*(m->>'amount_minor')::numeric/100 END,
     'heldAmount',CASE WHEN m->>'kind'='dispute' THEN (m->>'amount_minor')::numeric/100 END,'status',m->>'status',
     'currency',m->>'currency','transaction_type',m->>'kind','isRefund',m->>'kind'='refund','voided',false)), '[]')
    INTO provider_rows FROM jsonb_array_elements(movement) m;
    provider_complete:=NOT EXISTS(SELECT 1 FROM jsonb_array_elements(movement) m WHERE nullif(m->>'sourceId','') IS NULL);
   EXCEPTION WHEN OTHERS THEN provider_complete:=false; END;
  ELSIF method NOT IN ('bank','cash') OR method IS NULL THEN provider_complete:=false;
  END IF;
  RETURN (
    SELECT jsonb_build_object(
      'order_state', o.state,'ledgerComplete',provider_complete,
      'paymentOperations',payment_context,
      'actions', jsonb_build_object(
        'canAddCash', EXISTS(SELECT 1 FROM jsonb_array_elements(payment_context->'methods') m WHERE m->>'id'='cash' AND m->'record'='true'::jsonb),
        'canConfigureBank', bank_allowed AND public.can_manage_unit_bank_accounts(oc.unit),
        'showBankSetup',bank_allowed AND NOT bank_configured AND public.can_manage_unit_bank_accounts(oc.unit),
        'showBankAccess',bank_allowed AND NOT public.can_manage_unit_bank_accounts(oc.unit),
        'bankState', CASE WHEN NOT bank_allowed THEN 'disabled' WHEN NOT public.can_read_unit_bank_accounts(oc.unit) THEN 'restricted'
          WHEN bank_configured THEN 'configured' ELSE 'absent' END,
        'pairingAccountId', CASE WHEN pi.payment_method='bank'
          AND public.can_manage_bank_account(pi.bank_account) AND public.can_write_orders(o.occasion)
          AND (
            (bank_allowed AND o.state IN ('created','ordered','paid','sent'))
            OR (o.state IN ('created','ordered','paid','sent','expired')
             AND public.bank_sync_recovery_account_internal(pi.bank_account,oc.unit)
             AND EXISTS(SELECT FROM public.bank_sync_pairing_candidates_internal(pi.bank_account,true) c
              WHERE upper(trim((c.movement).currency))=upper(trim(pi.currency_code)))
            )
          ) THEN pi.bank_account END,
        'unitId', oc.unit,
        'removableTransactionIds', (SELECT coalesce(jsonb_agg(t.id),'[]')
          FROM eshop.transactions t JOIN eshop.bank_accounts b ON b.id=t.bank_account_id
          WHERE t.payment_info=o.payment_info AND (o.state IN ('created','ordered','paid','sent')
            OR (o.state='expired' AND public.bank_sync_recovery_receipt_internal(t)))
          AND NOT public.payment_method_is_online_internal(pi.payment_method)
          AND NOT EXISTS(SELECT 1 FROM eshop.refund_settlements s WHERE s.transaction_id=t.id)
          AND NOT EXISTS(SELECT 1 FROM eshop.transaction_pairing_events e WHERE e.transaction_snapshot_id=t.id AND e.method='exact_cash_correction')
          AND CASE WHEN t.transaction_type='manual' THEN upper(b.type)='CASH'
            AND public.can_manage_unit_bank_accounts(oc.unit) AND EXISTS(
              SELECT 1 FROM eshop.unit_bank_accounts l WHERE l.unit=oc.unit AND l.bank_account=b.id)
            ELSE (bank_allowed OR public.bank_sync_recovery_receipt_internal(t))
            AND public.can_write_orders(o.occasion) AND public.can_manage_bank_account(b.id)
            AND public.can_manage_bank_account(pi.bank_account) END)
      ),
      'payment_info', (
        SELECT to_jsonb(pi)
        FROM eshop.payment_info pi
        WHERE pi.id = o.payment_info
      ),
      'transactions', COALESCE((
        SELECT jsonb_agg(
            to_jsonb(t) || jsonb_build_object('source',CASE WHEN t.ingest_source='manual' THEN 'cash' ELSE 'bank' END,'sourceId','transaction:'||t.id,'isRefund',m.is_refund,'voided',m.voided,'createdByName',
                trim(both from COALESCE(ui.name, '') || ' ' || COALESCE(ui.surname, ''))
            )
        )
        FROM eshop.transactions t
        JOIN LATERAL public.payment_transaction_movements_internal(o.payment_info) m ON m.transaction_id=t.id
        LEFT JOIN public.user_info ui ON t.created_by = ui.id
        WHERE t.payment_info = o.payment_info
      ), '[]'::jsonb)||provider_rows
    )
    FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
    LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info
    WHERE o.id = order_id
  );
END;
$$;

-- SOURCE: eshop_transactions/get_transactions_for_order_all_available.sql
CREATE OR REPLACE FUNCTION public.get_transactions_for_order_all_available(payment_info_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    bank_acc bigint;
    v_bank_sales boolean;
    v_unit bigint;
    v_recovery_only boolean;
BEGIN
    SELECT pi.bank_account,public.payment_method_policy_enabled_internal(oc.unit,'bank'),oc.unit,o.state='expired'
    INTO bank_acc,v_bank_sales,v_unit,v_recovery_only
    FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id
    JOIN public.occasions oc ON oc.id=o.occasion
    WHERE pi.id=payment_info_id AND pi.payment_method='bank' AND public.can_read_orders(oc.id);
    IF bank_acc IS NULL THEN RAISE insufficient_privilege USING MESSAGE='Bank payment account required'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=bank_acc AND public.can_read_orders(demo_bank.occasion)) THEN
        PERFORM public.check_is_admin_for_bank_account(bank_acc);
    END IF;
    v_recovery_only:=v_recovery_only OR NOT v_bank_sales;
    IF v_recovery_only AND NOT public.bank_sync_recovery_account_internal(bank_acc,v_unit)
    THEN RAISE insufficient_privilege; END IF;

    RETURN (
        SELECT jsonb_agg(to_jsonb(c.movement)||
          CASE WHEN (c.review).delivery_id IS NOT NULL
          THEN jsonb_build_object('bankSyncReview',public.bank_sync_api_review_view_internal(c.review))
          ELSE '{}'::jsonb END ORDER BY (c.movement).date DESC,(c.movement).id)
        FROM public.bank_sync_pairing_candidates_internal(bank_acc,v_recovery_only) c
    );
END;
$$;

-- Explicit account context. Order access never grants statement authority.
CREATE OR REPLACE FUNCTION public.get_bank_transaction_history(p_bank_account_id bigint,p_unit_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.can_read_bank_transactions(p_bank_account_id) OR NOT public.get_is_manager_on_unit(p_unit_id)
  OR NOT coalesce(public.payment_method_policy_enabled_internal(p_unit_id,'bank'),false)
  OR NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts WHERE unit=p_unit_id AND bank_account=p_bank_account_id) THEN
  RAISE insufficient_privilege USING MESSAGE='Bank history access denied'; END IF;
 RETURN (SELECT coalesce(jsonb_agg(to_jsonb(t)||
    CASE WHEN r.resolution IS NOT NULL THEN jsonb_build_object('bankSyncDecision',r.resolution->>'action')
    ELSE '{}'::jsonb END ORDER BY t.date DESC,t.id),'[]')
   FROM eshop.transactions t JOIN eshop.bank_accounts b ON b.id=t.bank_account_id
   LEFT JOIN LATERAL public.bank_sync_api_review_row_internal(
     CASE WHEN t.ingest_source='banksync_api' THEN t.id END) r ON true
   WHERE b.id=p_bank_account_id AND upper(b.type)<>'CASH');
END $$;
REVOKE ALL ON FUNCTION public.get_bank_transaction_history(bigint,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_transaction_history(bigint,bigint) TO authenticated;

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
    bank_sync jsonb,
    bank_sync_warning jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_unit_manager boolean; v_bank_sales boolean;
BEGIN
    v_bank_sales := coalesce(public.payment_method_policy_enabled_internal(p_unit_id,'bank'),false);
    v_unit_manager := public.can_manage_unit_bank_accounts(p_unit_id);
    IF NOT public.can_read_unit_bank_accounts(p_unit_id) THEN
      RAISE insufficient_privilege USING MESSAGE='User is not manager.';
    END IF;
    IF NOT v_bank_sales AND NOT EXISTS(
      SELECT FROM eshop.unit_bank_accounts l WHERE l.unit=p_unit_id
        AND public.bank_sync_recovery_account_internal(l.bank_account,p_unit_id)
    ) THEN RAISE insufficient_privilege USING MESSAGE='PAYMENT_METHOD_POLICY_DISABLED'; END IF;
    RETURN QUERY
    SELECT
        ba.id,
        ba.account_number,
        ba.title,
        ba.creditor_name,
        ba.type,
        coalesce(membership.is_admin,false) as is_admin,
        NULL::text as token_masked,
        NULL::timestamptz as token_expiry_date,
        ba.supported_currencies,
        ba.last_fio_fetch_time,
        CASE WHEN public.bank_account_write_rule(membership.is_admin,v_unit_manager,protected.bank_account IS NOT NULL)
          THEN public.get_bank_sync_connection(ba.id)
          ELSE (
            SELECT jsonb_build_object('state',connection.state,'mode',connection.mode)
            FROM eshop.bank_sync_connections connection
            WHERE connection.bank_account_id = ba.id
          ) END AS bank_sync,
        public.bank_sync_warning(ba.id) AS bank_sync_warning
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    -- Historical memberships need not be unique. Preserve any active admin
    -- grant while returning one row for each linked bank account.
    LEFT JOIN (
      SELECT grants.bank_account,bool_or(grants.is_admin) AS is_admin
      FROM eshop.bank_account_users grants WHERE grants."user"=auth.uid()
      GROUP BY grants.bank_account
    ) membership ON membership.bank_account=ba.id
    LEFT JOIN (SELECT DISTINCT bank_account FROM public.demo_occasions) protected ON protected.bank_account=ba.id
    WHERE uba.unit = p_unit_id
      AND (v_bank_sales OR public.bank_sync_recovery_account_internal(ba.id,p_unit_id))
    AND ba.type != 'CASH'
    -- The entry guard admits a manager or a listed demo reader. Managers are
    -- always outside demo units; demo readers retain the account-level fence.
    AND (v_unit_manager OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=ba.id AND public.can_read_orders(demo_bank.occasion)));
END;
$$;

REVOKE ALL ON FUNCTION public.get_bank_accounts_for_unit_management(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_bank_accounts_for_unit_management(bigint) TO authenticated, service_role;
