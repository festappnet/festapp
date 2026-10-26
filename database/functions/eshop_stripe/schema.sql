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
