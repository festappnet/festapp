-- Stripe foundation only; new payments disabled. No production application authorized.

-- SOURCE: eshop_stripe/schema.sql
-- Additive foundation. No live activation, application triggers or bank-ledger aliases.
CREATE TABLE eshop.stripe_connections (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 organization_id bigint NOT NULL REFERENCES public.organizations(id),
 unit_id bigint NOT NULL REFERENCES public.units(id),
 account_id text NOT NULL CHECK(account_id ~ '^acct_[A-Za-z0-9]+$'),
 livemode boolean NOT NULL,
 state text NOT NULL CHECK(state IN ('candidate','connected','restricted','revoked','retired')),
 paused boolean NOT NULL DEFAULT true,
 business_name text, country text,
 charges_enabled boolean NOT NULL DEFAULT false,
 payouts_enabled boolean NOT NULL DEFAULT false,
 card_payments_active boolean NOT NULL DEFAULT false,
 model_verified boolean NOT NULL DEFAULT false,
 checked_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(account_id,livemode), UNIQUE(id,organization_id,unit_id,livemode)
);
CREATE UNIQUE INDEX stripe_connections_active_unit ON eshop.stripe_connections(unit_id,livemode)
 WHERE state IN ('connected','restricted');
CREATE TABLE eshop.stripe_runtime_policy (
 organization_id bigint NOT NULL REFERENCES public.organizations(id),
 livemode boolean NOT NULL,
 new_payments_enabled boolean NOT NULL DEFAULT false,
 online_admission_verified boolean NOT NULL DEFAULT false,
 reservation_policy_verified boolean NOT NULL DEFAULT false,
 dispute_policy_accepted boolean NOT NULL DEFAULT false,
 supported_surfaces text[] NOT NULL DEFAULT '{}',
 PRIMARY KEY(organization_id,livemode),
 CHECK(NOT new_payments_enabled OR (online_admission_verified AND reservation_policy_verified AND dispute_policy_accepted))
);
ALTER TABLE eshop.payment_info ADD COLUMN payment_method text NOT NULL DEFAULT 'bank'
 CHECK(payment_method IN ('bank','stripe'));
ALTER TABLE eshop.payment_info ADD COLUMN stripe_connection_id uuid REFERENCES eshop.stripe_connections(id);
ALTER TABLE eshop.payment_info ADD CONSTRAINT payment_info_stripe_identity CHECK(
 (payment_method='bank' AND stripe_connection_id IS NULL) OR
 (payment_method='stripe' AND stripe_connection_id IS NOT NULL AND bank_account IS NULL
  AND variable_symbol IS NULL AND creditor_reference IS NULL AND deposit_amount IS NULL));
CREATE TABLE eshop.stripe_checkout_attempts (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 order_id bigint NOT NULL REFERENCES eshop.orders(id),
 payment_info_id bigint NOT NULL REFERENCES eshop.payment_info(id),
 organization_id bigint NOT NULL REFERENCES public.organizations(id),
 unit_id bigint NOT NULL REFERENCES public.units(id),
 connection_id uuid NOT NULL,
 livemode boolean NOT NULL,
 amount_minor bigint NOT NULL CHECK(amount_minor>0 AND amount_minor<=9007199254740991),
 currency text NOT NULL CHECK(currency IN ('CZK','EUR','PLN','USD','GBP')),
 order_revision bigint NOT NULL,
 state text NOT NULL DEFAULT 'preparing' CHECK(state IN ('preparing','open','uncertain','paid','expired','action_required')),
 idempotency_key text NOT NULL UNIQUE CHECK(length(idempotency_key) BETWEEN 8 AND 255),
 created_at timestamptz NOT NULL DEFAULT now(), reservation_expires_at timestamptz NOT NULL,
 session_id text, payment_intent_id text, checkout_url text,
 last_synced_at timestamptz, next_reconcile_at timestamptz NOT NULL DEFAULT now(),
 reconcile_failures integer NOT NULL DEFAULT 0 CHECK(reconcile_failures>=0),
 lease_token uuid, lease_expires_at timestamptz,
 FOREIGN KEY(connection_id,organization_id,unit_id,livemode)
  REFERENCES eshop.stripe_connections(id,organization_id,unit_id,livemode),
 UNIQUE(connection_id,session_id), UNIQUE(connection_id,payment_intent_id),
 UNIQUE(id,organization_id,livemode), UNIQUE(id,connection_id,currency),
 UNIQUE(id,connection_id), UNIQUE(id,order_id),
 CHECK(reservation_expires_at>created_at),
 CHECK((lease_token IS NULL)=(lease_expires_at IS NULL))
);
CREATE UNIQUE INDEX stripe_one_active_attempt ON eshop.stripe_checkout_attempts(payment_info_id)
 WHERE state IN ('preparing','open','uncertain');
