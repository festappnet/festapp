-- Explicit term semantics. Sales windows retain their existing meaning.
ALTER TABLE public.forms ADD COLUMN term_start_at timestamptz, ADD COLUMN term_end_at timestamptz;
ALTER TABLE public.forms ADD CONSTRAINT forms_term_interval CHECK(term_end_at IS NULL OR (term_start_at IS NOT NULL AND term_end_at>term_start_at));
CREATE TABLE eshop.customer_order_change_capabilities (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(), token_hash text UNIQUE NOT NULL CHECK(token_hash~'^[a-f0-9]{64}$'),
 parent_hash text NOT NULL REFERENCES eshop.waitlist_capabilities(token_hash) ON DELETE CASCADE,
 organization_id bigint NOT NULL REFERENCES public.organizations(id), form_id bigint NOT NULL REFERENCES public.forms(id) ON DELETE CASCADE,
 order_id bigint NOT NULL REFERENCES eshop.orders(id) ON DELETE CASCADE, operation text NOT NULL CHECK(operation IN ('edit','cancel','move','withdraw')),
 proposal_hash text NOT NULL, policy_revision bigint NOT NULL, feature_epoch bigint NOT NULL,
 expires_at timestamptz NOT NULL, revoked_at timestamptz, consumed_by uuid, consumed_form_id bigint REFERENCES public.forms(id),
 preview_hash text, preview_expires_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE eshop.customer_order_change_sources (
 capability_id uuid PRIMARY KEY REFERENCES eshop.customer_order_change_capabilities(id) ON DELETE CASCADE,
 sealed jsonb NOT NULL, content_hash text NOT NULL
);
CREATE TABLE eshop.customer_order_change_attempts (
 order_id bigint NOT NULL REFERENCES eshop.orders(id) ON DELETE CASCADE, ip_hash text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX customer_order_change_attempts_order_time ON eshop.customer_order_change_attempts(order_id,created_at);
CREATE INDEX customer_order_change_attempts_ip_time ON eshop.customer_order_change_attempts(ip_hash,created_at);
CREATE TABLE eshop.customer_order_change_limits (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton), minimum_seconds integer NOT NULL CHECK(minimum_seconds>=60),
 hourly_limit integer NOT NULL CHECK(hourly_limit BETWEEN 1 AND 3)
);
INSERT INTO eshop.customer_order_change_limits VALUES(true,60,3);
-- Working evidence only. The existing refund_requests/settlements remain the
-- sole refund intent/fact owners. No amount is copied into this request table.
CREATE TABLE eshop.customer_order_change_requests (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(), order_id bigint NOT NULL REFERENCES eshop.orders(id) ON DELETE CASCADE,
 organization_id bigint NOT NULL REFERENCES public.organizations(id), operation text NOT NULL CHECK(operation IN ('cancel','move')),
 status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','approved','rejected','withdrawn','resolved')),
 ticket_ids bigint[],
 reason text CHECK(length(reason)<=2000), target_form_id bigint REFERENCES public.forms(id) ON DELETE SET NULL,
 customer_command uuid UNIQUE NOT NULL REFERENCES public.client_mutation_receipts(command_id),
 decision_command uuid REFERENCES public.client_mutation_receipts(command_id), response text CHECK(length(response)<=2000),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 decided_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);
CREATE UNIQUE INDEX customer_order_change_one_open_request ON eshop.customer_order_change_requests(order_id,operation) WHERE status='open';
CREATE TABLE eshop.customer_order_change_events (
 command_id uuid PRIMARY KEY REFERENCES public.client_mutation_receipts(command_id), order_id bigint NOT NULL REFERENCES eshop.orders(id) ON DELETE CASCADE,
 operation text NOT NULL, outcome text NOT NULL, request_id uuid REFERENCES eshop.customer_order_change_requests(id),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE eshop.customer_order_change_capabilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.customer_order_change_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.customer_order_change_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.customer_order_change_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.customer_order_change_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.customer_order_change_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.customer_order_change_capabilities,eshop.customer_order_change_sources,
 eshop.customer_order_change_attempts,eshop.customer_order_change_limits,eshop.customer_order_change_requests,
 eshop.customer_order_change_events FROM PUBLIC,anon,authenticated,service_role;
