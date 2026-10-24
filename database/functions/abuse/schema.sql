-- Policy is configuration; usage identities never include policy revision or domain FKs.
CREATE TABLE public.abuse_policy_revision (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton), revision bigint NOT NULL CHECK(revision>0)
);
INSERT INTO public.abuse_policy_revision VALUES(true,1);
CREATE TABLE public.abuse_policy_rules (
 rule_key text PRIMARY KEY, budget_key text NOT NULL,
 measure_unit text NOT NULL DEFAULT 'operations' CHECK(measure_unit IN ('operations','items','bytes','seconds')),
 scope_kind text NOT NULL CHECK(scope_kind IN ('actor','unit','organization','recipient','global')),
 kind text NOT NULL CHECK(kind IN ('rolling','cumulative','occupancy','bytes','duration','items')),
 window_seconds integer, bucket_seconds integer,
 base_limit bigint NOT NULL CHECK(base_limit>0), hard_cap bigint NOT NULL CHECK(hard_cap>=base_limit AND hard_cap<=1000000000000),
 growth_basis text NOT NULL DEFAULT 'none' CHECK(growth_basis IN ('none','existing_orders')),
 growth_increment integer NOT NULL DEFAULT 0 CHECK(growth_increment BETWEEN 0 AND 100),
 CHECK((kind='rolling' AND window_seconds IN (60,600,900,86400) AND bucket_seconds IN (60,300,3600) AND window_seconds%bucket_seconds=0 AND window_seconds/bucket_seconds<=288)
 OR (kind IN ('cumulative','occupancy','bytes','duration','items') AND window_seconds IS NULL AND bucket_seconds IS NULL)),
 CHECK(growth_basis<>'none' OR growth_increment=0)
);
CREATE TABLE public.abuse_policy_overrides (
 rule_key text NOT NULL REFERENCES public.abuse_policy_rules,
 target_kind text NOT NULL CHECK(target_kind IN ('unit','organization')), target_id bigint NOT NULL,
 base_limit bigint NOT NULL CHECK(base_limit>0), expires_at timestamptz NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 8 AND 1000), author text NOT NULL,
 PRIMARY KEY(rule_key,target_kind,target_id)
);
CREATE TABLE public.abuse_policy_audit (
 revision bigint PRIMARY KEY, occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 author text NOT NULL, reason text NOT NULL, previous jsonb NOT NULL, replacement jsonb NOT NULL
);
CREATE TABLE public.abuse_budget_usage (
 rule_key text NOT NULL, scope_id text NOT NULL CHECK(length(scope_id) BETWEEN 1 AND 160),
 bucket_at timestamptz NOT NULL, amount bigint NOT NULL CHECK(amount>0), expires_at timestamptz NOT NULL,
 PRIMARY KEY(rule_key,scope_id,bucket_at)
);
CREATE INDEX abuse_budget_usage_expiry_idx ON public.abuse_budget_usage(expires_at);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['abuse_policy_revision','abuse_policy_rules','abuse_policy_overrides','abuse_policy_audit','abuse_budget_usage'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated,service_role',t);
 END LOOP;
END $$;
-- Persistent pseudonymization key, generated once. Changing encryption/wrapping must
-- preserve this logical key; rotating it requires a dual-read usage migration.
CREATE TABLE public.abuse_identity_key(singleton boolean PRIMARY KEY CHECK(singleton), secret bytea NOT NULL);
INSERT INTO public.abuse_identity_key VALUES(true,extensions.gen_random_bytes(32));
ALTER TABLE public.abuse_identity_key ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.abuse_identity_key FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE public.email_messages ADD COLUMN last_claimed_at timestamptz;
ALTER TABLE public.email_messages ADD COLUMN producer_actor uuid;
ALTER TABLE public.email_messages ADD COLUMN admission_class text NOT NULL DEFAULT 'ordinary' CHECK(admission_class IN ('ordinary','auth','commitment'));
CREATE INDEX email_last_org_claim ON public.email_messages(organization,last_claimed_at DESC) WHERE last_claimed_at IS NOT NULL;
CREATE INDEX email_last_unit_claim ON public.email_messages(unit,last_claimed_at DESC) WHERE last_claimed_at IS NOT NULL;
CREATE INDEX email_pending_org ON public.email_messages(organization,id) WHERE workflow_state IN ('pending','blocked','preparing','sending','retry_wait','unknown');
CREATE INDEX email_pending_unit ON public.email_messages(unit,id) WHERE workflow_state IN ('pending','blocked','preparing','sending','retry_wait','unknown');
-- Existing order states own unresolved obligations; accepted delivery projects to sent.
CREATE INDEX orders_email_obligations ON eshop.orders(occasion,id)
 WHERE state IN ('ordered','created','expired','waitlisted','paid');
CREATE INDEX email_order_version_receipt ON public.email_messages(order_id,message_kind,source_version,workflow_state);
CREATE INDEX occasion_setup_drafts_org_idx ON public.occasion_setup_drafts(organization);
-- Derived, bounded-lifetime growth evidence. Never count delivery history on enqueue.
CREATE TABLE public.abuse_unit_evidence (
 unit bigint PRIMARY KEY REFERENCES public.units(id) ON DELETE CASCADE,
 verified_orders bigint NOT NULL CHECK(verified_orders>=0),
 measured_at timestamptz NOT NULL
);
ALTER TABLE public.abuse_unit_evidence ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.abuse_unit_evidence FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX bank_identity_transaction_evidence ON eshop.bank_transaction_identities(transaction_id);

CREATE INDEX email_last_auth_claim ON public.email_messages(organization,last_claimed_at DESC) WHERE unit IS NULL AND last_claimed_at IS NOT NULL;
-- Existing push log/outbox remain the owners; no parallel queue or receipt table.
ALTER TABLE public.log_notifications ADD COLUMN abuse_admitted_at timestamptz;
ALTER TABLE public.log_notifications ALTER COLUMN abuse_admitted_at SET DEFAULT statement_timestamp();
ALTER TABLE public.news_notification_outbox ADD COLUMN abuse_admitted_at timestamptz;
REVOKE UPDATE ON public.log_notifications FROM PUBLIC,anon,authenticated;