CREATE TABLE eshop.stripe_capabilities (
 token_hash text PRIMARY KEY CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 scope text NOT NULL CHECK(scope IN ('order_pay','handoff','return_read')),
 order_id bigint NOT NULL REFERENCES eshop.orders(id),
 attempt_id uuid REFERENCES eshop.stripe_checkout_attempts(id),
 generation bigint NOT NULL DEFAULT 1 CHECK(generation>0),
 expires_at timestamptz NOT NULL, revoked_at timestamptz, consumed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(attempt_id,order_id) REFERENCES eshop.stripe_checkout_attempts(id,order_id),
 CHECK(scope='order_pay' OR attempt_id IS NOT NULL),
 CHECK(scope<>'order_pay' OR consumed_at IS NULL)
);
CREATE TABLE eshop.stripe_payment_link_sources (
 token_hash text PRIMARY KEY REFERENCES eshop.stripe_capabilities(token_hash),
 sealed jsonb NOT NULL, content_hash text NOT NULL CHECK(content_hash ~ '^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
 command_id uuid NOT NULL UNIQUE
);
CREATE TABLE eshop.stripe_event_inbox (
 connection_id uuid NOT NULL REFERENCES eshop.stripe_connections(id),
 event_id text NOT NULL CHECK(event_id ~ '^evt_[A-Za-z0-9]+$'),
 body_sha256 text NOT NULL CHECK(body_sha256 ~ '^[a-f0-9]{64}$'),
 event_type text NOT NULL, provider_created_at timestamptz NOT NULL,
 received_at timestamptz NOT NULL DEFAULT now(), committed_at timestamptz,
 receipt jsonb, PRIMARY KEY(connection_id,event_id)
);
-- Successful refund facts are separate from dispute holds. No signed fake bank transactions.
CREATE TABLE eshop.stripe_payment_movements (
 connection_id uuid NOT NULL REFERENCES eshop.stripe_connections(id),
 provider_id text NOT NULL,
 attempt_id uuid NOT NULL REFERENCES eshop.stripe_checkout_attempts(id),
 kind text NOT NULL CHECK(kind IN ('payment','refund')),
 amount_minor bigint NOT NULL CHECK(amount_minor>0 AND amount_minor<=9007199254740991),
 currency text NOT NULL CHECK(currency IN ('CZK','EUR','PLN','USD','GBP')),
 occurred_at timestamptz NOT NULL, received_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(attempt_id,connection_id,currency) REFERENCES eshop.stripe_checkout_attempts(id,connection_id,currency),
 PRIMARY KEY(connection_id,provider_id,kind)
);
CREATE TABLE eshop.stripe_disputes (
 connection_id uuid NOT NULL REFERENCES eshop.stripe_connections(id),
 provider_id text NOT NULL, attempt_id uuid NOT NULL REFERENCES eshop.stripe_checkout_attempts(id),
 amount_minor bigint NOT NULL CHECK(amount_minor>0),
 status text NOT NULL CHECK(status IN ('warning_needs_response','warning_under_review','warning_closed','needs_response','under_review','won','lost')),
 observed_at timestamptz NOT NULL,
 FOREIGN KEY(attempt_id,connection_id) REFERENCES eshop.stripe_checkout_attempts(id,connection_id),
 PRIMARY KEY(connection_id,provider_id)
);
CREATE TABLE eshop.stripe_admission_decisions (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 attempt_id uuid NOT NULL REFERENCES eshop.stripe_checkout_attempts(id),
 actor uuid REFERENCES public.user_info(id),
 reason text NOT NULL CHECK(reason IN ('partial_refund_keep','partial_refund_cancel','dispute_hold','dispute_release','reconciliation_hold','reconciliation_release','full_refund','late_payment','financial_conflict')),
 ticket_ids bigint[] NOT NULL DEFAULT '{}',
 provider_revision text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE eshop.stripe_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.stripe_runtime_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.stripe_checkout_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.stripe_capabilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.stripe_payment_link_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.stripe_event_inbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.stripe_payment_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.stripe_disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.stripe_admission_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.stripe_connections,eshop.stripe_runtime_policy,eshop.stripe_checkout_attempts,
 eshop.stripe_capabilities,eshop.stripe_payment_link_sources,eshop.stripe_event_inbox,
 eshop.stripe_payment_movements,eshop.stripe_disputes,eshop.stripe_admission_decisions
 FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_stripe/capabilities.sql
-- Token creation belongs to the order transaction, never the public overview.
CREATE OR REPLACE FUNCTION public.issue_stripe_capability_internal(
 p_order bigint,p_scope text,p_expires_at timestamptz,p_attempt uuid DEFAULT NULL
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_token text; v_attempt eshop.stripe_checkout_attempts;
BEGIN
 PERFORM public.require_service_role();
 IF p_scope IS NULL OR p_scope NOT IN ('order_pay','handoff','return_read') OR
  p_expires_at IS NULL OR p_expires_at<=clock_timestamp() OR
  (p_scope<>'order_pay' AND p_attempt IS NULL) THEN RAISE EXCEPTION 'STRIPE_CAPABILITY_INVALID'; END IF;
 PERFORM 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
 WHERE o.id=p_order AND pi.payment_method='stripe' AND o.state<>'waitlisted' FOR UPDATE OF o;
 IF NOT FOUND THEN RAISE EXCEPTION 'STRIPE_CAPABILITY_INVALID'; END IF;
 IF p_attempt IS NOT NULL THEN
  SELECT * INTO v_attempt FROM eshop.stripe_checkout_attempts WHERE id=p_attempt AND order_id=p_order;
  IF NOT FOUND THEN RAISE EXCEPTION 'STRIPE_CAPABILITY_INVALID'; END IF;
 END IF;
 IF p_scope IN ('handoff','return_read') AND p_expires_at>least(v_attempt.reservation_expires_at,clock_timestamp()+interval '30 minutes') THEN
  RAISE EXCEPTION 'STRIPE_CAPABILITY_EXPIRY_INVALID'; END IF;
 v_token:=encode(extensions.gen_random_bytes(32),'hex');
 INSERT INTO eshop.stripe_capabilities(token_hash,scope,order_id,attempt_id,expires_at)
 VALUES(encode(extensions.digest(v_token,'sha256'),'hex'),p_scope,p_order,p_attempt,p_expires_at);
 RETURN v_token;
END $$;
REVOKE ALL ON FUNCTION public.issue_stripe_capability_internal(bigint,text,timestamptz,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.issue_stripe_capability_internal(bigint,text,timestamptz,uuid) TO service_role;

-- A service endpoint must choose the scope; it cannot infer it from any supplied ID.
CREATE OR REPLACE FUNCTION public.authorize_stripe_capability_internal(
 p_token text,p_scope text,p_order bigint,p_attempt uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_cap eshop.stripe_capabilities;
BEGIN
 PERFORM public.require_service_role();
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' OR p_scope IS NULL OR p_scope NOT IN ('order_pay','handoff','return_read') THEN
  RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO v_cap FROM eshop.stripe_capabilities
 WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex') AND scope=p_scope
 AND order_id=p_order AND revoked_at IS NULL AND expires_at>clock_timestamp()
 AND (p_attempt IS NULL OR attempt_id=p_attempt)
 AND (scope<>'handoff' OR consumed_at IS NULL) FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 IF p_scope='handoff' THEN UPDATE eshop.stripe_capabilities SET consumed_at=clock_timestamp() WHERE token_hash=v_cap.token_hash; END IF;
 RETURN jsonb_build_object('orderId',v_cap.order_id,'attemptId',v_cap.attempt_id,'scope',v_cap.scope,'expiresAt',v_cap.expires_at);
END $$;
REVOKE ALL ON FUNCTION public.authorize_stripe_capability_internal(text,text,bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.authorize_stripe_capability_internal(text,text,bigint,uuid) TO service_role;

-- SOURCE: eshop_transactions/payment_totals.sql
-- One financial projection over actual ledgers. External/manual settlement is
-- retained as its own fact; disputes are an availability hold, never a refund.
CREATE OR REPLACE FUNCTION public.payment_financial_totals_internal(p_payment bigint)
RETURNS TABLE(gross_received numeric,refunded numeric,external_received numeric,
 disputed numeric,net_received numeric,available numeric,invalid_identity boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH p AS (SELECT * FROM eshop.payment_info WHERE id=p_payment),
 bank AS (SELECT
  coalesce(sum(t.amount) FILTER(WHERE t.transaction_type IS DISTINCT FROM 'return'),0) received,
  abs(coalesce(sum(t.amount) FILTER(WHERE t.transaction_type='return'),0)) returned,
  coalesce(bool_or(t.currency IS DISTINCT FROM p.currency_code),false) invalid
  FROM p JOIN eshop.transactions t ON t.payment_info=p.id),
 provider AS (SELECT
  coalesce(sum(m.amount_minor) FILTER(WHERE m.kind='payment'),0)/100 received,
  coalesce(sum(m.amount_minor) FILTER(WHERE m.kind='refund'),0)/100 returned,
  coalesce(bool_or(m.connection_id IS DISTINCT FROM p.stripe_connection_id OR m.currency IS DISTINCT FROM p.currency_code::text
   OR a.order_id NOT IN(SELECT id FROM eshop.orders WHERE payment_info=p.id)),false) invalid
  FROM p JOIN eshop.stripe_checkout_attempts a ON a.payment_info_id=p.id
  JOIN eshop.stripe_payment_movements m ON m.attempt_id=a.id),
 holds AS (SELECT coalesce(sum(d.amount_minor) FILTER(WHERE d.status IN ('needs_response','under_review','lost')),0)/100 held
  FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_disputes d ON d.attempt_id=a.id WHERE a.payment_info_id=p_payment),
 totals AS (SELECT bank.received+provider.received gross,bank.returned+provider.returned returned,
  coalesce(p.paid_externally,0) external,holds.held,bank.invalid OR provider.invalid invalid
  FROM p CROSS JOIN bank CROSS JOIN provider CROSS JOIN holds)
 -- The legacy external field has no attributable movement identity/date.
 -- Preserve it explicitly, without guessing whether it overlaps stored paid.
 SELECT gross,returned,external,held,gross-returned,
  greatest(gross-returned-held,0),invalid FROM totals;
$$;
REVOKE ALL ON FUNCTION public.payment_financial_totals_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.refresh_payment_info_totals_internal(p_payment bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE totals record;
BEGIN
 PERFORM 1 FROM eshop.payment_info WHERE id=p_payment FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PAYMENT_INFO_NOT_FOUND'; END IF;
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(p_payment);
 IF totals.invalid_identity THEN RAISE EXCEPTION 'PAYMENT_FACT_IDENTITY_MISMATCH'; END IF;
 UPDATE eshop.payment_info SET paid=totals.gross_received,returned=totals.refunded WHERE id=p_payment;
 -- paid_externally is deliberately not rewritten or converted into a bank movement.
END $$;
REVOKE ALL ON FUNCTION public.refresh_payment_info_totals_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

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

  IF p_actor_kind='user' THEN
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
    IF v_target.payment_method='stripe' THEN RAISE EXCEPTION 'STRIPE_BANK_PAIRING_UNSUPPORTED'; END IF;
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
